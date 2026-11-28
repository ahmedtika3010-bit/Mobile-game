import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sahra_client/sahra_client.dart';

import '../design/chibi_avatar.dart';
import '../design/sfx.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';

/// Same palette and brush sizes as packages/shared/src/draw.ts.
const drawColors = [
  Color(0xFF1E2230),
  Color(0xFFE5484D),
  Color(0xFFF76B15),
  Color(0xFFFFC53D),
  Color(0xFF30A46C),
  Color(0xFF0090FF),
  Color(0xFF8E4EC6),
  Color(0xFF8D5B3A),
  Color(0xFFFFFFFF),
];
const drawWidths = [7.0, 16.0, 36.0];
const _teamColors = [Tokens.sky, Tokens.orange];
const _diffColor = {
  'easy': Tokens.mint,
  'medium': Tokens.sun,
  'hard': Tokens.coral
};

/// The live Draw and Guess match: the drawer draws on a shared canvas (only
/// new strokes travel over the network), everyone else types guesses that
/// only they can see.
class DrawPane extends StatefulWidget {
  const DrawPane(
      {super.key,
      required this.view,
      required this.session,
      required this.bubbles,
      required this.onPlayer});
  final RoomView view;
  final GameSession session;
  final Map<String, String> bubbles;
  final void Function(PublicPlayer) onPlayer;

  @override
  State<DrawPane> createState() => _DrawPaneState();
}

class _DrawPaneState extends State<DrawPane> {
  final _guess = TextEditingController();
  final _guessFocus = FocusNode();
  StreamSubscription<void>? _canvasSub;
  Timer? _flush;
  Timer? _clock;

  // Drawer: every operation made this turn (sent or not) and the unsent ones.
  final List<Map<String, dynamic>> _mine = [];
  final List<Map<String, Object>> _queue = [];
  List<int>? _current; // points of the stroke being drawn
  int _currentSent = 0; // of those, already queued
  bool _currentStarted = false;
  int _color = 0;
  int _width = 1;

  String _key = '';
  int _guessedBefore = 0;
  int? _drawSeenLocal;

  DrawView get g => widget.view.draw!;
  DrawTurn? get t => g.turn;
  String get me => widget.view.you;
  bool get isDrawer => t?.drawer == me;
  int get now => widget.session.serverNow;

  @override
  void initState() {
    super.initState();
    _canvasSub = widget.session.canvas.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _flush = Timer.periodic(const Duration(milliseconds: 120), (_) => _send());
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    _sync();
  }

  @override
  void didUpdateWidget(DrawPane old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _canvasSub?.cancel();
    _flush?.cancel();
    _clock?.cancel();
    _guess.dispose();
    _guessFocus.dispose();
    super.dispose();
  }

  void _sync() {
    final turn = t;
    if (turn == null) return;
    final key = '${turn.turn}-${g.stage}';
    if (key != _key) {
      final newTurn = _key.split('-').first != '${turn.turn}';
      _key = key;
      if (newTurn) {
        _mine.clear();
        _queue.clear();
        _current = null;
        _guessedBefore = 0;
        _drawSeenLocal = null;
        _guess.clear();
        if (turn.drawer == me) Sfx.play('whoosh', volume: 0.6);
      }
      if (g.stage == 'draw') {
        _drawSeenLocal ??= DateTime.now().millisecondsSinceEpoch;
        if (!isDrawer) Future.microtask(_guessFocus.requestFocus);
      }
      if (g.stage == 'reveal') {
        final pts = g.reveal?.points[me] ?? 0;
        pts > 0 ? Sfx.correct() : Sfx.play('pop', volume: 0.5);
      }
    }
    // A new player got it.
    if (g.stage == 'draw' && turn.guessed.length > _guessedBefore) {
      if (turn.guessed.contains(me) &&
          !turn.guessed.take(_guessedBefore).contains(me)) {
        Sfx.correct();
        HapticFeedback.mediumImpact();
      } else {
        Sfx.play('pop', volume: 0.6);
      }
      _guessedBefore = turn.guessed.length;
    }
  }

  /* ------------------------------ drawing ------------------------------ */

  bool get _canDraw => isDrawer && g.stage == 'draw' && now < t!.deadline;

  List<int> _pt(Offset p, double size) => [
        (p.dx / size * 1000).round().clamp(0, 1000),
        (p.dy / size * 1000).round().clamp(0, 1000),
      ];

  void _start(Offset p, double size) {
    if (!_canDraw) return;
    _current = [..._pt(p, size)];
    _currentSent = 0;
    _currentStarted = false;
    final op = {
      't': 'b',
      'c': _color,
      'w': _width,
      'p': <int>[..._current!]
    };
    _mine.add(op);
    setState(() {});
  }

  void _move(Offset p, double size) {
    final cur = _current;
    if (cur == null || !_canDraw) return;
    final next = _pt(p, size);
    final dx = next[0] - cur[cur.length - 2];
    final dy = next[1] - cur[cur.length - 1];
    if (dx * dx + dy * dy < 36) return; // skip points closer than 6 units
    cur.addAll(next);
    (_mine.last['p'] as List<int>).addAll(next);
    setState(() {});
  }

  void _end() {
    final cur = _current;
    if (cur == null) return;
    if (cur.length == 2) {
      // A tap: a dot.
      cur.addAll([cur[0] + 1, cur[1]]);
      (_mine.last['p'] as List<int>).addAll([cur[0] + 1, cur[1]]);
    }
    _queueCurrent();
    _current = null;
  }

  /// Moves the points drawn so far into the send queue (begin, then chunks).
  void _queueCurrent() {
    final cur = _current;
    if (cur == null || cur.length <= _currentSent) return;
    final fresh = cur.sublist(_currentSent);
    for (var i = 0; i < fresh.length; i += 128) {
      final chunk =
          fresh.sublist(i, i + 128 > fresh.length ? fresh.length : i + 128);
      if (!_currentStarted) {
        _queue.add({'t': 'b', 'c': _color, 'w': _width, 'p': chunk});
        _currentStarted = true;
      } else {
        _queue.add({'t': 'p', 'p': chunk});
      }
    }
    _currentSent = cur.length;
  }

  void _send() {
    if (!mounted || !isDrawer) return;
    _queueCurrent();
    if (_queue.isEmpty || g.stage != 'draw') return;
    while (_queue.isNotEmpty) {
      final batch = _queue.take(16).toList();
      _queue.removeRange(0, batch.length);
      widget.session.drawOps(t!.turn, batch);
    }
  }

  void _undo() {
    if (!_canDraw) return;
    _send();
    _mine.add({'t': 'u'});
    _queue.add({'t': 'u'});
    HapticFeedback.selectionClick();
    setState(() {});
    _send();
  }

  void _clear() {
    if (!_canDraw) return;
    _send();
    _mine.add({'t': 'x'});
    _queue.add({'t': 'x'});
    HapticFeedback.mediumImpact();
    setState(() {});
    _send();
  }

  List<DrawStroke> get _strokes {
    final shared = widget.session.canvas;
    final current = 't${t?.turn}';
    final ops = isDrawer && _mine.length >= shared.ops.length
        ? _mine
        : (shared.key == current ? shared.ops : const <Map<String, dynamic>>[]);
    return DrawCanvas.strokesOf(ops);
  }

  /* ------------------------------ guessing ------------------------------ */

  void _submitGuess() {
    final text = _guess.text.trim();
    final turn = t;
    if (text.isEmpty || turn == null || g.stage != 'draw') return;
    final seen = _drawSeenLocal;
    widget.session.drawGuess(turn.turn, text,
        elapsedMs:
            seen == null ? null : DateTime.now().millisecondsSinceEpoch - seen);
    _guess.clear();
    HapticFeedback.selectionClick();
  }

  void _hide() {
    final turn = t;
    if (turn == null) return;
    widget.session.drawHide(turn.turn);
    HapticFeedback.mediumImpact();
  }

  PublicPlayer? _player(String id) =>
      widget.view.players.where((p) => p.playerId == id).firstOrNull;

  /* -------------------------------- build -------------------------------- */

  @override
  Widget build(BuildContext context) {
    final turn = t;
    if (turn == null) return const SizedBox.shrink();
    final timer = switch (g.stage) {
      'choose' => (start: turn.chooseEndsAt - 12000, end: turn.chooseEndsAt),
      'draw' => (start: turn.startedAt, end: turn.deadline),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, Tokens.s8),
      child: Column(children: [
        Row(children: [
          Pill(
              text:
                  '${S.of('game_draw')} · ${turn.turn} ${S.of('of')} ${turn.total}',
              color: Tokens.sky,
              emoji: '🎨'),
          const SizedBox(width: 6),
          if (turn.category != null)
            Pill(text: S.of('draw_cat_${turn.category}'), color: Tokens.sun),
          const Spacer(),
          if (timer != null)
            ServerTimerRing(
                key: ValueKey('t$_key'),
                startsAt: timer.start,
                endsAt: timer.end,
                size: 50,
                serverNow: () => widget.session.serverNow),
        ]),
        const SizedBox(height: Tokens.s8),
        _header(turn),
        const SizedBox(height: Tokens.s8),
        Expanded(child: Center(child: _middle(turn))),
        const SizedBox(height: Tokens.s8),
        _controls(turn),
        const SizedBox(height: Tokens.s8),
        _footer(turn),
      ]),
    );
  }

  Widget _header(DrawTurn turn) {
    final drawer = _player(turn.drawer);
    switch (g.stage) {
      case 'choose':
        return Text(
            isDrawer
                ? S.of('drawChoose')
                : '${drawer?.displayName ?? ''} ${S.of('drawChoosing')}',
            key: const Key('drawHeader'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800));
      case 'draw':
        if (isDrawer) {
          return Column(children: [
            Text('${S.of('drawYourWord')} ${turn.word ?? ''}',
                key: const Key('drawHeader'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24,
                    color: Tokens.sun,
                    fontWeight: FontWeight.w900)),
            Text(S.of('drawNoText'),
                style: const TextStyle(color: Tokens.textDim, fontSize: 13)),
          ]);
        }
        return _Shape(
            key: const Key('drawHeader'),
            shape: turn.shape ?? const [],
            word: turn.youGuessed ? turn.word : null);
      default:
        final r = g.reveal;
        final ended = r?.ended ?? 'time';
        return Column(children: [
          Text('${S.of('drawWasWord')}: ${r?.word ?? ''}',
              key: const Key('drawHeader'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22,
                  color: Tokens.sun,
                  fontWeight: FontWeight.w900)),
          Text(S.of('drawEnded_$ended'),
              style: const TextStyle(color: Tokens.textDim, fontSize: 14)),
        ]);
    }
  }

  Widget _middle(DrawTurn turn) {
    if (g.stage == 'choose') {
      if (isDrawer && turn.choices != null) return _choices(turn);
      final drawer = _player(turn.drawer);
      return Bob(
          child: ChibiFullBody(
              avatarId: drawer?.avatarId ?? '',
              height: 190,
              expression: ChibiExpression.happy));
    }
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, c) {
        final size = c.maxWidth;
        final hidden = turn.youHid ||
            (g.reveal?.ended == 'stopped' && g.stage == 'reveal');
        return ClipRRect(
          borderRadius: const BorderRadius.all(Tokens.r24),
          child: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                key: const Key('drawCanvas'),
                onPanStart: (d) => _start(d.localPosition, size),
                onPanUpdate: (d) => _move(d.localPosition, size),
                onPanEnd: (_) => _end(),
                onPanCancel: _end,
                child: Container(
                  color: Colors.white,
                  child: hidden
                      ? null
                      : CustomPaint(
                          painter: _CanvasPainter(_strokes),
                          size: Size.square(size)),
                ),
              ),
            ),
            if (hidden) Positioned.fill(child: _hiddenCover(turn)),
            if (!isDrawer && !hidden && g.stage == 'draw')
              PositionedDirectional(
                top: 6,
                end: 6,
                child: Pressable(
                  key: const Key('drawHide'),
                  onTap: _hide,
                  semanticLabel: S.of('drawHide'),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                        color: Color(0x22000000), shape: BoxShape.circle),
                    child: const Icon(Icons.visibility_off_rounded,
                        color: Tokens.inkSoft, size: 22),
                  ),
                ),
              ),
            if (g.stage == 'reveal' && !hidden)
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Center(
                  child: Pill(
                      text: g.reveal?.word ?? '',
                      color: Tokens.grape,
                      solid: true,
                      emoji: '✏️'),
                ),
              ),
          ]),
        );
      }),
    );
  }

  Widget _hiddenCover(DrawTurn turn) {
    final drawer = _player(turn.drawer);
    final stopped = g.reveal?.ended == 'stopped';
    return Container(
      color: Tokens.paper,
      padding: const EdgeInsets.all(Tokens.s16),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🙈', style: TextStyle(fontSize: 46)),
        const SizedBox(height: 6),
        Text(S.of(stopped ? 'drawEnded_stopped' : 'drawHidden'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Tokens.ink, fontSize: 16, fontWeight: FontWeight.w800)),
        if (drawer != null && !isDrawer) ...[
          const SizedBox(height: Tokens.s12),
          GameButton(
              key: const Key('drawReport'),
              label: S.of('drawReportDrawer'),
              icon: Icons.flag_rounded,
              color: Tokens.coral,
              expand: false,
              size: GameButtonSize.medium,
              onPressed: () => widget.onPlayer(drawer)),
        ],
      ]),
    );
  }

  Widget _choices(DrawTurn turn) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, c) in turn.choices!.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s12),
              child: FadeSlideIn(
                delay: Duration(milliseconds: 80 * i),
                child: Pressable(
                  key: Key('drawChoice$i'),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.session.drawChoose(turn.turn, i);
                  },
                  semanticLabel: c.word,
                  child: Container(
                    width: 300,
                    padding: const EdgeInsets.symmetric(
                        horizontal: Tokens.s16, vertical: Tokens.s12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.all(Tokens.r20),
                      border: Border.all(
                          color: _diffColor[c.difficulty] ?? Tokens.sun,
                          width: 3),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x40000000),
                            blurRadius: 10,
                            offset: Offset(0, 4))
                      ],
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Text(c.word,
                            style: const TextStyle(
                                color: Tokens.ink,
                                fontSize: 24,
                                fontWeight: FontWeight.w900)),
                      ),
                      Pill(
                          text: S.of('drawDiff_${c.difficulty}'),
                          color: _diffColor[c.difficulty] ?? Tokens.sun,
                          solid: true),
                      const SizedBox(width: 6),
                      Text('+${c.points}',
                          style: const TextStyle(
                              color: Tokens.inkSoft,
                              fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _controls(DrawTurn turn) {
    if (g.stage != 'draw') return const SizedBox.shrink();
    if (isDrawer) return _tools();
    if (turn.youGuessed) {
      return Text(S.of('drawGotIt'),
          key: const Key('drawGotIt'),
          style: const TextStyle(
              fontSize: 20,
              color: Tokens.success,
              fontWeight: FontWeight.w900));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          child: TextField(
            key: const Key('drawGuess'),
            controller: _guess,
            focusNode: _guessFocus,
            maxLength: 40,
            textInputAction: TextInputAction.send,
            // Keeps the keyboard open between guesses (no unfocus on submit).
            onEditingComplete: _submitGuess,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
                hintText: S.of('drawGuessHint'), counterText: ''),
          ),
        ),
        const SizedBox(width: Tokens.s8),
        GameButton(
            key: const Key('drawSend'),
            label: S.of('drawSend'),
            expand: false,
            color: Tokens.sun,
            onPressed: _submitGuess),
      ]),
      if (turn.close || turn.yourGuesses.isNotEmpty) ...[
        const SizedBox(height: 6),
        SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (turn.close)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: Pill(
                      text: S.of('drawClose'),
                      color: Tokens.orange,
                      solid: true),
                ),
              for (final w in turn.yourGuesses.reversed.take(8))
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: const BoxDecoration(
                        color: Tokens.glass,
                        borderRadius: BorderRadius.all(Radius.circular(99))),
                    child: Text(w,
                        style: const TextStyle(
                            color: Tokens.textDim,
                            decoration: TextDecoration.lineThrough,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ),
      ],
    ]);
  }

  Widget _tools() => Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < drawColors.length; i++)
                Pressable(
                  key: Key('drawColor$i'),
                  onTap: () => setState(() => _color = i),
                  semanticLabel: '${S.of('drawColor')} ${i + 1}',
                  child: AnimatedContainer(
                    duration: Tokens.fast,
                    width: _color == i ? 36 : 30,
                    height: _color == i ? 36 : 30,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: drawColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: _color == i ? Tokens.sun : Colors.white38,
                          width: _color == i ? 3 : 1.5),
                    ),
                    child: i == drawColors.length - 1
                        ? const Icon(Icons.auto_fix_normal_rounded,
                            size: 16, color: Tokens.inkSoft)
                        : null,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < drawWidths.length; i++)
            Pressable(
              key: Key('drawWidth$i'),
              onTap: () => setState(() => _width = i),
              semanticLabel: '${S.of('drawSize')} ${i + 1}',
              child: Container(
                width: 44,
                height: 44,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _width == i ? Tokens.glassStrong : Tokens.glass,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _width == i ? Tokens.sun : Tokens.glassBorder,
                      width: 2),
                ),
                child: Container(
                  width: 6.0 + i * 8,
                  height: 6.0 + i * 8,
                  decoration: BoxDecoration(
                      color: _color == drawColors.length - 1
                          ? Colors.white
                          : drawColors[_color],
                      shape: BoxShape.circle),
                ),
              ),
            ),
          const SizedBox(width: Tokens.s12),
          _toolButton(Icons.undo_rounded, 'drawUndo', _undo),
          _toolButton(Icons.delete_sweep_rounded, 'drawClear', _clear),
        ]),
      ]);

  Widget _toolButton(IconData icon, String label, VoidCallback onTap) =>
      Pressable(
        key: Key(label),
        onTap: onTap,
        semanticLabel: S.of(label),
        child: Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration:
              const BoxDecoration(color: Tokens.glass, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white),
        ),
      );

  Widget _footer(DrawTurn turn) {
    final reveal = g.reveal;
    final teams = g.teamOf;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (teams != null && g.teamScores != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final i in const [0, 1]) ...[
              Pill(
                  text: '${S.of('drawTeam$i')}  ${g.teamScores![i]}',
                  color: _teamColors[i]),
              if (i == 0) const SizedBox(width: Tokens.s8),
            ],
          ]),
        ),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: Tokens.s8,
        runSpacing: Tokens.s8,
        children: [
          for (final p in widget.view.players)
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(3, 3, 10, 3),
              decoration: BoxDecoration(
                color: turn.guessed.contains(p.playerId)
                    ? Tokens.success.withValues(alpha: 0.25)
                    : p.playerId == me
                        ? Tokens.sun.withValues(alpha: 0.2)
                        : Tokens.glass,
                borderRadius: const BorderRadius.all(Radius.circular(99)),
                border: Border.all(
                    color: teams != null && teams[p.playerId] != null
                        ? _teamColors[teams[p.playerId]!]
                        : Tokens.glassBorder,
                    width: teams != null ? 2 : 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ChibiAvatar(
                    avatarId: p.avatarId,
                    frame: p.cosmetics?.frame,
                    size: 28,
                    expression: turn.guessed.contains(p.playerId)
                        ? ChibiExpression.happy
                        : ChibiExpression.neutral),
                const SizedBox(width: 4),
                if (p.playerId == turn.drawer)
                  const Text('✏️ ', style: TextStyle(fontSize: 14)),
                if (turn.guessed.contains(p.playerId))
                  const Text('✅ ', style: TextStyle(fontSize: 13)),
                Text(
                    reveal == null
                        ? '${g.scores[p.playerId] ?? 0}'
                        : '+${reveal.points[p.playerId] ?? 0}',
                    style: const TextStyle(
                        color: Tokens.sun, fontWeight: FontWeight.w900)),
              ]),
            ),
        ],
      ),
    ]);
  }
}

/// The word's shape for guessers: a box per letter, revealed hint letters filled in.
class _Shape extends StatelessWidget {
  const _Shape({super.key, required this.shape, this.word});
  final List<String> shape;
  final String? word;

  @override
  Widget build(BuildContext context) {
    if (word != null) {
      return Text(word!,
          style: const TextStyle(
              fontSize: 24,
              color: Tokens.success,
              fontWeight: FontWeight.w900));
    }
    final letters = shape.where((c) => c != ' ').length;
    return Semantics(
      label: '${S.of('drawLetters')} $letters',
      child: Wrap(
        alignment: WrapAlignment.center,
        textDirection: TextDirection.rtl,
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final c in shape)
            c == ' '
                ? const SizedBox(width: 14)
                : Container(
                    width: 30,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.isEmpty ? Tokens.glass : Tokens.sun,
                      borderRadius: const BorderRadius.all(Tokens.r8),
                      border: Border.all(color: Tokens.glassBorder, width: 2),
                    ),
                    child: Text(c,
                        style: const TextStyle(
                            color: Tokens.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w900)),
                  ),
          const SizedBox(width: 8),
          Text('($letters)',
              style: const TextStyle(
                  color: Tokens.textDim, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter(this.strokes);
  final List<DrawStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 1000;
    for (final s in strokes) {
      final paint = Paint()
        ..color = drawColors[s.color.clamp(0, drawColors.length - 1)]
        ..strokeWidth = drawWidths[s.width.clamp(0, drawWidths.length - 1)] * k
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final p = s.points;
      if (p.length < 2) continue;
      final path = Path()..moveTo(p[0] * k, p[1] * k);
      if (p.length == 2) {
        path.lineTo(p[0] * k + 0.1, p[1] * k);
      }
      for (var i = 2; i + 1 < p.length; i += 2) {
        // Smooth with midpoints between samples.
        if (i + 3 < p.length) {
          final mx = (p[i] + p[i + 2]) / 2 * k;
          final my = (p[i + 1] + p[i + 3]) / 2 * k;
          path.quadraticBezierTo(p[i] * k, p[i + 1] * k, mx, my);
        } else {
          path.lineTo(p[i] * k, p[i + 1] * k);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter old) => true;
}

/// End of a Draw and Guess match: ranking (and the team result in team mode).
class DrawResults extends StatelessWidget {
  const DrawResults(
      {super.key,
      required this.view,
      required this.rewards,
      required this.actions});
  final RoomView view;
  final Widget rewards;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final d = view.draw!;
    final ranking = d.ranking!;
    final me = view.you;
    final byId = {for (final p in view.players) p.playerId: p};
    final won = ranking.where((r) => r.playerId == me).firstOrNull?.place == 1;
    final teams = d.finalTeamScores;
    final winnerTeam = teams == null
        ? null
        : teams[0] == teams[1]
            ? -1
            : (teams[0] > teams[1] ? 0 : 1);
    return Stack(children: [
      ListView(
        padding:
            const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s24),
        children: [
          FadeSlideIn(
            child: Text('🎨 ${S.of(won ? 'youWon' : 'finalScores')}',
                key: const Key('drawResultTitle'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium),
          ),
          if (teams != null) ...[
            const SizedBox(height: Tokens.s12),
            Row(children: [
              for (final i in const [0, 1]) ...[
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(Tokens.s12),
                    decoration: BoxDecoration(
                      color: _teamColors[i].withValues(alpha: 0.18),
                      borderRadius: const BorderRadius.all(Tokens.r20),
                      border: Border.all(
                          color: _teamColors[i],
                          width: winnerTeam == i || winnerTeam == -1 ? 3 : 1),
                    ),
                    child: Column(children: [
                      Text(S.of('drawTeam$i'),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${teams[i]}',
                          style: TextStyle(
                              color: _teamColors[i],
                              fontSize: 28,
                              fontWeight: FontWeight.w900)),
                      if (winnerTeam == i)
                        Text('👑 ${S.of('drawTeamWins')}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
                if (i == 0) const SizedBox(width: Tokens.s8),
              ],
            ]),
            const SizedBox(height: 4),
            Text(S.of('drawTeamNote'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Tokens.textFaint, fontSize: 12)),
          ],
          const SizedBox(height: Tokens.s16),
          if (ranking.isNotEmpty && teams == null)
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
                      color: d.teamOf?[r.playerId] != null
                          ? _teamColors[d.teamOf![r.playerId]!]
                          : r.place == 1
                              ? Tokens.sun
                              : Tokens.glassBorder),
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
                  Text('${r.correct} 💡  ',
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
          Text(S.of('drawCorrectNote'),
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
