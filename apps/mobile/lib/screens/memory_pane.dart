import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sahra_client/sahra_client.dart';

import '../design/chibi_avatar.dart';
import '../design/sfx.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';

const _modeEmoji = {'cards': '🃏', 'sequence': '🎨', 'spot': '🔍'};
const _padColors = [Tokens.coral, Tokens.sky, Tokens.mint, Tokens.sun];
const _padIcons = [
  Icons.favorite_rounded,
  Icons.water_drop_rounded,
  Icons.eco_rounded,
  Icons.star_rounded,
];

/// The live Memory Challenges match. Everything on screen follows the server
/// clock, so every player sees the board for exactly the same time.
class MemoryPane extends StatefulWidget {
  const MemoryPane(
      {super.key,
      required this.view,
      required this.session,
      required this.bubbles});
  final RoomView view;
  final GameSession session;
  final Map<String, String> bubbles;

  @override
  State<MemoryPane> createState() => _MemoryPaneState();
}

class _MemoryPaneState extends State<MemoryPane> {
  Timer? _tick;
  String _key = '';
  bool _answerOpened = false;
  final List<int> _taps = []; // sequence taps before sending
  bool _sent = false;
  int? _lastLit;

  MemoryView get g => widget.view.memory!;
  MemoryRound get r => g.round!;
  int get now => widget.session.serverNow;

  @override
  void initState() {
    super.initState();
    _sync();
    _tick = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) _frame();
    });
  }

  @override
  void didUpdateWidget(MemoryPane old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _sync() {
    if (g.round == null) return;
    final key = '${r.round}-${g.stage}';
    if (key == _key) return;
    final round = _key.split('-').first;
    _key = key;
    if (round != '${r.round}') {
      _answerOpened = false;
      _taps.clear();
      _sent = false;
    }
    if (g.stage == 'reveal') {
      final pts = g.reveal?.points[widget.view.you] ?? 0;
      if (pts > 0) {
        Sfx.correct();
      } else {
        Sfx.wrong();
      }
    }
  }

  /// Repaints while the clock matters, and plays the sequence's sounds.
  void _frame() {
    if (g.round == null) return;
    if (g.stage == 'show' && r.mode == 'sequence') {
      final lit = _litPad();
      if (lit != null && lit != _lastLit) Sfx.play('pop', volume: 0.5);
      _lastLit = lit;
    }
    if (!_answerOpened && g.stage == 'answer' && now >= r.answerAt) {
      _answerOpened = true;
      widget.session.markAnswerOpened();
      Sfx.play('whoosh', volume: 0.5);
    }
    setState(() {});
  }

  /// The pad lit right now in the sequence (each step: lit, then a short gap).
  int? _litPad() {
    final seq = r.sequence;
    if (seq == null || now < r.showAt) return null;
    final t = now - r.showAt;
    final i = t ~/ r.stepMs;
    if (i >= seq.length || t % r.stepMs > r.stepMs * 0.75) return null;
    return seq[i];
  }

  bool get _canAnswer =>
      g.stage == 'answer' && now >= r.answerAt && !g.youDone && !_sent;

  @override
  Widget build(BuildContext context) {
    if (g.round == null) return const SizedBox.shrink();
    final showing = g.stage == 'show' && now >= r.showAt && now < r.hideAt;
    final timer = g.stage == 'show'
        ? (start: r.showAt, end: r.hideAt)
        : (start: r.answerAt, end: r.deadline);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, Tokens.s8),
      child: Column(children: [
        Row(children: [
          Pill(
              text:
                  '${S.of('mem_${r.mode}')} · ${r.round} ${S.of('of')} ${r.total}',
              color: Tokens.mint,
              emoji: _modeEmoji[r.mode]),
          const Spacer(),
          if (g.stage != 'reveal')
            ServerTimerRing(
                key: ValueKey('t$_key'),
                startsAt: timer.start,
                endsAt: timer.end,
                size: 54,
                serverNow: () => widget.session.serverNow),
        ]),
        const SizedBox(height: Tokens.s12),
        Text(_instruction(showing),
            key: const Key('memInstruction'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 20, height: 1.35, fontWeight: FontWeight.w800)),
        const SizedBox(height: Tokens.s12),
        if (r.mode == 'cards' && r.targets != null) ...[
          _targetsRow(),
          const SizedBox(height: Tokens.s12),
        ],
        Expanded(child: Center(child: _board(showing))),
        const SizedBox(height: Tokens.s8),
        _footer(),
      ]),
    );
  }

  String _instruction(bool showing) {
    switch (g.stage) {
      case 'show':
        if (now < r.showAt) return '👀 ${S.of('memGetReady')}';
        if (showing) return S.of('memMemorize_${r.mode}');
        return '🙈 ${S.of('memHidden')}';
      case 'answer':
        if (now < r.answerAt) return '🙈 ${S.of('memHidden')}';
        if (g.youDone || _sent) {
          return '⏳ ${S.of('waitingOthers')} ${g.doneCount}/${widget.view.players.length}';
        }
        if (r.mode == 'cards') {
          final step = g.yourAnswer.length;
          final target =
              step < (r.targets?.length ?? 0) ? r.targets![step] : '';
          return '${S.of('memWhereWas')} $target ؟';
        }
        return S.of('memAsk_${r.mode}');
      default:
        final pts = g.reveal?.points[widget.view.you] ?? 0;
        final c = g.reveal?.correct[widget.view.you] ?? 0;
        return pts > 0
            ? '🎉 +$pts  ($c/${g.reveal?.parts ?? 0})'
            : '😅 ${S.of('memMissed')}';
    }
  }

  Widget _targetsRow() {
    final step = g.yourAnswer.length;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (final (i, t) in r.targets!.indexed)
        AnimatedContainer(
          duration: Tokens.fast,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: i == step && g.stage == 'answer'
                ? Tokens.sun
                : Tokens.glassStrong,
            borderRadius: const BorderRadius.all(Tokens.r16),
            border: Border.all(
                color: i < step ? Tokens.mint : Colors.white24, width: 2),
          ),
          child: Text(t, style: const TextStyle(fontSize: 30)),
        ),
    ]);
  }

  Widget _board(bool showing) {
    if (r.mode == 'sequence') return _pads(showing);
    final reveal = g.reveal;
    final List<String?> faces;
    if (showing) {
      faces = r.grid ?? List.filled(r.cells, null);
    } else if (g.stage == 'reveal') {
      faces = r.mode == 'spot'
          ? (r.changedGrid ?? List.filled(r.cells, null))
          : (r.grid ?? List.filled(r.cells, null));
    } else if (g.stage == 'answer' && now >= r.answerAt && r.mode == 'spot') {
      faces = r.changedGrid ?? List.filled(r.cells, null);
    } else {
      faces = List.filled(r.cells, null);
    }
    Color? mark(int i) {
      if (reveal != null) {
        if (reveal.answer.contains(i)) return Tokens.success;
        if (g.yourAnswer.contains(i)) return Tokens.danger;
        return null;
      }
      return g.yourAnswer.contains(i) ? Tokens.sun : null;
    }

    String? badge(int i) {
      // Cards: the target you placed on this card.
      if (r.mode != 'cards' || r.targets == null) return null;
      final k = g.yourAnswer.indexOf(i);
      return k >= 0 && k < r.targets!.length ? r.targets![k] : null;
    }

    return LayoutBuilder(builder: (context, c) {
      final rows = (r.cells / r.columns).ceil();
      final size = [
        (c.maxWidth - (r.columns - 1) * 10) / r.columns,
        (c.maxHeight - (rows - 1) * 10) / rows,
        110.0
      ].reduce((a, b) => a < b ? a : b);
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < r.cells; i++)
            _Tile(
              key: Key('cell$i'),
              size: size,
              face: faces[i],
              mark: mark(i),
              badge: badge(i),
              onTap: _canAnswer && !g.yourAnswer.contains(i)
                  ? () {
                      HapticFeedback.selectionClick();
                      Sfx.play('pop', volume: 0.6);
                      if (r.mode == 'spot') setState(() => _sent = true);
                      widget.session.memoryPick(r.round, i);
                    }
                  : null,
            ),
        ],
      );
    });
  }

  Widget _pads(bool showing) {
    final lit = showing ? _litPad() : null;
    final reveal = g.reveal;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final row in const [
        [0, 1],
        [2, 3]
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final i in row)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _Pad(
                  key: Key('pad$i'),
                  index: i,
                  lit: lit == i,
                  onTap: _canAnswer
                      ? () {
                          HapticFeedback.selectionClick();
                          Sfx.play('pop', volume: 0.6);
                          setState(() => _taps.add(i));
                          if (_taps.length >= r.length) _sendSequence();
                        }
                      : null,
                ),
              ),
          ]),
        ),
      const SizedBox(height: 4),
      // Your taps (or, after the round, the right order and yours).
      if (reveal != null) ...[
        _dots(reveal.answer, label: '✅'),
        const SizedBox(height: 6),
        _dots(g.yourAnswer, label: '👤'),
      ] else
        _dots(g.youDone ? g.yourAnswer : _taps,
            slots: g.stage == 'answer' ? r.length : 0),
    ]);
  }

  Widget _dots(List<int> items, {int slots = 0, String? label}) {
    final n = slots > items.length ? slots : items.length;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (label != null)
        Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: Text(label, style: const TextStyle(fontSize: 16))),
      for (var i = 0; i < n; i++)
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < items.length ? _padColors[items[i]] : Colors.transparent,
            border: Border.all(color: Colors.white54, width: 2),
          ),
        ),
    ]);
  }

  void _sendSequence() {
    if (_sent) return;
    setState(() => _sent = true);
    widget.session.memorySequence(r.round, List.of(_taps));
  }

  Widget _footer() {
    if (g.stage == 'answer' &&
        r.mode == 'sequence' &&
        _canAnswer &&
        _taps.isNotEmpty) {
      return Row(children: [
        Expanded(
          child: GameButton(
              label: S.of('memClear'),
              color: Tokens.glassStrong,
              onPressed: () => setState(_taps.clear)),
        ),
        const SizedBox(width: Tokens.s8),
        Expanded(
          flex: 2,
          child: GameButton(
              key: const Key('memSend'),
              label: S.of('memSend'),
              icon: Icons.check_rounded,
              color: Tokens.mint,
              onPressed: _sendSequence),
        ),
      ]);
    }
    final reveal = g.reveal;
    final players = widget.view.players;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: Tokens.s8,
      runSpacing: Tokens.s8,
      children: [
        for (final p in players)
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(3, 3, 10, 3),
            decoration: BoxDecoration(
              color: p.playerId == widget.view.you
                  ? Tokens.sun.withValues(alpha: 0.2)
                  : Tokens.glass,
              borderRadius: const BorderRadius.all(Radius.circular(99)),
              border: Border.all(color: Tokens.glassBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ChibiAvatar(
                  avatarId: p.avatarId,
                  size: 28,
                  expression: reveal == null
                      ? ChibiExpression.neutral
                      : (reveal.points[p.playerId] ?? 0) > 0
                          ? ChibiExpression.happy
                          : ChibiExpression.sad),
              const SizedBox(width: 5),
              Text(
                  reveal == null
                      ? '${g.scores[p.playerId] ?? 0}'
                      : '+${reveal.points[p.playerId] ?? 0}',
                  style: const TextStyle(
                      color: Tokens.sun, fontWeight: FontWeight.w900)),
            ]),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(
      {super.key,
      required this.size,
      required this.face,
      this.mark,
      this.badge,
      this.onTap});
  final double size;
  final String? face;
  final Color? mark;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final up = face != null;
    return Pressable(
      onTap: onTap,
      semanticLabel: face ?? '🂠',
      child: AnimatedContainer(
        duration: Tokens.fast,
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: up ? Colors.white : null,
          gradient: up ? null : Tokens.gradient(Tokens.grape, Tokens.sky),
          borderRadius: BorderRadius.all(Radius.circular(size * 0.2)),
          border: Border.all(
              color: mark ?? Colors.white.withValues(alpha: 0.7),
              width: mark != null ? 4 : 2),
          boxShadow: [
            BoxShadow(
                color: (mark ?? Colors.black).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4)),
          ],
        ),
        child: up
            ? Text(face!, style: TextStyle(fontSize: size * 0.5))
            : badge != null
                ? Text(badge!, style: TextStyle(fontSize: size * 0.42))
                : Text('؟',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: size * 0.4,
                        fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad({super.key, required this.index, required this.lit, this.onTap});
  final int index;
  final bool lit;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final color = _padColors[index];
    return Pressable(
      onTap: onTap,
      semanticLabel: '${S.of('memPad')} ${index + 1}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: 128,
        height: 128,
        decoration: BoxDecoration(
          color: lit ? Tokens.tint(color, 0.35) : Tokens.shade(color, 0.25),
          borderRadius: const BorderRadius.all(Tokens.r32),
          border: Border.all(
              color: lit ? Colors.white : Colors.white24, width: lit ? 5 : 2),
          boxShadow: [
            if (lit)
              BoxShadow(
                  color: color.withValues(alpha: 0.9),
                  blurRadius: 34,
                  spreadRadius: 4),
          ],
        ),
        child: Icon(_padIcons[index],
            size: 54, color: Colors.white.withValues(alpha: lit ? 1 : 0.6)),
      ),
    );
  }
}

/// End of a Memory match: ranking and perfect rounds.
class MemoryResults extends StatelessWidget {
  const MemoryResults(
      {super.key,
      required this.view,
      required this.rewards,
      required this.actions});
  final RoomView view;
  final Widget rewards;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ranking = view.memory!.ranking!;
    final me = view.you;
    final byId = {for (final p in view.players) p.playerId: p};
    final won = ranking.where((r) => r.playerId == me).firstOrNull?.place == 1;
    return Stack(children: [
      ListView(
        padding:
            const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s24),
        children: [
          FadeSlideIn(
            child: Text('🧩 ${S.of(won ? 'youWon' : 'finalScores')}',
                key: const Key('memResultTitle'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium),
          ),
          const SizedBox(height: Tokens.s16),
          if (ranking.isNotEmpty)
            Center(
              child: Bob(
                child: ChibiFullBody(
                    avatarId: byId[ranking.first.playerId]?.avatarId ?? '',
                    height: 170),
              ),
            ),
          const SizedBox(height: Tokens.s12),
          for (final r in ranking)
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
                  Text('${r.correct} 💯  ',
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
          const SizedBox(height: Tokens.s4),
          Text(S.of('memPerfectNote'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Tokens.textFaint, fontSize: 13)),
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
