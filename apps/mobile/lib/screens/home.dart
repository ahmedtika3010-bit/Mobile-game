import 'package:flutter/material.dart';

import '../app_state.dart';
import '../design/chibi_avatar.dart';
import '../design/sfx.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'onboarding.dart';
import 'game_hub.dart';
import 'safety_center.dart';
import 'sign_in.dart';

class _GameInfo {
  const _GameInfo(this.id, this.name, this.emoji, this.color,
      {this.playable = false,
      this.desc,
      this.gradient = const [],
      this.tags = const []});
  final String id;
  final String name;
  final String emoji;
  final Color color;
  final bool playable;
  final String? desc;
  final List<Color> gradient;
  final List<(String, String)> tags;
}

final _games = [
  _GameInfo('quiz', S.of('game_quiz'), '🧠', Tokens.sky,
      playable: true,
      desc: S.of('game_quiz_desc'),
      gradient: const [
        Color(0xFF3DA5FF),
        Color(0xFF6A5CFF),
        Color(0xFF9B4DFF)
      ],
      tags: [
        ('👥', S.of('tagPlayers')),
        ('⏱️', S.of('tagQuick')),
        ('🏆', S.of('tagRanked')),
      ]),
  _GameInfo('spy', S.of('game_spy'), '🕵️', Tokens.grape,
      playable: true,
      desc: S.of('game_spy_desc'),
      gradient: const [
        Color(0xFFFF5E8A),
        Color(0xFF9B4DFF),
        Color(0xFF3A1F86)
      ],
      tags: [
        ('👥', S.of('tagSpyPlayers')),
        ('🤫', S.of('tagSecretRoles')),
        ('🗳️', S.of('tagVoting')),
      ]),
  _GameInfo('liar', S.of('game_liar'), '🤥', Tokens.coral,
      playable: true,
      desc: S.of('game_liar_desc'),
      gradient: const [
        Color(0xFFFFB03D),
        Color(0xFFFF5A7A),
        Color(0xFFB0328F)
      ],
      tags: [
        ('👥', S.of('tagSpyPlayers')),
        ('🔁', S.of('tagLiarRounds')),
        ('🗳️', S.of('tagVoting')),
      ]),
  _GameInfo('who', S.of('game_who'), '👀', Tokens.pink,
      playable: true,
      desc: S.of('game_who_desc'),
      gradient: const [
        Color(0xFFFF6FD8),
        Color(0xFF8E5BFF),
        Color(0xFF3DA5FF)
      ],
      tags: [
        ('👥', S.of('tagWhoPlayers')),
        ('🤫', S.of('tagAnonymous')),
        ('😄', S.of('tagNoLosers')),
      ]),
  _GameInfo('emoji', S.of('game_emoji'), '😎', Tokens.sun,
      playable: true,
      desc: S.of('game_emoji_desc'),
      gradient: const [
        Color(0xFFFFC93D),
        Color(0xFFFF8A3D),
        Color(0xFFFF4F7B)
      ],
      tags: [
        ('👥', S.of('tagPlayers')),
        ('😎', S.of('tagEmojiCats')),
        ('🏆', S.of('tagRanked')),
      ]),
  _GameInfo('stop', S.of('game_stop'), '🚌', Tokens.orange,
      playable: true,
      desc: S.of('game_stop_desc'),
      gradient: const [
        Color(0xFF34D399),
        Color(0xFF16A2B8),
        Color(0xFF3D5AFE)
      ],
      tags: [
        ('👥', S.of('tagPlayers')),
        ('🔤', S.of('tagStopLetters')),
        ('✋', S.of('tagStopAppeal')),
      ]),
  _GameInfo('memory', S.of('game_memory'), '🧩', Tokens.mint,
      playable: true,
      desc: S.of('game_memory_desc'),
      gradient: const [
        Color(0xFF7BE8C8),
        Color(0xFF3DA5FF),
        Color(0xFF7A4DFF)
      ],
      tags: [
        ('👥', S.of('tagPlayers')),
        ('🧠', S.of('tagMemModes')),
        ('⏱️', S.of('tagFairTime')),
      ]),
  const _GameInfo('football', 'تحديات الكورة', '⚽', Tokens.mint),
  const _GameInfo('draw', 'ارسم وخمّن', '🎨', Tokens.sky),
  const _GameInfo('acting', 'مثّل وخمّن', '🎭', Tokens.grape),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _open(BuildContext context, String gameId) async {
    final app = AppScope.read(context);
    final nav = Navigator.of(context);
    if (!app.signedIn) {
      await nav.push(SoftRoute(const SignInScreen()));
    } else if (!app.canPlay) {
      await nav.push(SoftRoute(const OnboardingScreen()));
    } else {
      await nav.push(SoftRoute(GameHubScreen(gameId: gameId)));
      app.refreshWallet();
    }
  }

  void _profileSheet(BuildContext context) {
    final app = AppScope.read(context);
    final u = app.user!;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(Tokens.s24, 0, Tokens.s24, Tokens.s24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ChibiAvatar(avatarId: u.avatarId, size: 96),
            const SizedBox(height: Tokens.s8),
            Text(u.displayName ?? '',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: Tokens.s16),
            _SheetAction(
                icon: Icons.shield_rounded,
                color: Tokens.mint,
                label: S.of('safetyCenter'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context)
                      .push(SoftRoute(const SafetyCenterScreen()));
                }),
            const SizedBox(height: Tokens.s8),
            StatefulBuilder(
              builder: (ctx, setSheet) => _SheetAction(
                  icon: Sfx.enabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  color: Tokens.sky,
                  label: S.of(Sfx.enabled ? 'soundOff' : 'soundOn'),
                  onTap: () async {
                    await Sfx.setEnabled(!Sfx.enabled);
                    setSheet(() {});
                  }),
            ),
            const SizedBox(height: Tokens.s8),
            _SheetAction(
                icon: Icons.logout_rounded,
                color: Tokens.coral,
                label: S.of('signOut'),
                onTap: () {
                  Navigator.pop(ctx);
                  app.signOut();
                }),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final user = app.user;
    final w = app.wallet;
    return NightScaffold(
      showBack: false,
      body: CustomScrollView(slivers: [
        SliverPadding(
          padding:
              const EdgeInsets.fromLTRB(Tokens.s20, Tokens.s16, Tokens.s20, 0),
          sliver: SliverToBoxAdapter(
            child: Row(children: [
              const Flexible(
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Logo(size: 30)),
              ),
              const Spacer(),
              if (user != null)
                Pressable(
                  semanticLabel: user.displayName,
                  onTap: () => _profileSheet(context),
                  child: Container(
                    padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 14, 4),
                    decoration: const BoxDecoration(
                      color: Tokens.glass,
                      borderRadius: BorderRadius.all(Radius.circular(99)),
                      border: Border.fromBorderSide(
                          BorderSide(color: Tokens.glassBorder)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      ChibiAvatar(avatarId: user.avatarId, size: 36),
                      const SizedBox(width: Tokens.s8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: Text(user.displayName ?? '',
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ]),
                  ),
                )
              else
                GameButton(
                  label: S.of('signIn'),
                  expand: false,
                  size: GameButtonSize.medium,
                  color: Tokens.grape,
                  onPressed: () => Navigator.of(context)
                      .push(SoftRoute(const SignInScreen())),
                ),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              Tokens.s20, Tokens.s24, Tokens.s20, Tokens.s16),
          sliver: SliverToBoxAdapter(
            child: FadeSlideIn(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        user?.displayName != null
                            ? '${S.of('homeHello')} ${user!.displayName} 👋'
                            : S.of('homeGuest'),
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 2),
                    Text(S.of('homeSub'),
                        style: const TextStyle(
                            color: Tokens.textDim, fontSize: 15)),
                    if (w != null) ...[
                      const SizedBox(height: Tokens.s12),
                      Wrap(
                          spacing: Tokens.s8,
                          runSpacing: Tokens.s8,
                          children: [
                            Pill(
                                emoji: '⭐',
                                text: '${S.of('level')} ${w['level'] ?? 1}',
                                color: Tokens.sun),
                            Pill(
                                emoji: '🪙',
                                text: '${w['coins'] ?? 0}',
                                color: Tokens.orange),
                            Pill(
                                emoji: '💎',
                                text: '${w['gems'] ?? 0}',
                                color: Tokens.sky),
                          ]),
                    ],
                  ]),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s20),
          sliver: SliverList.list(children: [
            for (final (i, g) in _games.where((g) => g.playable).indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : Tokens.s20),
                child: FadeSlideIn(
                    delay: Duration(milliseconds: 120 + i * 80),
                    child: _FeaturedCard(
                        key: Key('featured_${g.id}'),
                        game: g,
                        onPlay: () => _open(context, g.id))),
              ),
          ]),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              Tokens.s20, Tokens.s32, Tokens.s20, Tokens.s12),
          sliver: SliverToBoxAdapter(
            child: Row(children: [
              Flexible(
                child: Text(S.of('comingSoonTitle'),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              const SizedBox(width: Tokens.s8),
              Pill(
                  text: '${_games.where((g) => !g.playable).length}',
                  color: Tokens.pink),
            ]),
          ),
        ),
        SliverPadding(
          padding:
              const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s32),
          sliver: SliverGrid.count(
            crossAxisCount: 3,
            mainAxisSpacing: Tokens.s12,
            crossAxisSpacing: Tokens.s12,
            childAspectRatio: 0.82,
            children: [
              for (final (i, g) in _games.where((g) => !g.playable).indexed)
                FadeSlideIn(
                    delay: Duration(milliseconds: 200 + i * 50),
                    child: _ComingTile(game: g)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction(
      {required this.icon,
      required this.color,
      required this.label,
      required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        child: GlassCard(
          padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s16, vertical: Tokens.s12),
          radius: Tokens.r20,
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: const BorderRadius.all(Tokens.r12)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: Tokens.s12),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16))),
            const Icon(Icons.chevron_left_rounded, color: Tokens.textFaint),
          ]),
        ),
      );
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({super.key, required this.game, required this.onPlay});
  final _GameInfo game;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Tokens.r32),
        gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: game.gradient),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: game.gradient.last.withValues(alpha: 0.45),
              blurRadius: 30,
              offset: const Offset(0, 14)),
        ],
      ),
      child: Stack(children: [
        // Decorative bubbles.
        PositionedDirectional(
            top: -40, start: -30, child: _Circle(size: 150, alpha: 0.10)),
        PositionedDirectional(
            bottom: 60, end: -40, child: _Circle(size: 120, alpha: 0.08)),
        PositionedDirectional(
          top: 18,
          end: 14,
          child: Bob(
            amplitude: 7,
            child: Transform.rotate(
              angle: -0.12,
              child: Text(game.emoji, style: const TextStyle(fontSize: 84)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Tokens.s20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Pill(
                text: S.of(game.id != 'quiz' ? 'newTag' : 'popularTag'),
                emoji: game.id != 'quiz' ? '✨' : '🔥',
                color: Colors.white,
                solid: true),
            const SizedBox(height: Tokens.s12),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 110),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(game.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            height: 1.15,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: Tokens.s4),
                    Text(game.desc ?? '',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 15,
                            height: 1.4)),
                  ]),
            ),
            const SizedBox(height: Tokens.s16),
            Wrap(spacing: Tokens.s8, runSpacing: Tokens.s8, children: [
              for (final (emoji, text) in game.tags)
                _Tag(emoji: emoji, text: text),
            ]),
            const SizedBox(height: Tokens.s20),
            GameButton(
                label: S.of('playNow'),
                icon: Icons.play_arrow_rounded,
                color: Tokens.sun,
                onPressed: onPlay),
          ]),
        ),
      ]),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.size, required this.alpha});
  final double size;
  final double alpha;
  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha)));
}

class _Tag extends StatelessWidget {
  const _Tag({required this.emoji, required this.text});
  final String emoji;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.16),
          borderRadius: const BorderRadius.all(Radius.circular(99)),
        ),
        child: Text('$emoji  $text',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13)),
      );
}

class _ComingTile extends StatelessWidget {
  const _ComingTile({required this.game});
  final _GameInfo game;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${game.name}، ${S.of('comingSoon')}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Tokens.r24),
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                game.color.withValues(alpha: 0.30),
                game.color.withValues(alpha: 0.10),
              ]),
          border:
              Border.all(color: game.color.withValues(alpha: 0.35), width: 1.2),
        ),
        padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
        child: Column(children: [
          Expanded(
            child: Center(
                child: Text(game.emoji, style: const TextStyle(fontSize: 38))),
          ),
          Text(game.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13.5, height: 1.3)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: const BorderRadius.all(Radius.circular(99))),
            child: Text('🔒 ${S.of('comingSoon')}',
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Tokens.textDim)),
          ),
        ]),
      ),
    );
  }
}
