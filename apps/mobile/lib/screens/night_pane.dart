import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sahra_client/sahra_client.dart';
import 'package:share_plus/share_plus.dart';

import '../design/chibi_avatar.dart';
import '../design/sfx.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'friends.dart' show gameEmoji;

/// Same order as the home screen.
const nightGames = [
  'quiz',
  'spy',
  'liar',
  'who',
  'emoji',
  'stop',
  'memory',
  'draw',
  'football',
  'acting',
];

const _gameColor = {
  'quiz': Tokens.sky,
  'spy': Tokens.grape,
  'liar': Tokens.coral,
  'who': Tokens.pink,
  'emoji': Tokens.sun,
  'stop': Tokens.orange,
  'memory': Tokens.mint,
  'draw': Tokens.sky,
  'football': Tokens.mint,
  'acting': Tokens.grape,
};

Color nightGameColor(String id) => _gameColor[id] ?? Tokens.sun;

PublicPlayer? _player(RoomView v, String id) =>
    v.players.where((p) => p.playerId == id).firstOrNull;

/// A small tile for one game: emoji badge and name.
class NightGameTile extends StatelessWidget {
  const NightGameTile(
      {super.key,
      required this.gameId,
      this.onTap,
      this.selected = false,
      this.dimmed = false,
      this.badge,
      this.trailing});
  final String gameId;
  final VoidCallback? onTap;
  final bool selected;
  final bool dimmed;
  final String? badge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = nightGameColor(gameId);
    return Pressable(
      onTap: onTap,
      semanticLabel: S.of('game_$gameId'),
      child: AnimatedOpacity(
        duration: Tokens.fast,
        opacity: dimmed ? 0.4 : 1,
        child: AnimatedContainer(
          duration: Tokens.fast,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.3) : Tokens.glass,
            borderRadius: const BorderRadius.all(Tokens.r16),
            border: Border.all(
                color: selected ? c : Tokens.glassBorder,
                width: selected ? 2.5 : 1),
          ),
          child: Row(children: [
            Text(gameEmoji[gameId] ?? '🎮',
                style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(S.of('game_$gameId'),
                  maxLines: 2,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14, height: 1.2)),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: c,
                    borderRadius: const BorderRadius.all(Radius.circular(99))),
                child: Text(badge!,
                    style: const TextStyle(
                        color: Tokens.ink, fontWeight: FontWeight.w900)),
              ),
            if (trailing != null) trailing!,
          ]),
        ),
      ),
    );
  }
}

/// The night's ranking: avatars with points and wins.
class NightStandings extends StatelessWidget {
  const NightStandings({super.key, required this.view, this.compact = false});
  final RoomView view;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final n = view.night!;
    if (n.standings.isEmpty) return const SizedBox.shrink();
    return GlassCard(
      padding: const EdgeInsets.all(Tokens.s12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('🏅 ${S.of('nightStandings')}',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('${S.of('nightGamesPlayed')}: ${n.played.length}',
              style: const TextStyle(color: Tokens.textDim, fontSize: 13)),
        ]),
        const SizedBox(height: Tokens.s8),
        for (final (i, s) in n.standings.take(compact ? 3 : 8).indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(
                width: 28,
                child: Text(const {0: '🥇', 1: '🥈', 2: '🥉'}[i] ?? '${i + 1}',
                    style: const TextStyle(fontSize: 18)),
              ),
              ChibiAvatar(
                  avatarId: _player(view, s.playerId)?.avatarId ?? '',
                  size: 30),
              const SizedBox(width: Tokens.s8),
              Expanded(
                child: Text(
                    s.playerId == view.you
                        ? '${_player(view, s.playerId)?.displayName ?? ''} (${S.of('you')})'
                        : _player(view, s.playerId)?.displayName ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (s.wins > 0)
                Text('🏆${s.wins}  ',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${s.points}',
                  style: const TextStyle(
                      color: Tokens.sun,
                      fontSize: 17,
                      fontWeight: FontWeight.w900)),
            ]),
          ),
      ]),
    );
  }
}

/// Between games: the room's code, the playlist (host edits it), standings,
/// and start / end for the host.
class NightLobby extends StatelessWidget {
  const NightLobby(
      {super.key,
      required this.view,
      required this.session,
      required this.onCopy,
      required this.onInvite,
      required this.onPlayer});
  final RoomView view;
  final GameSession session;
  final VoidCallback onCopy;
  final VoidCallback onInvite;
  final void Function(PublicPlayer) onPlayer;

  @override
  Widget build(BuildContext context) {
    final n = view.night!;
    final isHost = view.me?.isHost == true;
    final started = n.played.isNotEmpty;
    return Column(children: [
      Expanded(
        child: ListView(
          padding:
              const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s12),
          children: [
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(Tokens.s16),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Tokens.r24),
                  gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFF5B3DFF), Color(0xFF2A1A6E)]),
                  border: Border.all(color: Tokens.glassBorder),
                ),
                child: Column(children: [
                  Text(S.of('nightLobbyTitle'),
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: Tokens.s8),
                  if (view.code != null)
                    Pressable(
                      onTap: onCopy,
                      semanticLabel: '${S.of('roomCode')}: ${view.code}',
                      child: Text(view.code!,
                          key: const Key('nightCode'),
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                              fontFamily: Tokens.body,
                              fontSize: 30,
                              letterSpacing: 6,
                              color: Tokens.sun,
                              fontWeight: FontWeight.w900)),
                    ),
                  const SizedBox(height: Tokens.s8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    GameButton(
                        key: const Key('inviteFriends'),
                        label: S.of('inviteFriends'),
                        icon: Icons.group_add_rounded,
                        color: Tokens.sun,
                        size: GameButtonSize.medium,
                        expand: false,
                        onPressed: onInvite),
                    const SizedBox(width: Tokens.s8),
                    GameButton(
                        label: S.of('copyCode'),
                        icon: Icons.copy_rounded,
                        color: Tokens.grape,
                        size: GameButtonSize.medium,
                        expand: false,
                        onPressed: onCopy),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: Tokens.s12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: Tokens.s12,
              runSpacing: Tokens.s8,
              children: [
                for (final p in view.players)
                  Pressable(
                    onTap: () => onPlayer(p),
                    semanticLabel: p.displayName,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Stack(clipBehavior: Clip.none, children: [
                        ChibiAvatar(
                            avatarId: p.avatarId,
                            frame: p.cosmetics?.frame,
                            size: 52,
                            dimmed: !p.connected),
                        if (p.isHost)
                          const PositionedDirectional(
                              top: -10,
                              end: -4,
                              child:
                                  Text('👑', style: TextStyle(fontSize: 18))),
                      ]),
                      const SizedBox(height: 2),
                      SizedBox(
                        width: 70,
                        child: Text(p.displayName,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: p.playerId == view.you
                                    ? Tokens.sun
                                    : Colors.white)),
                      ),
                    ]),
                  ),
              ],
            ),
            if (started) ...[
              const SizedBox(height: Tokens.s12),
              NightStandings(view: view),
            ],
            const SizedBox(height: Tokens.s16),
            Text('🎮 ${S.of('nightPlaylist')}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                isHost
                    ? S.of('nightPlaylistHint')
                    : (n.playlist.isEmpty
                        ? S.of('nightPlaylistEmpty')
                        : S.of('nightPlaylistGuest')),
                style: const TextStyle(color: Tokens.textDim, fontSize: 13)),
            const SizedBox(height: Tokens.s8),
            if (n.playlist.isNotEmpty)
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (i, g) in n.playlist.indexed)
                  Pill(
                      text: '${i + 1}. ${S.of('game_$g')}',
                      emoji: gameEmoji[g],
                      color: nightGameColor(g),
                      solid: true),
                if (isHost)
                  Pressable(
                    key: const Key('nightClearPlaylist'),
                    onTap: () => session.nightPlaylist(const []),
                    semanticLabel: S.of('friendsCancel'),
                    child: const Pill(text: '✕', color: Tokens.textDim),
                  ),
              ]),
            if (isHost) ...[
              const SizedBox(height: Tokens.s8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.9,
                children: [
                  for (final g in nightGames)
                    NightGameTile(
                      key: Key('nightAdd_$g'),
                      gameId: g,
                      dimmed: !n.eligible.contains(g),
                      badge: n.playlist.contains(g)
                          ? '${n.playlist.indexOf(g) + 1}'
                          : null,
                      selected: n.playlist.contains(g),
                      onTap: n.playlist.length >= 10
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              final list = [...n.playlist];
                              list.contains(g) ? list.remove(g) : list.add(g);
                              session.nightPlaylist(list);
                            },
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text('🔅 = ${S.of('nightNotFit')}',
                  style:
                      const TextStyle(color: Tokens.textFaint, fontSize: 12)),
            ],
          ],
        ),
      ),
      Padding(
        padding:
            const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s12),
        child: isHost
            ? Row(children: [
                if (started) ...[
                  Expanded(
                    child: GameButton(
                        key: const Key('nightEnd'),
                        label: S.of('nightEnd'),
                        icon: Icons.nightlight_round,
                        color: Tokens.grape,
                        onPressed: session.nightEnd),
                  ),
                  const SizedBox(width: Tokens.s8),
                ],
                Expanded(
                  flex: 2,
                  child: GameButton(
                      key: const Key('startMatch'),
                      label: S.of(started ? 'nightContinue' : 'nightBegin'),
                      icon: Icons.play_arrow_rounded,
                      color: Tokens.sun,
                      onPressed: n.eligible.isEmpty ? null : session.start),
                ),
              ])
            : Text(
                n.eligible.isEmpty
                    ? S.of('needMorePlayers')
                    : S.of('nightWaitHost'),
                style: const TextStyle(color: Tokens.textDim)),
      ),
    ]);
  }
}

/// Everyone votes for the next game; on a tie the host picks.
class NightVotePane extends StatelessWidget {
  const NightVotePane({super.key, required this.view, required this.session});
  final RoomView view;
  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final n = view.night!;
    final v = n.vote!;
    final isHost = view.me?.isHost == true;
    final tie = v.tie;
    final options = tie ?? v.options.keys.toList();
    final maxVotes =
        v.options.values.fold<int>(0, (a, b) => b > a ? b : a).clamp(1, 99);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s12),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Text(tie == null ? S.of('nightVoteTitle') : S.of('nightTie'),
                key: const Key('nightVoteTitle'),
                style: Theme.of(context).textTheme.headlineSmall),
          ),
          ServerTimerRing(
              key: ValueKey('vt${tie == null ? v.endsAt : v.tieEndsAt}'),
              startsAt:
                  tie == null ? v.endsAt - 20000 : (v.tieEndsAt ?? 0) - 10000,
              endsAt: tie == null ? v.endsAt : (v.tieEndsAt ?? 0),
              size: 50,
              serverNow: () => session.serverNow),
        ]),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
              tie == null
                  ? '${S.of('nightVoted')}: ${v.voted}/${v.voters}'
                  : (isHost ? S.of('nightTieHost') : S.of('nightTieWait')),
              style: TextStyle(
                  color: tie == null ? Tokens.textDim : Tokens.sun,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: Tokens.s12),
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.25,
            children: [
              for (final (i, g) in options.indexed)
                FadeSlideIn(
                  delay: Duration(milliseconds: 40 * i),
                  child: _VoteCard(
                    key: Key('nightVote_$g'),
                    gameId: g,
                    votes: v.options[g] ?? 0,
                    share: (v.options[g] ?? 0) / maxVotes,
                    mine: v.yourVote == g,
                    onTap: tie == null
                        ? () {
                            HapticFeedback.selectionClick();
                            Sfx.play('pop', volume: 0.5);
                            session.nightVote(g);
                          }
                        : (isHost ? () => session.nightPick(g) : null),
                  ),
                ),
            ],
          ),
        ),
        if (n.standings.isNotEmpty) NightStandings(view: view, compact: true),
        if (isHost)
          TextButton.icon(
              key: const Key('nightEndVote'),
              onPressed: session.nightEnd,
              icon: const Icon(Icons.nightlight_round, color: Tokens.textDim),
              label: Text(S.of('nightEnd'),
                  style: const TextStyle(
                      color: Tokens.textDim, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

class _VoteCard extends StatelessWidget {
  const _VoteCard(
      {super.key,
      required this.gameId,
      required this.votes,
      required this.share,
      required this.mine,
      this.onTap});
  final String gameId;
  final int votes;
  final double share;
  final bool mine;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = nightGameColor(gameId);
    return Pressable(
      onTap: onTap,
      semanticLabel:
          '${S.of('game_$gameId')} · $votes${mine ? ' · ${S.of('nightYourVote')}' : ''}',
      child: ExcludeSemantics(
          child: AnimatedContainer(
        duration: Tokens.fast,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: mine ? c.withValues(alpha: 0.35) : Tokens.glass,
          borderRadius: const BorderRadius.all(Tokens.r20),
          border: Border.all(
              color: mine ? c : Tokens.glassBorder, width: mine ? 3 : 1),
        ),
        child: Column(children: [
          Row(children: [
            Text(gameEmoji[gameId] ?? '🎮',
                style: const TextStyle(fontSize: 30)),
            const Spacer(),
            if (mine) Pill(text: S.of('nightYourVote'), color: c, solid: true),
          ]),
          const Spacer(),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(S.of('game_$gameId'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(99)),
                child: LinearProgressIndicator(
                    value: votes == 0 ? 0 : share,
                    minHeight: 8,
                    color: c,
                    backgroundColor: Tokens.glass),
              ),
            ),
            const SizedBox(width: 6),
            Text('$votes', style: const TextStyle(fontWeight: FontWeight.w900)),
          ]),
        ]),
      )),
    );
  }
}

/// The countdown before the next game of the night.
class NightNextPane extends StatelessWidget {
  const NightNextPane({super.key, required this.view, required this.session});
  final RoomView view;
  final GameSession session;
  @override
  Widget build(BuildContext context) {
    final g = view.night?.next ?? view.gameId;
    final n = ((view.countdownEndsAt! - session.serverNow) / 1000)
        .ceil()
        .clamp(0, 99);
    final c = nightGameColor(g);
    return Column(children: [
      const Spacer(),
      Text(S.of('nightNext'),
          style: const TextStyle(color: Tokens.textDim, fontSize: 18)),
      const SizedBox(height: Tokens.s12),
      PopIn(
        child: Bob(
          child: GameIcon(emoji: gameEmoji[g] ?? '🎮', color: c, size: 130),
        ),
      ),
      const SizedBox(height: Tokens.s16),
      Text(S.of('game_$g'),
          key: const Key('nightNextGame'),
          style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: Tokens.s16),
      PopIn(
        key: ValueKey(n),
        from: 1.6,
        child: Text(n == 0 ? '🚀' : '$n',
            style: const TextStyle(
                fontSize: 64, fontWeight: FontWeight.w900, color: Tokens.sun)),
      ),
      const Spacer(),
    ]);
  }
}

/// The end of the night: podium, titles, games played and a shareable card.
class NightSummaryPane extends StatefulWidget {
  const NightSummaryPane(
      {super.key, required this.view, required this.session});
  final RoomView view;
  final GameSession session;
  @override
  State<NightSummaryPane> createState() => _NightSummaryPaneState();
}

class _NightSummaryPaneState extends State<NightSummaryPane> {
  final _shareKey = GlobalKey();
  bool _sharing = false;

  RoomView get view => widget.view;

  @override
  void initState() {
    super.initState();
    Sfx.play('win');
  }

  Future<void> _share(int place, int games) async {
    setState(() => _sharing = true);
    try {
      final boundary = _shareKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await SharePlus.instance.share(ShareParams(
        text: S
            .of('nightShareText')
            .replaceAll('{games}', '$games')
            .replaceAll('{place}', '${S.of('place')} $place'),
        files: [
          XFile.fromData(data!.buffer.asUint8List(),
              mimeType: 'image/png', name: 'sahra-night.png')
        ],
        fileNameOverrides: ['sahra-night.png'],
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(S.of('shareFailed'))));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sum = view.night!.summary!;
    final isHost = view.me?.isHost == true;
    final myIndex = sum.standings.indexWhere((s) => s.playerId == view.you);
    final mine = myIndex < 0 ? null : sum.standings[myIndex];
    final me = view.me;
    final top = sum.standings.take(3).toList();
    final won = myIndex == 0;
    return Stack(children: [
      ListView(
        padding:
            const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s24),
        children: [
          FadeSlideIn(
            child: Text(S.of('nightSummary'),
                key: const Key('nightSummaryTitle'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium),
          ),
          const SizedBox(height: 4),
          Text(
              '${S.of('nightGamesPlayed')}: ${sum.played.length} · ${S.of('nightDuration')}: ${(sum.durationSec / 60).ceil()} ${S.of('minutes')}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Tokens.textDim)),
          const SizedBox(height: Tokens.s16),
          // Podium: 2nd, 1st, 3rd.
          if (top.isNotEmpty)
            SizedBox(
              height: 285,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final i in [1, 0, 2])
                  Expanded(
                    child: i < top.length
                        ? _Podium(
                            view: view,
                            standing: top[i],
                            place: i + 1,
                            title: sum.titles[top[i].playerId])
                        : const SizedBox.shrink(),
                  ),
              ]),
            ),
          const SizedBox(height: Tokens.s12),
          for (final (i, s) in sum.standings.indexed)
            FadeSlideIn(
              delay: Duration(milliseconds: 60 * i),
              child: Container(
                margin: const EdgeInsets.only(bottom: Tokens.s8),
                padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.s12, vertical: 8),
                decoration: BoxDecoration(
                  color: s.playerId == view.you
                      ? Tokens.sun.withValues(alpha: 0.18)
                      : Tokens.glass,
                  borderRadius: const BorderRadius.all(Tokens.r16),
                  border: Border.all(
                      color: i == 0 ? Tokens.sun : Tokens.glassBorder),
                ),
                child: Row(children: [
                  SizedBox(
                      width: 28,
                      child: Text(
                          const {0: '🥇', 1: '🥈', 2: '🥉'}[i] ?? '${i + 1}',
                          style: const TextStyle(fontSize: 18))),
                  ChibiAvatar(
                      avatarId: _player(view, s.playerId)?.avatarId ?? '',
                      size: 36),
                  const SizedBox(width: Tokens.s8),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_player(view, s.playerId)?.displayName ?? '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          if (sum.titles[s.playerId] != null)
                            Text(S.of('night_title_${sum.titles[s.playerId]}'),
                                style: const TextStyle(
                                    color: Tokens.textDim, fontSize: 12)),
                        ]),
                  ),
                  if (s.wins > 0)
                    Text('🏆${s.wins}  ',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${s.points}',
                      style: const TextStyle(
                          color: Tokens.sun,
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          const SizedBox(height: 4),
          Text(S.of('nightPointsNote'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Tokens.textFaint, fontSize: 12)),
          const SizedBox(height: Tokens.s16),
          Text('🎮 ${S.of('nightGamesPlayed')}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Tokens.s8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (i, p) in sum.played.indexed)
              Container(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 4, 4),
                decoration: BoxDecoration(
                  color: nightGameColor(p.gameId).withValues(alpha: 0.2),
                  borderRadius: const BorderRadius.all(Radius.circular(99)),
                  border: Border.all(color: nightGameColor(p.gameId)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${i + 1}. ${gameEmoji[p.gameId] ?? ''} ',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  for (final w in p.winners.take(2))
                    ChibiAvatar(
                        avatarId: _player(view, w)?.avatarId ?? '', size: 22),
                ]),
              ),
          ]),
          if (mine != null && me != null) ...[
            const SizedBox(height: Tokens.s20),
            // The shared card shows only you: other players stay private.
            RepaintBoundary(
              key: _shareKey,
              child: _NightShareCard(
                  player: me,
                  standing: mine,
                  place: myIndex + 1,
                  games: sum.played.length,
                  friends: sum.standings.length - 1,
                  title: sum.titles[view.you]),
            ),
            const SizedBox(height: Tokens.s12),
            GameButton(
                key: const Key('nightShare'),
                label: S.of('nightShare'),
                icon: Icons.ios_share_rounded,
                color: Tokens.sky,
                busy: _sharing,
                onPressed: () => _share(myIndex + 1, sum.played.length)),
          ],
          const SizedBox(height: Tokens.s12),
          if (isHost)
            GameButton(
                key: const Key('nightNew'),
                label: S.of('nightNew'),
                icon: Icons.nightlight_round,
                color: Tokens.sun,
                onPressed: widget.session.nightNew),
          const SizedBox(height: Tokens.s12),
          GameButton(
              label: S.of('backHome'),
              icon: Icons.home_rounded,
              color: Tokens.grape,
              onPressed: () => Navigator.of(context).pop()),
        ],
      ),
      if (won) const Positioned.fill(child: IgnorePointer(child: Confetti())),
    ]);
  }
}

class _Podium extends StatelessWidget {
  const _Podium(
      {required this.view,
      required this.standing,
      required this.place,
      this.title});
  final RoomView view;
  final NightStanding standing;
  final int place;
  final String? title;
  @override
  Widget build(BuildContext context) {
    final p = _player(view, standing.playerId);
    final h = const {1: 96.0, 2: 70.0, 3: 52.0}[place]!;
    final c =
        const {1: Tokens.sun, 2: Color(0xFFCBD5E1), 3: Tokens.orange}[place]!;
    return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      if (place == 1) const Text('👑', style: TextStyle(fontSize: 26)),
      Bob(
        phase: place / 3,
        child: ChibiFullBody(
            avatarId: p?.avatarId ?? '',
            height: place == 1 ? 110 : 84,
            expression: ChibiExpression.happy),
      ),
      Text(p?.displayName ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      const SizedBox(height: 4),
      Container(
        height: h,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: Tokens.gradient(c, Tokens.shade(c, 0.3)),
          borderRadius: const BorderRadius.vertical(top: Tokens.r12),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('$place',
              style: const TextStyle(
                  color: Tokens.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w900)),
          Text('${standing.points}',
              style: const TextStyle(
                  color: Tokens.ink, fontWeight: FontWeight.w800)),
        ]),
      ),
    ]);
  }
}

/// The shareable memory card: only the player's own name, avatar and result.
class _NightShareCard extends StatelessWidget {
  const _NightShareCard(
      {required this.player,
      required this.standing,
      required this.place,
      required this.games,
      required this.friends,
      this.title});
  final PublicPlayer player;
  final NightStanding standing;
  final int place;
  final int games;
  final int friends;
  final String? title;
  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s16, Tokens.s16, 0),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Tokens.r24),
          gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF5B3DFF), Tokens.night, Tokens.nightDeep]),
          border:
              Border.all(color: Tokens.sun.withValues(alpha: 0.6), width: 2),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Logo(size: 20),
                      const SizedBox(width: 6),
                      Text('· ${S.of('night')}',
                          style: const TextStyle(
                              color: Tokens.textDim,
                              fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(height: Tokens.s12),
                    Text(player.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    if (title != null)
                      Text(S.of('night_title_$title'),
                          style: const TextStyle(
                              color: Tokens.sun,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                        '${const {
                              1: '🥇',
                              2: '🥈',
                              3: '🥉'
                            }[place] ?? '🎯'} ${S.of('place')} $place · ${standing.points} ${S.of('nightPts')}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                        '🎮 $games · 🏆 ${standing.wins} · ${S.of('nightWith').replaceAll('{n}', '$friends')}',
                        style: const TextStyle(
                            color: Tokens.textDim,
                            fontWeight: FontWeight.w700)),
                  ]),
            ),
          ),
          ChibiFullBody(avatarId: player.avatarId, height: 140),
        ]),
      );
}

/// Ticks once a second so countdowns repaint (vote and next game).
class NightTicker extends StatefulWidget {
  const NightTicker({super.key, required this.child});
  final Widget Function() child;
  @override
  State<NightTicker> createState() => _NightTickerState();
}

class _NightTickerState extends State<NightTicker> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child();
}
