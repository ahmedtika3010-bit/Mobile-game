import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sahra_client/sahra_client.dart';

import '../design/chibi_avatar.dart';
import '../design/sfx.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';

const _diffColor = {
  'easy': Tokens.mint,
  'medium': Tokens.sun,
  'hard': Tokens.coral
};

/// Same as ACT_LIMITS.moveGapMs in packages/shared/src/acting.ts.
const _moveGapMs = 900;
const _movesPerTurn = 40;

ChibiExpression _face(String f) => switch (f) {
      'neutral' => ChibiExpression.neutral,
      'sad' => ChibiExpression.sad,
      'surprised' => ChibiExpression.surprised,
      _ => ChibiExpression.happy,
    };

/// The live Acting and Guessing match: the actor plays approved avatar moves
/// and reveals the word's hint cards, everyone else types private guesses.
/// No camera, no free text and no voice from the actor.
class ActingPane extends StatefulWidget {
  const ActingPane(
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
  State<ActingPane> createState() => _ActingPaneState();
}

class _ActingPaneState extends State<ActingPane> {
  final _guess = TextEditingController();
  final _guessFocus = FocusNode();
  Timer? _clock;

  String _key = '';
  int _guessedBefore = 0;
  int _beatsBefore = 0;
  int? _actSeenLocal;
  int _lastMoveLocal = 0;
  String _tab = 'suggested';

  ActView get g => widget.view.acting!;
  ActTurn? get t => g.turn;
  String get me => widget.view.you;
  bool get isActor => t?.actor == me;
  int get now => widget.session.serverNow;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    _sync();
  }

  @override
  void didUpdateWidget(ActingPane old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
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
        _guessedBefore = 0;
        _beatsBefore = 0;
        _actSeenLocal = null;
        _lastMoveLocal = 0;
        _tab = 'suggested';
        _guess.clear();
        if (turn.actor == me) Sfx.play('whoosh', volume: 0.6);
      }
      if (g.stage == 'act') {
        _actSeenLocal ??= DateTime.now().millisecondsSinceEpoch;
        if (!isActor) Future.microtask(_guessFocus.requestFocus);
      }
      if (g.stage == 'reveal') {
        final pts = g.reveal?.points[me] ?? 0;
        pts > 0 ? Sfx.correct() : Sfx.play('pop', volume: 0.5);
      }
    }
    if (g.stage == 'act' && turn.beats.length > _beatsBefore) {
      if (!isActor) Sfx.play('pop', volume: 0.35);
      _beatsBefore = turn.beats.length;
    }
    if (g.stage == 'act' && turn.guessed.length > _guessedBefore) {
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

  /* ------------------------------ actions ------------------------------ */

  bool get _canAct => isActor && g.stage == 'act' && now < t!.deadline;

  void _play(ActMove m) {
    if (!_canAct) return;
    final local = DateTime.now().millisecondsSinceEpoch;
    // The server refuses moves closer than the gap; skip them here too.
    if (local - _lastMoveLocal < _moveGapMs) return;
    _lastMoveLocal = local;
    widget.session.actMove(t!.turn, m.id);
    HapticFeedback.selectionClick();
  }

  void _showCard(int i) {
    if (!_canAct) return;
    final local = DateTime.now().millisecondsSinceEpoch;
    if (local - _lastMoveLocal < _moveGapMs) return;
    _lastMoveLocal = local;
    widget.session.actCard(t!.turn, i);
    HapticFeedback.mediumImpact();
  }

  void _submitGuess() {
    final text = _guess.text.trim();
    final turn = t;
    if (text.isEmpty || turn == null || g.stage != 'act') return;
    final seen = _actSeenLocal;
    widget.session.actGuess(turn.turn, text,
        elapsedMs:
            seen == null ? null : DateTime.now().millisecondsSinceEpoch - seen);
    _guess.clear();
    HapticFeedback.selectionClick();
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
      'act' => (start: turn.startedAt, end: turn.deadline),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, Tokens.s8),
      child: Column(children: [
        Row(children: [
          Pill(
              text:
                  '${S.of('game_acting')} · ${turn.turn} ${S.of('of')} ${turn.total}',
              color: Tokens.grape,
              emoji: '🎭'),
          const SizedBox(width: 6),
          if (turn.category != null)
            Pill(text: S.of('act_cat_${turn.category}'), color: Tokens.sun),
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
        Expanded(child: _middle(turn)),
        const SizedBox(height: Tokens.s8),
        _controls(turn),
        const SizedBox(height: Tokens.s8),
        _footer(turn),
      ]),
    );
  }

  Widget _header(ActTurn turn) {
    final actor = _player(turn.actor);
    switch (g.stage) {
      case 'choose':
        return Text(
            isActor
                ? S.of('actChoose')
                : '${actor?.displayName ?? ''} ${S.of('actChoosing')}',
            key: const Key('actHeader'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800));
      case 'act':
        if (isActor) {
          return Column(children: [
            Text('${S.of('actYourWord')} ${turn.word ?? ''}',
                key: const Key('actHeader'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24,
                    color: Tokens.sun,
                    fontWeight: FontWeight.w900)),
            Text(S.of('actNoText'),
                style: const TextStyle(color: Tokens.textDim, fontSize: 13)),
          ]);
        }
        return _Shape(
            key: const Key('actHeader'),
            shape: turn.shape ?? const [],
            word: turn.youGuessed ? turn.word : null);
      default:
        final r = g.reveal;
        final ended = r?.ended ?? 'time';
        return Column(children: [
          Text('${S.of('drawWasWord')}: ${r?.word ?? ''}',
              key: const Key('actHeader'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22,
                  color: Tokens.sun,
                  fontWeight: FontWeight.w900)),
          Text(S.of('actEnded_$ended'),
              style: const TextStyle(color: Tokens.textDim, fontSize: 14)),
        ]);
    }
  }

  Widget _middle(ActTurn turn) {
    final actor = _player(turn.actor);
    if (g.stage == 'choose') {
      if (isActor && turn.choices != null) {
        return Center(child: SingleChildScrollView(child: _choices(turn)));
      }
      return Center(
        child: Bob(
            child: ChibiFullBody(
                avatarId: actor?.avatarId ?? '',
                height: 190,
                expression: ChibiExpression.neutral)),
      );
    }
    final moves = turn.beats.where((b) => b.kind == 'move').toList();
    final cards = turn.beats.where((b) => b.kind == 'card').toList();
    final last = moves.isEmpty ? null : actMoveById[moves.last.move];
    final reveal = g.stage == 'reveal';
    final everyone = reveal && (g.reveal?.guessed.isNotEmpty ?? false);
    return Column(children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, c) => Center(
              child: _ActorStage(
            key: const Key('actStage'),
            avatarId: actor?.avatarId ?? '',
            move: reveal ? null : last,
            beat: moves.length,
            height: math.min(c.maxHeight, 300),
            mood: reveal
                ? (everyone ? ChibiExpression.happy : ChibiExpression.sad)
                : null,
            caption: !reveal && moves.isEmpty ? S.of('actWaiting') : null,
          )),
        ),
      ),
      if (moves.isNotEmpty) ...[
        const SizedBox(height: 6),
        SizedBox(
          height: 34,
          child: ListView.separated(
            key: const Key('actTimeline'),
            scrollDirection: Axis.horizontal,
            reverse: true,
            itemCount: moves.length,
            separatorBuilder: (_, __) => const SizedBox(width: 4),
            itemBuilder: (context, i) {
              final b = moves[moves.length - 1 - i];
              final m = actMoveById[b.move];
              final latest = i == 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: latest ? Tokens.grape : Tokens.glass,
                  borderRadius: const BorderRadius.all(Radius.circular(99)),
                  border: Border.all(
                      color: latest ? Tokens.grape : Tokens.glassBorder),
                ),
                child: Text('${m?.emoji ?? '❔'} ${m?.label ?? ''}',
                    style: TextStyle(
                        color: latest ? Colors.white : Tokens.textDim,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
              );
            },
          ),
        ),
      ],
      if (cards.isNotEmpty) ...[
        const SizedBox(height: 6),
        Wrap(
          key: const Key('actShownCards'),
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (i, b) in cards.indexed)
              PopIn(
                key: ValueKey('card${b.at}'),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.all(Tokens.r12),
                    border: Border.all(
                        color: i == cards.length - 1
                            ? Tokens.sun
                            : const Color(0x33000000),
                        width: 2),
                  ),
                  child: Text('🃏 ${b.text ?? ''}',
                      style: const TextStyle(
                          color: Tokens.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ],
    ]);
  }

  Widget _choices(ActTurn turn) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, c) in turn.choices!.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s12),
              child: FadeSlideIn(
                delay: Duration(milliseconds: 80 * i),
                child: Pressable(
                  key: Key('actChoice$i'),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.session.actChoose(turn.turn, i);
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

  Widget _controls(ActTurn turn) {
    if (g.stage != 'act') return const SizedBox.shrink();
    if (isActor) return _palette(turn);
    if (turn.youGuessed) {
      return Text(S.of('drawGotIt'),
          key: const Key('actGotIt'),
          style: const TextStyle(
              fontSize: 20,
              color: Tokens.success,
              fontWeight: FontWeight.w900));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          child: TextField(
            key: const Key('actGuess'),
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
            key: const Key('actSend'),
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

  /// The actor's move library: suggested moves first, then every move by
  /// group, then the word's hint cards. Every move is free.
  Widget _palette(ActTurn turn) {
    final suggested = turn.suggested ?? const <String>[];
    final cards = turn.cards ?? const <ActCard>[];
    final played = turn.beats.where((b) => b.kind == 'move').length;
    final left = _movesPerTurn - turn.beats.length;
    const tabs = ['suggested', 'action', 'feeling', 'gesture', 'cards'];
    String tabLabel(String id) => switch (id) {
          'suggested' => '⭐ ${S.of('actTabSuggested')}',
          'cards' =>
            '🃏 ${S.of('actTabCards')} ${cards.where((c) => c.shown).length}/${cards.length}',
          _ => S.of('actTab_$id'),
        };
    final Widget body;
    if (_tab == 'cards') {
      body = ListView(
        key: const Key('actCards'),
        padding: EdgeInsets.zero,
        children: [
          for (final (i, c) in cards.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 6, 6),
                decoration: BoxDecoration(
                  color: c.shown ? Tokens.glass : Colors.white,
                  borderRadius: const BorderRadius.all(Tokens.r12),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text('🃏 ${c.text}',
                        style: TextStyle(
                            color: c.shown ? Tokens.textDim : Tokens.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 6),
                  c.shown
                      ? Pill(text: S.of('actCardShown'), color: Tokens.mint)
                      : GameButton(
                          key: Key('actCard$i'),
                          label: S.of('actCardShow'),
                          expand: false,
                          size: GameButtonSize.medium,
                          color: Tokens.sun,
                          onPressed: () => _showCard(i)),
                ]),
              ),
            ),
        ],
      );
    } else {
      final list = _tab == 'suggested'
          ? [for (final id in suggested) actMoveById[id]].nonNulls.toList()
          : actMoves.where((m) => m.group == _tab).toList();
      body = GridView.builder(
        key: Key('actMoves_$_tab'),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 76,
            mainAxisExtent: 66,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final m = list[i];
          final star = suggested.contains(m.id);
          return Pressable(
            key: Key('actMove_${m.id}'),
            onTap: () => _play(m),
            semanticLabel: m.label,
            child: Container(
              decoration: BoxDecoration(
                color: star ? Tokens.sun.withValues(alpha: 0.22) : Tokens.glass,
                borderRadius: const BorderRadius.all(Tokens.r12),
                border: Border.all(
                    color: star ? Tokens.sun : Tokens.glassBorder,
                    width: star ? 2 : 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(m.emoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(height: 2),
                    Text(m.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w800)),
                  ]),
            ),
          );
        },
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final id in tabs)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: Pressable(
                  key: Key('actTab_$id'),
                  onTap: () => setState(() => _tab = id),
                  semanticLabel: tabLabel(id),
                  child: AnimatedContainer(
                    duration: Tokens.fast,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _tab == id ? Tokens.sun : Tokens.glass,
                      borderRadius: const BorderRadius.all(Radius.circular(99)),
                    ),
                    child: Text(tabLabel(id),
                        style: TextStyle(
                            color: _tab == id ? Tokens.ink : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      SizedBox(height: 144, child: body),
      const SizedBox(height: 4),
      Text(
          _tab == 'suggested'
              ? '${S.of('actSuggestedNote')} · $played 🎬 · ${S.of('actMovesLeft')} $left'
              : '$played 🎬 · ${S.of('actMovesLeft')} $left',
          style: const TextStyle(color: Tokens.textFaint, fontSize: 12)),
    ]);
  }

  Widget _footer(ActTurn turn) {
    final reveal = g.reveal;
    return Wrap(
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
                  color: p.playerId == turn.actor
                      ? Tokens.grape
                      : Tokens.glassBorder,
                  width: p.playerId == turn.actor ? 2 : 1),
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
              if (p.playerId == turn.actor)
                const Text('🎭 ', style: TextStyle(fontSize: 14)),
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
    );
  }
}

/// The actor's avatar on stage, animated by the latest move: the body moves
/// with code transforms over the character art, the face uses the art's
/// four expressions, and the move's prop floats beside it with its label.
class _ActorStage extends StatefulWidget {
  const _ActorStage(
      {super.key,
      required this.avatarId,
      required this.move,
      required this.beat,
      required this.height,
      this.mood,
      this.caption});
  final String avatarId;
  final ActMove? move;

  /// Changes with every new move, so the same move played twice restarts.
  final int beat;
  final double height;
  final ChibiExpression? mood;
  final String? caption;

  @override
  State<_ActorStage> createState() => _ActorStageState();
}

class _ActorStageState extends State<_ActorStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void didUpdateWidget(_ActorStage old) {
    super.didUpdateWidget(old);
    if (old.beat != widget.beat) {
      _c
        ..reset()
        ..repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// The body's transform for a motion at time t (0..1, looping).
  Matrix4 _pose(String motion, double t, double h) {
    final s = math.sin(2 * math.pi * t);
    final s2 = math.sin(4 * math.pi * t);
    final m = Matrix4.identity();
    switch (motion) {
      case 'bob':
        m.translateByDouble(0, -h * 0.03 * s.abs(), 0, 1);
      case 'jump':
        m.translateByDouble(0, -h * 0.14 * math.sin(math.pi * t).abs(), 0, 1);
      case 'shake':
        m.translateByDouble(h * 0.025 * math.sin(10 * math.pi * t), 0, 0, 1);
      case 'spin':
        m.rotateY(2 * math.pi * t);
      case 'sway':
        m.rotateZ(0.12 * s);
      case 'float':
        m.translateByDouble(0, -h * 0.08 - h * 0.04 * s, 0, 1);
      case 'walk':
        m.translateByDouble(h * 0.08 * s, -h * 0.015 * s2.abs(), 0, 1);
      case 'run':
        m.translateByDouble(h * 0.14 * s, -h * 0.03 * s2.abs(), 0, 1);
        m.rotateZ(-0.08);
      case 'nod':
        m.translateByDouble(0, h * 0.015 * s2, 0, 1);
        m.rotateZ(0.04 * s2);
      case 'stir':
        m.rotateZ(0.09 * s2);
      case 'still':
        m.scaleByDouble(1, 1 + 0.012 * s, 1, 1);
      case 'grow':
        final k = 1 + 0.18 * math.sin(math.pi * t);
        m.scaleByDouble(k, k, 1, 1);
      case 'shrink':
        final k = 1 - 0.3 * math.sin(math.pi * t);
        m.scaleByDouble(k, k, 1, 1);
      case 'push':
        m.translateByDouble(-h * 0.07 * math.max(0, s), 0, 0, 1);
      case 'flap':
        m.translateByDouble(0, -h * 0.04 * s2.abs(), 0, 1);
        m.scaleByDouble(1 + 0.06 * math.sin(8 * math.pi * t), 1, 1, 1);
      case 'tilt':
        m.rotateZ(0.2 * math.sin(math.pi * t));
      case 'low':
        m.translateByDouble(0, h * 0.06, 0, 1);
        m.scaleByDouble(1, 0.86, 1, 1);
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final move = widget.move;
    final h = widget.height;
    final face = widget.mood ??
        (move == null ? ChibiExpression.neutral : _face(move.face));
    final body = ChibiFullBody(
        avatarId: widget.avatarId, height: h * 0.76, expression: face);
    return SizedBox(
      width: double.infinity,
      height: h,
      child: Stack(alignment: Alignment.topCenter, children: [
        // A soft spotlight on the floor.
        Positioned(
          bottom: 0,
          child: Container(
            width: h * 0.7,
            height: h * 0.12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(Radius.elliptical(h, h * 0.2)),
              gradient: const RadialGradient(
                  colors: [Color(0x55FFFFFF), Color(0x00FFFFFF)]),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: h * 0.04,
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) => Transform(
                    alignment: Alignment.bottomCenter,
                    transform: move == null
                        ? _pose(
                            widget.mood == null ? 'bob' : 'still', _c.value, h)
                        : _pose(move.motion, _c.value, h),
                    child: child,
                  ),
                  child: body,
                ),
                if (move != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: h * 0.3),
                    child: PopIn(
                      key: ValueKey('prop${widget.beat}'),
                      child: Bob(
                        amplitude: 5,
                        period: const Duration(milliseconds: 1600),
                        child: Text(move.emoji,
                            style: TextStyle(fontSize: h * 0.16)),
                      ),
                    ),
                  ),
              ]),
        ),
        if (move != null)
          PopIn(
            key: ValueKey('label${widget.beat}'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(99)),
                boxShadow: [
                  BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 8,
                      offset: Offset(0, 3))
                ],
              ),
              child: Text(move.label,
                  key: const Key('actMoveLabel'),
                  style: const TextStyle(
                      color: Tokens.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900)),
            ),
          ),
        if (widget.caption != null)
          Text(widget.caption!,
              style: const TextStyle(
                  color: Tokens.textDim,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
      ]),
    );
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

/// End of an Acting and Guessing match: the ranking.
class ActingResults extends StatelessWidget {
  const ActingResults(
      {super.key,
      required this.view,
      required this.rewards,
      required this.actions});
  final RoomView view;
  final Widget rewards;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ranking = view.acting!.ranking!;
    final me = view.you;
    final byId = {for (final p in view.players) p.playerId: p};
    final won = ranking.where((r) => r.playerId == me).firstOrNull?.place == 1;
    return Stack(children: [
      ListView(
        padding:
            const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s24),
        children: [
          FadeSlideIn(
            child: Text('🎭 ${S.of(won ? 'youWon' : 'finalScores')}',
                key: const Key('actResultTitle'),
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
          Text(S.of('actCorrectNote'),
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
