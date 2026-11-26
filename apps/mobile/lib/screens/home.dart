import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../design/chibi_avatar.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'onboarding.dart';
import 'quiz_hub.dart';
import 'safety_center.dart';
import 'sign_in.dart';

class _GameInfo {
  const _GameInfo(this.id, this.name, this.emoji, this.color,
      {this.playable = false, this.desc});
  final String id;
  final String name;
  final String emoji;
  final Color color;
  final bool playable;
  final String? desc;
}

final _games = [
  _GameInfo('quiz', S.of('game_quiz'), '🧠', Tokens.sky,
      playable: true, desc: S.of('game_quiz_desc')),
  const _GameInfo('football', 'تحديات الكورة', '⚽', Tokens.mint),
  const _GameInfo('spy', 'الجاسوس', '🕵️', Tokens.grape),
  const _GameInfo('stop', 'أتوبيس كومبليت', '🚌', Tokens.sun),
  const _GameInfo('liar', 'مين الكداب؟', '🤥', Tokens.coral),
  const _GameInfo('who', 'مين فينا؟', '👀', Color(0xFFF472B6)),
  const _GameInfo('draw', 'ارسم وخمّن', '🎨', Tokens.sky),
  const _GameInfo('emoji', 'خمّن بالإيموجي', '😎', Tokens.sun),
  const _GameInfo('memory', 'تحديات الذاكرة', '🧩', Tokens.mint),
  const _GameInfo('acting', 'مثّل وخمّن', '🎭', Tokens.grape),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, _GameInfo g) {
    final app = AppScope.read(context);
    if (!app.signedIn) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SignInScreen()));
    } else if (!app.canPlay) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const QuizHubScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final user = app.user;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                Tokens.s16, Tokens.s16, Tokens.s16, Tokens.s8),
            sliver: SliverToBoxAdapter(
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppConfig.appName,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(color: Tokens.grape)),
                        Text(S.of('tagline'),
                            style: const TextStyle(color: Tokens.inkSoft)),
                      ]),
                ),
                if (user != null)
                  PopupMenuButton<String>(
                    tooltip: user.displayName ?? '',
                    onSelected: (v) {
                      if (v == 'safety') {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const SafetyCenterScreen()));
                      }
                      if (v == 'out') app.signOut();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'safety', child: Text(S.of('safetyCenter'))),
                      PopupMenuItem(value: 'out', child: Text(S.of('signOut'))),
                    ],
                    child: ChibiAvatar(avatarId: user.avatarId, size: 48),
                  )
                else
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SignInScreen())),
                    child: Text(S.of('signIn')),
                  ),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
            sliver: SliverToBoxAdapter(
                child: _FeaturedCard(
                    game: _games.first,
                    onPlay: () => _open(context, _games.first))),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                Tokens.s16, Tokens.s24, Tokens.s16, Tokens.s8),
            sliver: SliverToBoxAdapter(
                child: Text(S.of('games'),
                    style: Theme.of(context).textTheme.titleLarge)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                Tokens.s16, 0, Tokens.s16, Tokens.s24),
            sliver: SliverGrid.count(
              crossAxisCount: 3,
              mainAxisSpacing: Tokens.s12,
              crossAxisSpacing: Tokens.s12,
              childAspectRatio: 0.72,
              children: [for (final g in _games.skip(1)) _GameTile(game: g)],
            ),
          ),
        ]),
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.game, required this.onPlay});
  final _GameInfo game;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Tokens.s16),
      decoration: const BoxDecoration(
          color: Tokens.night, borderRadius: BorderRadius.all(Tokens.r24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: game.color,
                borderRadius: const BorderRadius.all(Tokens.r16)),
            child: Text(game.emoji, style: const TextStyle(fontSize: 34)),
          ),
          const SizedBox(width: Tokens.s12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(game.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(game.desc ?? '',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
            ]),
          ),
        ]),
        const SizedBox(height: Tokens.s16),
        GameButton(
            label: S.of('play'),
            icon: Icons.play_arrow_rounded,
            color: Tokens.sun,
            onPressed: onPlay),
      ]),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.game});
  final _GameInfo game;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${game.name}، ${S.of('comingSoon')}',
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.all(Tokens.r16),
          border: Border.all(color: Tokens.ink.withValues(alpha: 0.06)),
        ),
        padding: const EdgeInsets.all(Tokens.s8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: game.color.withValues(alpha: 0.18),
                borderRadius: const BorderRadius.all(Tokens.r16)),
            child: Text(game.emoji, style: const TextStyle(fontSize: 28)),
          ),
          const SizedBox(height: Tokens.s8),
          Flexible(
            child: Text(game.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(height: 4),
          Pill(text: S.of('comingSoon'), color: Tokens.inkSoft),
        ]),
      ),
    );
  }
}
