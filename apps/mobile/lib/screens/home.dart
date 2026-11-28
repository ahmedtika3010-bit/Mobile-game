import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sahra_client/sahra_client.dart';

import '../app_state.dart';
import '../design/chibi_avatar.dart';
import '../design/cosmetics.dart';
import '../design/sfx.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'achievements.dart';
import 'leaderboards.dart';
import 'missions.dart';
import 'onboarding.dart';
import 'shop.dart';
import 'room.dart';
import 'friends.dart';
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
  _GameInfo('draw', S.of('game_draw'), '🎨', Tokens.sky,
      playable: true,
      desc: S.of('game_draw_desc'),
      gradient: const [
        Color(0xFF6FD3FF),
        Color(0xFF3D7BFF),
        Color(0xFFB04DFF)
      ],
      tags: [
        ('👥', S.of('tagPlayers')),
        ('🔁', S.of('tagDrawTurns')),
        ('🤝', S.of('tagDrawTeams')),
      ]),
  _GameInfo('football', S.of('game_football'), '⚽', Tokens.mint,
      playable: true,
      desc: S.of('game_football_desc'),
      gradient: const [
        Color(0xFF2BD67B),
        Color(0xFF0FA37F),
        Color(0xFF1F6FD1)
      ],
      tags: [
        ('👥', S.of('tagPlayers')),
        ('⚽', S.of('tagFbModes')),
        ('⚔️', S.of('tagFbDuel')),
      ]),
  _GameInfo('acting', S.of('game_acting'), '🎭', Tokens.grape,
      playable: true,
      desc: S.of('game_acting_desc'),
      gradient: const [
        Color(0xFFFF8BD1),
        Color(0xFFB04DFF),
        Color(0xFF5B3DFF)
      ],
      tags: [
        ('👥', S.of('tagPlayers')),
        ('🤸', S.of('tagActMoves')),
        ('📵', S.of('tagActNoCamera')),
      ]),
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

  static const _hubs = [
    ('missions', '🎯', 'hubMissions', Tokens.sun),
    ('shop', '🛍️', 'hubShop', Tokens.pink),
    ('achievements', '🏆', 'hubAchievements', Tokens.grape),
    ('leaderboards', '📊', 'hubLeaderboards', Tokens.sky),
  ];

  Future<void> _openHub(BuildContext context, String id) async {
    final app = AppScope.read(context);
    final nav = Navigator.of(context);
    if (!app.signedIn) {
      await nav.push(SoftRoute(const SignInScreen()));
      return;
    }
    if (!app.canPlay) {
      await nav.push(SoftRoute(const OnboardingScreen()));
      return;
    }
    final Widget screen = switch (id) {
      'missions' => const MissionsScreen(),
      'shop' => const ShopScreen(),
      'achievements' => const AchievementsScreen(),
      _ => const LeaderboardsScreen(),
    };
    await nav.push(SoftRoute(screen));
    app.refreshWallet();
    app.refreshProgress();
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
              if (app.canPlay) ...[
                _FriendsButton(count: app.friendRequests),
                const SizedBox(width: Tokens.s8),
              ],
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
                      ChibiAvatar(
                          avatarId: user.avatarId,
                          size: 36,
                          frame: MyLooks.frame),
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
        if (app.invites.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                Tokens.s20, Tokens.s16, Tokens.s20, 0),
            sliver: SliverList.list(children: [
              for (final i in app.invites)
                InviteCard(key: ValueKey(i.id), invite: i),
            ]),
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
          padding:
              const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s20),
          sliver: SliverToBoxAdapter(
            child: FadeSlideIn(
              delay: const Duration(milliseconds: 40),
              child: Column(children: [
                Row(children: [
                  for (final (i, h) in _hubs.indexed) ...[
                    if (i > 0) const SizedBox(width: Tokens.s8),
                    Expanded(
                      child: _HubTile(
                        key: Key('hub_${h.$1}'),
                        emoji: h.$2,
                        label: S.of(h.$3),
                        color: h.$4,
                        badge: switch (h.$1) {
                          'missions' => app.progress.missionsReady,
                          'achievements' => app.progress.achievementsReady,
                          _ => 0,
                        },
                        onTap: () => _openHub(context, h.$1),
                      ),
                    ),
                  ],
                ]),
                if (app.canPlay && app.progress.loginReady) ...[
                  const SizedBox(height: Tokens.s12),
                  _GiftBanner(onTap: () => _openHub(context, 'missions')),
                ],
              ]),
            ),
          ),
        ),
        SliverPadding(
          padding:
              const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s20),
          sliver: SliverToBoxAdapter(
            child: FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: _NightCard(
                    key: const Key('nightCard'),
                    ready: () async {
                      if (app.canPlay) return true;
                      await _open(context, 'quiz');
                      return false;
                    })),
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

class _FriendsButton extends StatelessWidget {
  const _FriendsButton({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Pressable(
        key: const Key('friendsButton'),
        semanticLabel: S.of('friends'),
        onTap: () async {
          final app = AppScope.read(context);
          await Navigator.of(context).push(SoftRoute(const FriendsScreen()));
          app.pingFriends();
        },
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Tokens.glass,
              shape: BoxShape.circle,
              border:
                  Border.fromBorderSide(BorderSide(color: Tokens.glassBorder)),
            ),
            child: const Text('👥', style: TextStyle(fontSize: 21)),
          ),
          if (count > 0)
            PositionedDirectional(
              top: -4,
              end: -4,
              child: PopIn(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: Tokens.coral,
                      borderRadius: BorderRadius.all(Radius.circular(99))),
                  child: Text('$count',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w900)),
                ),
              ),
            ),
        ]),
      );
}

/// Game Night: one room for the whole evening, started or joined from home.
class _NightCard extends StatefulWidget {
  const _NightCard({super.key, required this.ready});

  /// Sends the player to sign in or onboarding first; true when they can play.
  final Future<bool> Function() ready;

  @override
  State<_NightCard> createState() => _NightCardState();
}

class _NightCardState extends State<_NightCard> {
  String? _busy;
  String? _error;

  Future<void> _go(
      String what, Future<GameSession> Function(AppState) f) async {
    if (!await widget.ready() || !mounted) return;
    setState(() {
      _busy = what;
      _error = null;
    });
    final app = AppScope.read(context);
    try {
      final session = await f(app);
      if (!mounted) return;
      await Navigator.of(context).push(SoftRoute(RoomScreen(session: session)));
      app.refreshWallet();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error =
            e.code == 'room_not_found' ? S.of('roomNotFound') : S.of('error'));
      }
    } catch (_) {
      if (mounted) setState(() => _error = S.of('error'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _joinDialog() async {
    if (!await widget.ready() || !mounted) return;
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of('haveCode')),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
            TextInputFormatter.withFunction(
                (o, n) => n.copyWith(text: n.text.toUpperCase())),
          ],
          style: const TextStyle(
              fontFamily: Tokens.body,
              fontSize: 22,
              letterSpacing: 6,
              fontWeight: FontWeight.w900),
          decoration: InputDecoration(
              hintText: 'ABC123', labelText: S.of('roomCode'), counterText: ''),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.of('friendsCancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text(S.of('join'))),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    await _go(
        'join',
        (a) => GameSession.joinByCode(a.api, a.client,
            gameId: nightId, code: code));
  }

  @override
  Widget build(BuildContext context) {
    final idle = _busy == null;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Tokens.r32),
        gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF2B1B5E), Color(0xFF6C3FD1), Color(0xFFE0569B)]),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF6C3FD1).withValues(alpha: 0.45),
              blurRadius: 30,
              offset: const Offset(0, 14)),
        ],
      ),
      child: Stack(children: [
        PositionedDirectional(
            top: -40, start: -30, child: _Circle(size: 150, alpha: 0.10)),
        const PositionedDirectional(
          top: 14,
          end: 14,
          child: Bob(
            amplitude: 6,
            child: Text('🌙', style: TextStyle(fontSize: 76)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Tokens.s20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Pill(
                text: S.of('newTag'),
                emoji: '✨',
                color: Colors.white,
                solid: true),
            const SizedBox(height: Tokens.s12),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 96),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.of('night'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            height: 1.15,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: Tokens.s4),
                    Text(S.of('nightDesc'),
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 15,
                            height: 1.4)),
                  ]),
            ),
            const SizedBox(height: Tokens.s16),
            Wrap(spacing: Tokens.s8, runSpacing: Tokens.s8, children: [
              _Tag(emoji: '🎲', text: S.of('nightTag1')),
              _Tag(emoji: '🗳️', text: S.of('nightTag2')),
              _Tag(emoji: '🏆', text: S.of('nightTag3')),
            ]),
            const SizedBox(height: Tokens.s20),
            Row(children: [
              Expanded(
                flex: 3,
                child: GameButton(
                    key: const Key('nightStart'),
                    label: S.of('nightStart'),
                    icon: Icons.nightlight_round,
                    color: Tokens.sun,
                    busy: _busy == 'start',
                    onPressed: idle
                        ? () => _go(
                            'start',
                            (a) => GameSession.createPrivate(a.api, a.client,
                                gameId: nightId))
                        : null),
              ),
              const SizedBox(width: Tokens.s12),
              Expanded(
                flex: 2,
                child: GameButton(
                    key: const Key('nightJoin'),
                    label: S.of('nightJoinCode'),
                    color: Tokens.sky,
                    busy: _busy == 'join',
                    onPressed: idle ? _joinDialog : null),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: Tokens.s12),
              Text(_error!,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile(
      {super.key,
      required this.emoji,
      required this.label,
      required this.color,
      required this.onTap,
      this.badge = 0});
  final String emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: badge > 0 ? '$label ($badge)' : label,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          height: 82,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Tokens.r20),
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.32),
                  color.withValues(alpha: 0.12)
                ]),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13)),
            ),
          ]),
        ),
        if (badge > 0)
          PositionedDirectional(
            top: -6,
            end: -4,
            child: PopIn(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: Tokens.danger,
                    borderRadius: const BorderRadius.all(Radius.circular(99)),
                    border: Border.all(color: Tokens.night, width: 2)),
                child: Text('$badge',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: Colors.white)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _GiftBanner extends StatelessWidget {
  const _GiftBanner({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: S.of('loginReadyHome'),
        child: Container(
          key: const Key('giftBanner'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Tokens.r20),
            gradient: const LinearGradient(colors: [Tokens.sun, Tokens.orange]),
            boxShadow: [
              BoxShadow(
                  color: Tokens.orange.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: Row(children: [
            const Bob(child: Text('🎁', style: TextStyle(fontSize: 28))),
            const SizedBox(width: 10),
            Expanded(
              child: Text(S.of('loginReadyHome'),
                  style: const TextStyle(
                      color: Tokens.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 16)),
            ),
            const Icon(Icons.chevron_left_rounded, color: Tokens.ink),
          ]),
        ),
      );
}
