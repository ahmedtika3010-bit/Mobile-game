import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sahra_client/sahra_client.dart';

import '../design/chibi_avatar.dart';
import '../design/sfx.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'spy_pane.dart' show OptionTile, PartyPlayerGrid;

const _diffEmoji = {'easy': '🌱', 'medium': '🔥', 'hard': '🌶️'};

/// The live "Who Is the Liar?" match: answer, discussion, vote, round reveal.
class LiarPane extends StatefulWidget {
  const LiarPane(
      {super.key,
      required this.view,
      required this.session,
      required this.bubbles});
  final RoomView view;
  final GameSession session;
  final Map<String, String> bubbles;

  @override
  State<LiarPane> createState() => _LiarPaneState();
}

class _LiarPaneState extends State<LiarPane> {
  int _stageStart = 0;
  String _stageKey = '';
  String? _voteFor;
  int? _picked;
  bool _sent = false;

  LiarView get g => widget.view.liar!;
  String get you => widget.view.you;
  int get n => widget.view.players.length;

  PublicPlayer? _player(String? id) =>
      widget.view.players.where((p) => p.playerId == id).firstOrNull;

  @override
  void initState() {
    super.initState();
    _syncStage();
  }

  @override
  void didUpdateWidget(LiarPane old) {
    super.didUpdateWidget(old);
    _syncStage();
  }

  void _syncStage() {
    final key = '${g.round}-${g.stage}';
    if (key == _stageKey) return;
    final previous = _stageKey;
    _stageKey = key;
    _stageStart = widget.session.serverNow;
    _sent = false;
    _voteFor = null;
    if (g.stage == 'answer') _picked = null;
    if (previous.isEmpty) return;
    switch (g.stage) {
      case 'answer':
        Sfx.play('whoosh', volume: 0.6);
      case 'discuss':
        if (g.youAreLiar == true) {
          Sfx.play('wrong', volume: 0.5);
          HapticFeedback.heavyImpact();
        } else {
          Sfx.play('go', volume: 0.6);
        }
      case 'vote':
        Sfx.play('go', volume: 0.6);
      case 'roundEnd':
        final r = g.lastRound;
        final good = r != null && (r.points[you] ?? 0) > 0;
        Sfx.play(good ? 'correct' : 'wrong', volume: 0.6);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, Tokens.s8),
        child: Column(children: [
          _header(),
          const SizedBox(height: Tokens.s12),
          Expanded(
            child: AnimatedSwitcher(
              duration: Tokens.medium,
              child: KeyedSubtree(key: ValueKey(_stageKey), child: _stage()),
            ),
          ),
        ]),
      );

  Widget _timer() => ServerTimerRing(
      startsAt: _stageStart,
      endsAt: g.stageEndsAt,
      size: 54,
      serverNow: () => widget.session.serverNow);

  Widget _header() => Row(children: [
        Pill(
            text: '${S.of('roundOf')} ${g.round} ${S.of('of')} ${g.rounds}',
            color: Tokens.coral,
            emoji: '🤥'),
        const SizedBox(width: Tokens.s8),
        Pill(
            text: S.of('diff_${g.difficulty}'),
            color: Tokens.sun,
            emoji: _diffEmoji[g.difficulty]),
        const Spacer(),
        Pill(text: '${g.scores[you] ?? 0}', color: Tokens.mint, emoji: '⭐'),
        if (g.stage != 'finished') ...[
          const SizedBox(width: Tokens.s8),
          _timer(),
        ],
      ]);

  Widget _stage() => switch (g.stage) {
        'answer' => _answer(),
        'discuss' => _discuss(),
        'vote' => _vote(),
        'roundEnd' => _roundEnd(),
        _ => const SizedBox.shrink(),
      };

  Widget _questionCard(String text, {Color accent = Tokens.grape}) => PopIn(
        from: 0.8,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Tokens.s20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.all(Tokens.r24),
            boxShadow: [
              BoxShadow(
                  color: Tokens.shade(accent, 0.12),
                  offset: const Offset(0, 6)),
            ],
          ),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Tokens.ink,
                  fontSize: 22,
                  height: 1.4,
                  fontWeight: FontWeight.w800)),
        ),
      );

  Widget _answer() {
    final chosen = g.yourAnswer ?? _picked;
    return ListView(children: [
      Text('❓ ${S.of('yourQuestion')}',
          style: const TextStyle(
              color: Tokens.textDim, fontWeight: FontWeight.w700)),
      const SizedBox(height: Tokens.s8),
      _questionCard(g.yourQuestion ?? ''),
      const SizedBox(height: Tokens.s12),
      Text(S.of('liarAnswerHint'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Tokens.textDim, height: 1.4)),
      const SizedBox(height: Tokens.s12),
      for (final (i, o) in g.options.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: Tokens.s8),
          child: AnimatedOpacity(
            duration: Tokens.fast,
            opacity: chosen == null || chosen == i ? 1 : 0.4,
            child: OptionTile(
              key: Key('liarOption$i'),
              text: chosen == i ? '✓  $o' : o,
              color: Tokens.choiceColors[i % Tokens.choiceColors.length],
              center: true,
              onTap: chosen != null || _sent
                  ? null
                  : () {
                      setState(() {
                        _sent = true;
                        _picked = i;
                      });
                      Sfx.play('pop', volume: 0.6);
                      widget.session.liarAnswer(g.round, i);
                    },
            ),
          ),
        ),
      if (chosen != null)
        Center(
          child: Bob(
            child: Text('⏳ ${S.of('waitingOthers')} ${g.answeredCount}/$n',
                style: const TextStyle(
                    color: Tokens.textDim,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
        ),
    ]);
  }

  /// Your role for this round, now that the questions are revealed.
  Widget _roleBanner() {
    final liar = g.youAreLiar == true;
    if (!liar) {
      return Text(S.of('youAreHonest'),
          textAlign: TextAlign.center,
          style:
              const TextStyle(color: Tokens.mint, fontWeight: FontWeight.w800));
    }
    return PopIn(
      from: 0.5,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Tokens.s12),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Tokens.r20),
          gradient: Tokens.gradient(Tokens.coral, Tokens.shade(Tokens.coral)),
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: Column(children: [
          Text(S.of('youAreTheLiar'),
              style: const TextStyle(
                  color: Tokens.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          Text('${S.of('yourQuestionWas')}: ${g.yourQuestion ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xCC1B1340), fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(S.of('youAreTheLiarHint'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xCC1B1340),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _mainQuestion() => Column(children: [
        Text('${S.of('theMainQuestion')}:',
            style: const TextStyle(
                color: Tokens.textDim, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(g.mainQuestion ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Tokens.sun, fontSize: 19, fontWeight: FontWeight.w800)),
      ]);

  String _answerText(int? a) =>
      a == null ? '🤐 ${S.of('noAnswer')}' : g.options[a];

  Widget _answersList() {
    final answers = g.answers ?? const <String, int?>{};
    return ListView(children: [
      Text('📝 ${S.of('everyonesAnswers')}',
          style: const TextStyle(
              color: Tokens.textDim, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      for (final p in widget.view.players)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: GlassCard(
            radius: Tokens.r16,
            padding:
                const EdgeInsets.symmetric(horizontal: Tokens.s8, vertical: 6),
            child: Row(children: [
              ChibiAvatar(avatarId: p.avatarId, size: 32),
              const SizedBox(width: Tokens.s8),
              Expanded(
                child: Text(
                    p.playerId == you
                        ? '${p.displayName} (${S.of('you')})'
                        : p.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              _AnswerBadge(
                  text: _answerText(answers[p.playerId]),
                  index: answers[p.playerId]),
            ]),
          ),
        ),
    ]);
  }

  Widget _discuss() {
    final counts = <String, int>{};
    for (final t in g.suspicions.values) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    final mySuspect = g.suspicions[you];
    return Column(children: [
      _roleBanner(),
      const SizedBox(height: Tokens.s8),
      _mainQuestion(),
      const SizedBox(height: Tokens.s8),
      PartyPlayerGrid(
        players: widget.view.players,
        you: you,
        bubbles: widget.bubbles,
        selected: mySuspect,
        badge: (id) => counts[id] == null ? null : '🤔 ${counts[id]}',
        onTap: (p) {
          if (p.playerId == you) return;
          HapticFeedback.selectionClick();
          widget.session
              .spySuspect(mySuspect == p.playerId ? null : p.playerId);
        },
      ),
      const SizedBox(height: Tokens.s8),
      Expanded(child: _answersList()),
      const SizedBox(height: Tokens.s8),
      GameButton(
        key: const Key('readyToVote'),
        label: g.youReady
            ? '${S.of('readyCount')} ${g.readyCount}/$n'
            : S.of('readyToVote'),
        icon: g.youReady ? Icons.check_circle_rounded : Icons.how_to_vote,
        color: g.youReady ? Tokens.success : Tokens.sun,
        size: GameButtonSize.medium,
        onPressed: g.youReady ? null : widget.session.spyReadyToVote,
      ),
    ]);
  }

  Widget _vote() {
    final voted = g.yourVote != null;
    final answers = g.answers ?? const <String, int?>{};
    return Column(children: [
      Text('🗳️ ${S.of('voteLiarTitle')}',
          style: Theme.of(context).textTheme.titleLarge),
      Text(S.of('voteHint'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Tokens.textDim, height: 1.4)),
      const SizedBox(height: Tokens.s8),
      _mainQuestion(),
      const SizedBox(height: Tokens.s16),
      Expanded(
        child: SingleChildScrollView(
          child: PartyPlayerGrid(
            players: widget.view.players,
            you: you,
            bubbles: widget.bubbles,
            selected: g.yourVote ?? _voteFor,
            disabledId: you,
            badge: (id) => answers.containsKey(id)
                ? (answers[id] == null ? '🤐' : g.options[answers[id]!])
                : null,
            onTap: voted
                ? null
                : (p) {
                    if (p.playerId == you) return;
                    HapticFeedback.selectionClick();
                    setState(() => _voteFor = p.playerId);
                  },
          ),
        ),
      ),
      Text('${S.of('voted')}: ${g.votedCount}/$n',
          style: const TextStyle(
              color: Tokens.textDim, fontWeight: FontWeight.w700)),
      const SizedBox(height: Tokens.s8),
      GameButton(
        key: const Key('confirmVote'),
        label: voted ? S.of('youVoted') : S.of('confirmVote'),
        icon: voted ? Icons.check_circle_rounded : Icons.how_to_vote,
        color: voted ? Tokens.success : Tokens.coral,
        onPressed: voted || _voteFor == null || _sent
            ? null
            : () {
                setState(() => _sent = true);
                Sfx.play('pop');
                widget.session.spyVote(_voteFor!);
              },
      ),
    ]);
  }

  Widget _roundEnd() {
    final r = g.lastRound;
    if (r == null) return const SizedBox.shrink();
    return ListView(children: [
      _RoundReveal(result: r, player: _player, you: you),
      const SizedBox(height: Tokens.s16),
      Center(
        child: Bob(
          child: Text(S.of('nextRoundSoon'),
              style: const TextStyle(
                  color: Tokens.textDim, fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }
}

/* ------------------------------- pieces -------------------------------- */

class _AnswerBadge extends StatelessWidget {
  const _AnswerBadge({required this.text, required this.index});
  final String text;
  final int? index;
  @override
  Widget build(BuildContext context) {
    final color = index == null
        ? Tokens.glassStrong
        : Tokens.choiceColors[index! % Tokens.choiceColors.length];
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.all(Radius.circular(99))),
      child: Text(text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: index == null ? Colors.white : Tokens.onColor(color),
              fontSize: 13.5,
              fontWeight: FontWeight.w800)),
    );
  }
}

/// Who the liar was, whether they were caught, and both questions.
class _RoundReveal extends StatelessWidget {
  const _RoundReveal(
      {required this.result, required this.player, required this.you});
  final LiarRoundResult result;
  final PublicPlayer? Function(String?) player;
  final String you;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final liar = player(r.liar);
    final mine = r.points[you] ?? 0;
    return Column(children: [
      Text(S.of('theLiarWas'),
          style: const TextStyle(
              color: Tokens.textDim, fontWeight: FontWeight.w700)),
      const SizedBox(height: Tokens.s8),
      PopIn(
        child: Stack(clipBehavior: Clip.none, children: [
          Bob(
              child: ChibiFullBody(
                  avatarId: liar?.avatarId ?? '',
                  height: 150,
                  expression: r.caught
                      ? ChibiExpression.surprised
                      : ChibiExpression.happy)),
          const PositionedDirectional(
              top: 0,
              end: -6,
              child: Text('🤥', style: TextStyle(fontSize: 36))),
        ]),
      ),
      Text(r.liar == you ? S.of('you') : (liar?.displayName ?? '—'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Pill(
          text: S.of(r.caught ? 'liarCaught' : 'liarEscaped'),
          color: r.caught ? Tokens.success : Tokens.coral,
          solid: true),
      const SizedBox(height: Tokens.s16),
      GlassCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('✅ ${S.of('theMainQuestion')}',
              style: const TextStyle(
                  color: Tokens.textDim, fontWeight: FontWeight.w700)),
          Text(r.mainQuestion,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const Divider(color: Tokens.glassBorder, height: Tokens.s20),
          Text('🤥 ${S.of('theOddQuestion')}',
              style: const TextStyle(
                  color: Tokens.coral, fontWeight: FontWeight.w700)),
          Text(r.oddQuestion,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
      ),
      const SizedBox(height: Tokens.s12),
      if (mine > 0)
        PopIn(
          child: Text('${S.of('youGotPoints')}: +$mine ⭐',
              style: const TextStyle(
                  color: Tokens.sun,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
        ),
    ]);
  }
}

/* -------------------------------- results ------------------------------- */

/// End of a Liar match: the last reveal, every round, and the final scores.
class LiarResults extends StatelessWidget {
  const LiarResults(
      {super.key,
      required this.view,
      required this.rewards,
      required this.actions});
  final RoomView view;
  final Widget rewards;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final f = view.liar!.final_!;
    final me = view.you;
    final byId = {for (final p in view.players) p.playerId: p};
    PublicPlayer? player(String? id) => byId[id];
    final won =
        f.ranking.where((r) => r.playerId == me).firstOrNull?.place == 1;
    return Stack(children: [
      ListView(
        padding:
            const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s24),
        children: [
          if (f.rounds.isNotEmpty)
            FadeSlideIn(
                child: _RoundReveal(
                    result: f.rounds.last, player: player, you: me)),
          const SizedBox(height: Tokens.s20),
          FadeSlideIn(
            delay: const Duration(milliseconds: 150),
            child: Text('🏆 ${S.of('finalScores')}',
                key: const Key('liarResultTitle'),
                style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: Tokens.s8),
          for (final r in f.ranking)
            Container(
              margin: const EdgeInsets.only(bottom: Tokens.s8),
              padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.s12, vertical: 8),
              decoration: BoxDecoration(
                color: r.playerId == me
                    ? Tokens.sun.withValues(alpha: 0.18)
                    : Tokens.glass,
                borderRadius: const BorderRadius.all(Tokens.r16),
                border: Border.all(
                    color: r.place == 1 ? Tokens.sun : Tokens.glassBorder),
              ),
              child: Row(children: [
                SizedBox(
                  width: 30,
                  child: Text(
                      r.place == 1
                          ? '🥇'
                          : r.place == 2
                              ? '🥈'
                              : r.place == 3
                                  ? '🥉'
                                  : '${r.place}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                ChibiAvatar(
                    avatarId: byId[r.playerId]?.avatarId ?? '', size: 38),
                const SizedBox(width: Tokens.s8),
                Expanded(
                  child: Text(
                      r.playerId == me
                          ? '${byId[r.playerId]?.displayName ?? ''} (${S.of('you')})'
                          : byId[r.playerId]?.displayName ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                Text('${r.score} ⭐',
                    style: const TextStyle(
                        color: Tokens.sun,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
          const SizedBox(height: Tokens.s12),
          Text('🔁 ${S.of('roundsSummary')}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Tokens.s8),
          for (final r in f.rounds)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GlassCard(
                radius: Tokens.r16,
                padding: const EdgeInsets.all(Tokens.s8),
                child: Row(children: [
                  Text('${r.round}',
                      style: const TextStyle(
                          color: Tokens.textDim, fontWeight: FontWeight.w800)),
                  const SizedBox(width: Tokens.s8),
                  ChibiAvatar(avatarId: byId[r.liar]?.avatarId ?? '', size: 30),
                  const SizedBox(width: Tokens.s8),
                  Expanded(
                    child: Text(r.oddQuestion,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  Text(r.caught ? '✅' : '😎',
                      style: const TextStyle(fontSize: 20)),
                ]),
              ),
            ),
          const SizedBox(height: Tokens.s12),
          rewards,
          const SizedBox(height: Tokens.s24),
          ...actions,
        ],
      ),
      if (won) const Positioned.fill(child: Confetti()),
    ]);
  }
}
