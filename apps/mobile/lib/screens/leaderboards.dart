import 'package:flutter/material.dart';
import 'package:sahra_client/sahra_client.dart';

import '../app_state.dart';
import '../design/chibi_avatar.dart';
import '../design/cosmetics.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'friends.dart' show gameEmoji;
import 'progress_common.dart';

/// Games on the leaderboards (Who Among Us has no winners by design).
const _boardGames = [
  'quiz',
  'spy',
  'liar',
  'emoji',
  'stop',
  'memory',
  'draw',
  'football',
  'acting'
];

/// Games with an official ranked rating.
const _rankedGames = {'quiz', 'emoji', 'football'};

class LeaderboardsScreen extends StatefulWidget {
  const LeaderboardsScreen({super.key});
  @override
  State<LeaderboardsScreen> createState() => _LeaderboardsScreenState();
}

class _LeaderboardsScreenState extends State<LeaderboardsScreen> {
  String _game = 'all';
  String _period = 'week';
  String _scope = 'global';
  String _metric = 'points';
  LeaderboardView? _lb;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final metric = _rankedGames.contains(_game) ? _metric : 'points';
      final lb = await AppScope.read(context).api.leaderboard(
          game: _game, period: _period, scope: _scope, metric: metric);
      if (mounted) {
        setState(() {
          _lb = lb;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = S.of('error'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _set(VoidCallback f) {
    setState(f);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lb = _lb;
    final rating = lb?.metric == 'rating';
    return NightScaffold(
      glow: Tokens.sky,
      title: Text(S.of('hubLeaderboards'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      body: Column(children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s20),
            children: [
              for (final g in ['all', ..._boardGames])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    key: Key('lbGame_$g'),
                    label: Text(g == 'all'
                        ? '🎮 ${S.of('lbAll')}'
                        : '${gameEmoji[g] ?? ''} ${S.of('game_$g')}'),
                    selected: _game == g,
                    onSelected: (_) => _set(() => _game = g),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Tokens.s8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s20),
          child: Row(children: [
            Expanded(
              child: rating
                  ? const SizedBox.shrink()
                  : SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                            value: 'week', label: Text(S.of('lbWeek'))),
                        ButtonSegment(
                            value: 'month', label: Text(S.of('lbMonth'))),
                        ButtonSegment(
                            value: 'all', label: Text(S.of('lbAllTime'))),
                      ],
                      selected: {_period},
                      onSelectionChanged: (v) => _set(() => _period = v.first),
                    ),
            ),
          ]),
        ),
        const SizedBox(height: Tokens.s8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s20),
          child: Row(children: [
            ChoiceChip(
              key: const Key('lbGlobal'),
              label: Text('🌍 ${S.of('lbGlobal')}'),
              selected: _scope == 'global',
              onSelected: (_) => _set(() => _scope = 'global'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              key: const Key('lbFriends'),
              label: Text('🤝 ${S.of('lbFriends')}'),
              selected: _scope == 'friends',
              onSelected: (_) => _set(() => _scope = 'friends'),
            ),
            const Spacer(),
            if (_rankedGames.contains(_game))
              ChoiceChip(
                key: const Key('lbRating'),
                label: Text('📈 ${S.of('lbRating')}'),
                selected: _metric == 'rating',
                onSelected: (v) =>
                    _set(() => _metric = v ? 'rating' : 'points'),
              ),
          ]),
        ),
        Expanded(
          child: _error != null && lb == null
              ? Center(child: Text(_error!))
              : lb == null
                  ? const Center(
                      child: CircularProgressIndicator(color: Tokens.sun))
                  : AnimatedOpacity(
                      duration: Tokens.fast,
                      opacity: _loading ? 0.5 : 1,
                      child: _list(lb)),
        ),
        if (lb != null) _you(lb),
      ]),
    );
  }

  Widget _list(LeaderboardView lb) {
    final me = AppScope.of(context).user?.id;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            Tokens.s20, Tokens.s12, Tokens.s20, Tokens.s16),
        children: [
          if (lb.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Tokens.s32),
              child: Column(children: [
                const Text('🏁', style: TextStyle(fontSize: 54)),
                const SizedBox(height: Tokens.s8),
                Text(S.of('lbEmpty'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Tokens.textDim)),
              ]),
            ),
          for (final (i, r) in lb.rows.indexed)
            FadeSlideIn(
                delay: Duration(milliseconds: (20 * i).clamp(0, 400)),
                child: _row(r, lb, mine: r.playerId == me)),
          const SizedBox(height: Tokens.s12),
          Text(
              lb.metric == 'rating'
                  ? S.of('lbRatingNote')
                  : sf('lbNote', {'n': lb.bestOf}),
              style: const TextStyle(
                  color: Tokens.textFaint, fontSize: 12.5, height: 1.5)),
        ],
      ),
    );
  }

  Widget _row(LeaderboardRow r, LeaderboardView lb, {bool mine = false}) {
    final medal =
        switch (r.rank) { 1 => '🥇', 2 => '🥈', 3 => '🥉', _ => null };
    final top = r.rank <= 3;
    return Container(
      key: Key('lbRow_${r.rank}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: top ? 10 : 7),
      decoration: BoxDecoration(
        color: mine
            ? Tokens.sun.withValues(alpha: 0.14)
            : (top ? Tokens.glass : Tokens.glass.withValues(alpha: 0.06)),
        borderRadius: const BorderRadius.all(Tokens.r16),
        border: Border.all(
            color: mine ? Tokens.sun : Tokens.glassBorder, width: mine ? 2 : 1),
      ),
      child: Row(children: [
        SizedBox(
          width: 34,
          child: Center(
            child: medal != null
                ? Text(medal, style: const TextStyle(fontSize: 24))
                : Text('${r.rank}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Tokens.textDim)),
          ),
        ),
        const SizedBox(width: 6),
        ChibiAvatar(
            avatarId: r.avatarId,
            size: top ? 50 : 42,
            frame: r.cosmetics?.frame),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mine ? '${r.displayName} (${S.of('you')})' : r.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: top ? 16 : 14.5,
                    color: mine ? Tokens.sun : Colors.white)),
            Row(children: [
              Flexible(
                  child: TitleTag(look: r.cosmetics?.title, fontSize: 11.5)),
              if (r.cosmetics?.title?.text != null) const SizedBox(width: 6),
              Text('${r.matches} ${S.of('lbMatches')}',
                  style:
                      const TextStyle(fontSize: 11.5, color: Tokens.textFaint)),
            ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${r.points}',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: top ? 20 : 17,
                  color: top ? Tokens.sun : Colors.white)),
          Text(lb.metric == 'rating' ? S.of('lbRating') : S.of('lbPts'),
              style: const TextStyle(fontSize: 11, color: Tokens.textDim)),
        ]),
      ]),
    );
  }

  Widget _you(LeaderboardView lb) {
    final you = lb.you;
    final user = AppScope.of(context).user;
    return Container(
      padding: const EdgeInsets.fromLTRB(Tokens.s20, 10, Tokens.s20, 10),
      decoration: const BoxDecoration(
        color: Tokens.plum,
        border: Border(top: BorderSide(color: Tokens.glassBorder)),
      ),
      child: Row(children: [
        Text(S.of('lbYou'),
            style: const TextStyle(
                color: Tokens.textDim, fontWeight: FontWeight.w700)),
        const SizedBox(width: 10),
        ChibiAvatar(
            avatarId: user?.avatarId ?? '', size: 36, frame: MyLooks.frame),
        const SizedBox(width: 10),
        Expanded(
          child: Text(you == null ? S.of('lbNotRanked') : '#${you.rank}',
              key: const Key('lbYouRank'),
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: you == null ? 14 : 20,
                  color: you == null ? Tokens.textDim : Tokens.sun)),
        ),
        if (you != null)
          Text('${you.points} ${lb.metric == 'rating' ? '' : S.of('lbPts')}',
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      ]),
    );
  }
}
