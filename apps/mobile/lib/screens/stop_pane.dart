import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sahra_client/sahra_client.dart';

import '../design/chibi_avatar.dart';
import '../design/sfx.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';

const _catEmoji = {
  'boy': '👦',
  'girl': '👧',
  'animal': '🐾',
  'plant': '🌱',
  'object': '📦',
  'country': '🌍',
};

/// Same comparison the server makes for the first letter: hamza on alef and
/// a leading "ال" do not matter. Only a hint; the server decides.
String stopInitial(String word) {
  var w = word.trim().replaceAll(RegExp('[ً-ٰٟـ]'), '');
  w = w.replaceAll(RegExp('[أإآٱ]'), 'ا');
  if (w.length > 3 && w.startsWith('ال')) w = w.substring(2);
  return w.isEmpty ? '' : w.substring(0, 1);
}

/// The big letter of the round.
class _LetterBadge extends StatelessWidget {
  const _LetterBadge({required this.letter, this.size = 72});
  final String letter;
  final double size;
  @override
  Widget build(BuildContext context) => PopIn(
        from: 0.3,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: Tokens.gradient(Tokens.sun, Tokens.orange),
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                  color: Tokens.orange.withValues(alpha: 0.5), blurRadius: 24)
            ],
          ),
          child: Text(letter,
              key: const Key('stopLetter'),
              style: TextStyle(
                  color: Tokens.ink,
                  fontSize: size * 0.5,
                  height: 1.1,
                  fontWeight: FontWeight.w900)),
        ),
      );
}

/// The live Stop match: fill the sheet, then see every answer scored.
class StopPane extends StatefulWidget {
  const StopPane(
      {super.key,
      required this.view,
      required this.session,
      required this.bubbles});
  final RoomView view;
  final GameSession session;
  final Map<String, String> bubbles;

  @override
  State<StopPane> createState() => _StopPaneState();
}

class _StopPaneState extends State<StopPane> {
  final Map<String, TextEditingController> _fields = {};
  String _stageKey = '';
  int _stageStart = 0;
  Timer? _save;
  bool _doneSent = false;
  final Set<String> _appealed = {};

  StopView get g => widget.view.stop!;
  String get you => widget.view.you;

  @override
  void initState() {
    super.initState();
    _syncStage();
  }

  @override
  void didUpdateWidget(StopPane old) {
    super.didUpdateWidget(old);
    _syncStage();
  }

  void _syncStage() {
    final key = '${g.round}-${g.stage}';
    if (key == _stageKey) return;
    final previous = _stageKey;
    _stageKey = key;
    _stageStart = widget.session.serverNow;
    if (g.stage == 'answer') {
      _doneSent = g.youDone;
      for (final c in g.categories) {
        (_fields[c] ??= TextEditingController()).text = g.yourAnswers[c] ?? '';
      }
    }
    if (previous.isEmpty) return;
    if (g.stage == 'answer') Sfx.play('whoosh', volume: 0.6);
    if (g.stage == 'review') {
      _save?.cancel();
      final mine = g.result?.points[you] ?? 0;
      Sfx.play(mine > 0 ? 'correct' : 'pop', volume: 0.6);
    }
  }

  @override
  void dispose() {
    _save?.cancel();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _sheet => {
        for (final e in _fields.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim()
      };

  void _changed() {
    setState(() {});
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 500),
        () => widget.session.stopAnswers(g.round, _sheet));
  }

  void _done() {
    _save?.cancel();
    HapticFeedback.mediumImpact();
    Sfx.play('pop', volume: 0.7);
    setState(() => _doneSent = true);
    widget.session.stopAnswers(g.round, _sheet, done: true);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, Tokens.s8),
        child: Column(children: [
          Row(children: [
            Pill(
                text:
                    '${S.of('roundWord')} ${g.round} ${S.of('of')} ${g.totalRounds}',
                color: Tokens.orange,
                emoji: '🚌'),
            const Spacer(),
            if (g.stage == 'answer' || g.stage == 'review')
              ServerTimerRing(
                  startsAt: _stageStart,
                  endsAt: g.stageEndsAt,
                  size: 54,
                  serverNow: () => widget.session.serverNow),
          ]),
          const SizedBox(height: Tokens.s8),
          Expanded(
            child: AnimatedSwitcher(
              duration: Tokens.medium,
              child: KeyedSubtree(
                  key: ValueKey(_stageKey),
                  child: g.stage == 'review' ? _review() : _answer()),
            ),
          ),
        ]),
      );

  Widget _answer() {
    final letter = g.letter ?? '';
    final locked = _doneSent || g.youDone;
    final n = widget.view.players.length;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _LetterBadge(letter: letter),
        const SizedBox(width: Tokens.s12),
        Flexible(
          child: Text(S.of('stopLetterHint'),
              style: const TextStyle(
                  color: Tokens.textDim,
                  fontSize: 15,
                  height: 1.4,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
      const SizedBox(height: Tokens.s12),
      Expanded(
        child: ListView(children: [
          for (final c in g.categories) ...[
            _field(c, letter, locked),
            const SizedBox(height: Tokens.s8),
          ],
        ]),
      ),
      const SizedBox(height: Tokens.s8),
      if (locked)
        Bob(
          child: Text(
              '⏳ ${S.of('waitingOthers')} ${g.doneCount}/$n · ${S.of('stopCanWait')}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Tokens.textDim,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        )
      else
        GameButton(
          key: const Key('stopDone'),
          label: S.of('stopDone'),
          icon: Icons.check_circle_rounded,
          color: Tokens.sun,
          onPressed: _done,
        ),
    ]);
  }

  Widget _field(String c, String letter, bool locked) {
    final ctrl = _fields[c] ??= TextEditingController();
    final text = ctrl.text.trim();
    final wrong = text.isNotEmpty && stopInitial(text) != letter;
    return TextField(
      key: Key('stop_$c'),
      controller: ctrl,
      enabled: !locked,
      maxLength: 40,
      textInputAction: TextInputAction.next,
      onChanged: (_) => _changed(),
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        counterText: '',
        labelText: '${_catEmoji[c] ?? ''}  ${S.of('stop_$c')}',
        helperText: wrong ? '${S.of('stopMustStart')} $letter' : null,
        helperStyle: const TextStyle(color: Tokens.orange),
        enabledBorder: wrong
            ? const OutlineInputBorder(
                borderRadius: BorderRadius.all(Tokens.r16),
                borderSide: BorderSide(color: Tokens.orange, width: 2))
            : null,
      ),
    );
  }

  Widget _review() {
    final r = g.result;
    if (r == null) return const SizedBox.shrink();
    final players = widget.view.players;
    return ListView(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _LetterBadge(letter: r.letter, size: 54),
        const SizedBox(width: Tokens.s12),
        Text(S.of('stopRoundScores'),
            style: Theme.of(context).textTheme.titleLarge),
      ]),
      const SizedBox(height: Tokens.s12),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: Tokens.s8,
        runSpacing: Tokens.s8,
        children: [
          for (final p in players)
            PopIn(
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 12, 4),
                decoration: BoxDecoration(
                  color: p.playerId == you
                      ? Tokens.sun.withValues(alpha: 0.2)
                      : Tokens.glass,
                  borderRadius: const BorderRadius.all(Radius.circular(99)),
                  border: Border.all(color: Tokens.glassBorder),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ChibiAvatar(
                      avatarId: p.avatarId,
                      frame: p.cosmetics?.frame,
                      size: 30),
                  const SizedBox(width: 6),
                  Text('+${r.points[p.playerId] ?? 0}',
                      style: const TextStyle(
                          color: Tokens.sun, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
        ],
      ),
      const SizedBox(height: Tokens.s12),
      for (final c in g.categories)
        if (r.cells[c] case final row?)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s8),
            child: GlassCard(
              radius: Tokens.r16,
              padding: const EdgeInsets.all(Tokens.s8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${_catEmoji[c] ?? ''}  ${S.of('stop_$c')}',
                        style: const TextStyle(
                            color: Tokens.textDim,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    for (final p in players)
                      if (row[p.playerId] case final cell?)
                        _cellRow(r.round, c, p, cell),
                  ]),
            ),
          ),
    ]);
  }

  Widget _cellRow(int round, String c, PublicPlayer p, StopCell cell) {
    final mine = p.playerId == you;
    final (badge, color) = switch (cell.verdict) {
      'unique' => ('+10', Tokens.success),
      'shared' => ('+5', Tokens.sky),
      'wrong_letter' => (S.of('stopWrongLetter'), Tokens.orange),
      'unknown' => (S.of('stopUnknown'), Tokens.textFaint),
      _ => ('—', Tokens.textFaint),
    };
    final appealed = cell.appealed || _appealed.contains('$round:$c');
    final text = cell.text ??
        (cell.verdict == 'unknown' ? '🔒 ${S.of('stopHidden')}' : '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        ChibiAvatar(avatarId: p.avatarId, frame: p.cosmetics?.frame, size: 26),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cell.text == null ? Tokens.textFaint : Colors.white,
                  decoration: cell.verdict == 'wrong_letter'
                      ? TextDecoration.lineThrough
                      : null)),
        ),
        // Practice saves nothing, so there is nothing to appeal there.
        if (mine &&
            cell.verdict == 'unknown' &&
            cell.text != null &&
            widget.view.mode != 'practice')
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: appealed
                ? Text('📨 ${S.of('stopAppealSent')}',
                    style: const TextStyle(
                        color: Tokens.mint,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800))
                : Pressable(
                    key: Key('appeal_$c'),
                    semanticLabel: S.of('stopAppeal'),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _appealed.add('$round:$c'));
                      widget.session.stopAppeal(round, c);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Tokens.grape,
                        borderRadius:
                            const BorderRadius.all(Radius.circular(99)),
                        border: Border.all(color: Colors.white54),
                      ),
                      child: Text('✋ ${S.of('stopAppeal')}',
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w800)),
                    ),
                  ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.22),
            borderRadius: const BorderRadius.all(Radius.circular(99)),
            border: Border.all(color: color),
          ),
          child: Text(badge,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }
}

/// End of a Stop match: ranking and each round's letter.
class StopResults extends StatelessWidget {
  const StopResults(
      {super.key,
      required this.view,
      required this.rewards,
      required this.actions});
  final RoomView view;
  final Widget rewards;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final f = view.stop!.final_!;
    final me = view.you;
    final byId = {for (final p in view.players) p.playerId: p};
    final won =
        f.ranking.where((r) => r.playerId == me).firstOrNull?.place == 1;
    return Stack(children: [
      ListView(
        padding:
            const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s24),
        children: [
          FadeSlideIn(
            child: Text('🚌 ${S.of(won ? 'youWon' : 'finalScores')}',
                key: const Key('stopResultTitle'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium),
          ),
          const SizedBox(height: Tokens.s12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Tokens.s8,
            children: [
              for (final r in f.rounds)
                _LetterBadge(letter: r.letter, size: 44),
            ],
          ),
          const SizedBox(height: Tokens.s16),
          for (final r in f.ranking)
            FadeSlideIn(
              child: Container(
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
                        const {1: '🥇', 2: '🥈', 3: '🥉'}[r.place] ??
                            '${r.place}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  ChibiAvatar(
                      avatarId: byId[r.playerId]?.avatarId ?? '',
                      size: 38,
                      expression: r.place == 1
                          ? ChibiExpression.happy
                          : ChibiExpression.neutral),
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
                  Text('${r.correct} ✅  ',
                      style: const TextStyle(
                          color: Tokens.textDim, fontWeight: FontWeight.w700)),
                  Text('${r.score} ⭐',
                      style: const TextStyle(
                          color: Tokens.sun,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          const SizedBox(height: Tokens.s8),
          Text(S.of('stopAppealNote'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Tokens.textFaint, fontSize: 13, height: 1.4)),
          const SizedBox(height: Tokens.s16),
          rewards,
          const SizedBox(height: Tokens.s24),
          ...actions,
        ],
      ),
      if (won) const Positioned.fill(child: IgnorePointer(child: Confetti())),
    ]);
  }
}
