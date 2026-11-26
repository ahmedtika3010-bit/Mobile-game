import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sahra_client/sahra_client.dart';

import '../design/chibi_avatar.dart';
import '../design/sfx.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';

const _answerColors = [
  Tokens.mint,
  Tokens.sky,
  Tokens.sun,
  Tokens.orange,
  Tokens.coral,
];
const _categoryEmoji = {
  'places': '📍',
  'food': '🍽️',
  'jobs': '💼',
  'animals': '🐾',
  'objects': '🏠',
  'sports': '🏅',
};

String _catLabel(String c) =>
    '${_categoryEmoji[c] ?? '❓'} ${S.of('spycat_$c')}';

/// The live Spy match: role, question turns, discussion, vote and guess.
class SpyPane extends StatefulWidget {
  const SpyPane(
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
  State<SpyPane> createState() => _SpyPaneState();
}

class _SpyPaneState extends State<SpyPane> {
  /// Local server-time when the current stage started (for the timer ring).
  int _stageStart = 0;
  String _stageKey = '';
  String? _target;
  String? _voteFor;
  bool _sent = false;

  SpyView get g => widget.view.spy!;
  String get you => widget.view.you;

  PublicPlayer? _player(String? id) =>
      widget.view.players.where((p) => p.playerId == id).firstOrNull;

  @override
  void initState() {
    super.initState();
    _syncStage();
  }

  @override
  void didUpdateWidget(SpyPane old) {
    super.didUpdateWidget(old);
    _syncStage();
  }

  void _syncStage() {
    final key = '${g.stage}-${g.turn?.index}-${g.turn?.answer != null}';
    if (key == _stageKey) return;
    final previous = _stageKey;
    _stageKey = key;
    _stageStart = widget.session.serverNow;
    _sent = false;
    if (g.stage != 'vote') _voteFor = null;
    if (g.stage != 'ask') _target = null;
    if (previous.isEmpty) return;
    // Sounds for what just happened.
    switch (g.stage) {
      case 'ask':
        Sfx.play(g.turn?.asker == you ? 'go' : 'whoosh', volume: 0.5);
        if (g.turn?.asker == you) HapticFeedback.mediumImpact();
      case 'answer':
        if (g.turn?.answer != null || g.turn?.target == you) {
          Sfx.play('pop', volume: 0.6);
        }
        if (g.turn?.target == you && g.turn?.answer == null) {
          HapticFeedback.mediumImpact();
        }
      case 'discuss' || 'vote':
        Sfx.play('go', volume: 0.6);
      case 'guess':
        Sfx.play('wrong', volume: 0.5);
    }
  }

  Future<void> _earlyGuess() async {
    final options = g.guessOptions;
    if (options == null) return;
    final choice = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('🎯 ${S.of('knowTheWord')}',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: Tokens.s4),
            Text(S.of('guessWarning'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Tokens.coral, height: 1.4)),
            const SizedBox(height: Tokens.s16),
            _WordGrid(options: options, onPick: (i) => Navigator.pop(ctx, i)),
          ]),
        ),
      ),
    );
    if (choice != null && mounted) widget.session.spyGuess(choice);
  }

  @override
  Widget build(BuildContext context) {
    final stage = g.stage;
    final canEarlyGuess = g.isSpy &&
        g.guessOptions != null &&
        (stage == 'ask' || stage == 'answer' || stage == 'discuss');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, Tokens.s8),
      child: Column(children: [
        if (stage != 'roles')
          _RoleStrip(view: g, onGuess: canEarlyGuess ? _earlyGuess : null),
        const SizedBox(height: Tokens.s12),
        Expanded(
          child: AnimatedSwitcher(
            duration: Tokens.medium,
            child: KeyedSubtree(key: ValueKey(_stageKey), child: _stage()),
          ),
        ),
      ]),
    );
  }

  Widget _timer() => ServerTimerRing(
      startsAt: _stageStart,
      endsAt: g.stageEndsAt,
      size: 54,
      serverNow: () => widget.session.serverNow);

  Widget _stage() {
    switch (g.stage) {
      case 'roles':
        return _RoleReveal(view: g);
      case 'ask':
        return g.turn?.asker == you ? _askMine() : _askOther();
      case 'answer':
        return _answer();
      case 'discuss':
        return _discuss();
      case 'vote':
        return _vote();
      case 'guess':
        return _guess();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _turnHeader() {
    final t = g.turn!;
    return Row(children: [
      Pill(
          text: '${S.of('turnOf')} ${t.index + 1} ${S.of('of')} ${t.total}',
          color: Tokens.sky,
          emoji: '❓'),
      const Spacer(),
      _timer(),
    ]);
  }

  Widget _askMine() {
    final t = g.turn!;
    final others = widget.view.players.where((p) => p.playerId != you).toList();
    return ListView(children: [
      _turnHeader(),
      const SizedBox(height: Tokens.s8),
      PopIn(
        child: Text('🎤 ${S.of('yourTurnToAsk')}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(height: Tokens.s12),
      Text('1. ${S.of('pickTarget')}',
          style: const TextStyle(
              color: Tokens.textDim, fontWeight: FontWeight.w700)),
      const SizedBox(height: Tokens.s8),
      _AvatarPicker(
          players: others,
          selected: _target,
          onPick: (id) {
            Sfx.play('tap', volume: 0.4);
            setState(() => _target = id);
          }),
      const SizedBox(height: Tokens.s16),
      Text('2. ${S.of('pickQuestion')}',
          style: const TextStyle(
              color: Tokens.textDim, fontWeight: FontWeight.w700)),
      const SizedBox(height: Tokens.s8),
      for (final (i, q) in (t.questionOptions ?? const <String>[]).indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: Tokens.s8),
          child: Opacity(
            opacity: _target == null ? 0.55 : 1,
            child: _OptionTile(
              key: Key('spyQuestion$i'),
              text: q,
              color: Tokens.choiceColors[i % Tokens.choiceColors.length],
              onTap: _target == null || _sent
                  ? null
                  : () {
                      setState(() => _sent = true);
                      Sfx.play('pop', volume: 0.6);
                      widget.session.spyAsk(t.index, i, _target!);
                    },
            ),
          ),
        ),
    ]);
  }

  Widget _askOther() {
    final asker = _player(g.turn!.asker);
    return Column(children: [
      _turnHeader(),
      const Spacer(),
      Bob(child: ChibiAvatar(avatarId: asker?.avatarId ?? '', size: 110)),
      const SizedBox(height: Tokens.s12),
      Text('${asker?.displayName ?? ''} ${S.of('isChoosingQuestion')}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const Spacer(),
      if (g.history.isNotEmpty) _HistoryList(view: g, players: _player),
    ]);
  }

  Widget _answer() {
    final t = g.turn!;
    final asker = _player(t.asker);
    final target = _player(t.target);
    final mine = t.target == you && t.answer == null;
    return ListView(children: [
      _turnHeader(),
      const SizedBox(height: Tokens.s12),
      // Asker → target, and the question card.
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _MiniPlayer(player: asker),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: Tokens.s12),
          child: Icon(Icons.arrow_forward_rounded,
              color: Tokens.textDim, size: 30), // mirrors in RTL: points to the target
        ),
        _MiniPlayer(player: target, highlight: true),
      ]),
      const SizedBox(height: Tokens.s12),
      PopIn(
        from: 0.8,
        child: Container(
          padding: const EdgeInsets.all(Tokens.s20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.all(Tokens.r24),
            boxShadow: [
              BoxShadow(
                  color: Tokens.shade(Tokens.grape, 0.12),
                  offset: const Offset(0, 6)),
            ],
          ),
          child: Text(t.question ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Tokens.ink,
                  fontSize: 22,
                  height: 1.4,
                  fontWeight: FontWeight.w800)),
        ),
      ),
      const SizedBox(height: Tokens.s16),
      if (t.answer != null || (t.target != you && _answerShown))
        Center(child: PopIn(from: 0.3, child: _AnswerChip(answer: t.answer)))
      else if (mine) ...[
        Text(S.of('yourTurnToAnswer'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Tokens.textDim, fontWeight: FontWeight.w700)),
        const SizedBox(height: Tokens.s12),
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s8),
            child: _OptionTile(
              key: Key('spyAnswer$i'),
              text: S.of('spyAnswer_$i'),
              color: _answerColors[i],
              center: true,
              onTap: _sent
                  ? null
                  : () {
                      setState(() => _sent = true);
                      widget.session.spyAnswer(t.index, i);
                    },
            ),
          ),
      ] else
        Center(
          child: Bob(
            child: Text(
                '⏳ ${S.of('waitingAnswerFrom')} ${target?.displayName ?? ''}',
                style: const TextStyle(
                    color: Tokens.textDim,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
          ),
        ),
    ]);
  }

  /// The turn closed without an answer (timed out).
  bool get _answerShown =>
      g.history.length > (g.turn?.index ?? 0) &&
      g.history.length == (g.turn?.index ?? 0) + 1;

  Widget _discuss() {
    final counts = <String, int>{};
    for (final t in g.suspicions.values) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    final mySuspect = g.suspicions[you];
    final n = widget.view.players.length;
    return Column(children: [
      Row(children: [
        Expanded(
          child: Text('💬 ${S.of('discussTitle')}',
              style: Theme.of(context).textTheme.titleLarge),
        ),
        _timer(),
      ]),
      Text(S.of('discussHint'),
          style: const TextStyle(color: Tokens.textDim, height: 1.4)),
      const SizedBox(height: Tokens.s12),
      _PlayerGrid(
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
      Expanded(child: _HistoryList(view: g, players: _player, expanded: true)),
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
    final n = widget.view.players.length;
    final voted = g.yourVote != null;
    return Column(children: [
      Row(children: [
        Expanded(
          child: Text('🗳️ ${S.of('voteTitle')}',
              style: Theme.of(context).textTheme.titleLarge),
        ),
        _timer(),
      ]),
      Text(S.of('voteHint'),
          style: const TextStyle(color: Tokens.textDim, height: 1.4)),
      const SizedBox(height: Tokens.s16),
      Expanded(
        child: SingleChildScrollView(
          child: _PlayerGrid(
            players: widget.view.players,
            you: you,
            bubbles: widget.bubbles,
            selected: g.yourVote ?? _voteFor,
            disabledId: you,
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

  Widget _guess() {
    final guesser = _player(g.guesser);
    final mine = g.guesser == you && g.guessOptions != null;
    return ListView(children: [
      Row(children: [const Spacer(), _timer()]),
      Center(
          child: Bob(
              child: ChibiAvatar(avatarId: guesser?.avatarId ?? '', size: 96))),
      const SizedBox(height: Tokens.s12),
      Text(
          mine
              ? S.of('youWereCaught')
              : '${guesser?.displayName ?? ''} ${S.of('isGuessing')}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      const SizedBox(height: Tokens.s16),
      if (mine)
        _WordGrid(
            options: g.guessOptions!,
            onPick: _sent
                ? null
                : (i) {
                    setState(() => _sent = true);
                    widget.session.spyGuess(i);
                  }),
    ]);
  }
}

/* ------------------------------- pieces -------------------------------- */

class _RoleReveal extends StatelessWidget {
  const _RoleReveal({required this.view});
  final SpyView view;
  @override
  Widget build(BuildContext context) {
    final spy = view.isSpy;
    final color = spy ? Tokens.coral : Tokens.mint;
    return Column(children: [
      const Spacer(),
      PopIn(
        from: 0.4,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Tokens.s24),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Tokens.r32),
            gradient: Tokens.gradient(color, Tokens.shade(color, 0.25)),
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 40)
            ],
          ),
          child: Column(children: [
            Bob(
                child: Text(spy ? '🕵️' : '🤫',
                    style: const TextStyle(fontSize: 80))),
            const SizedBox(height: Tokens.s8),
            Text(S.of(spy ? 'youAreSpy' : 'youAreCitizen'),
                style: const TextStyle(
                    color: Tokens.ink,
                    fontSize: 28,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: Tokens.s12),
            if (!spy && view.word != null) ...[
              Text(S.of('theWordIs'),
                  style: const TextStyle(
                      color: Tokens.inkSoft, fontWeight: FontWeight.w700)),
              Container(
                margin: const EdgeInsets.only(top: Tokens.s8),
                padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.s24, vertical: Tokens.s12),
                decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Tokens.r20)),
                child: Text(view.word!,
                    key: const Key('spyWord'),
                    style: const TextStyle(
                        color: Tokens.ink,
                        fontSize: 32,
                        fontWeight: FontWeight.w800)),
              ),
            ],
            const SizedBox(height: Tokens.s12),
            Text('${S.of('category')}: ${_catLabel(view.category)}',
                style: const TextStyle(
                    color: Tokens.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: Tokens.s12),
            Text(S.of(spy ? 'youAreSpyHint' : 'citizenHint'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Tokens.inkSoft, height: 1.5)),
          ]),
        ),
      ),
      const SizedBox(height: Tokens.s16),
      Text(S.of('dontShowScreen'),
          style: const TextStyle(color: Tokens.textDim)),
      const Spacer(),
    ]);
  }
}

/// Compact, always-visible reminder of your role (tap the eye to hide it).
class _RoleStrip extends StatefulWidget {
  const _RoleStrip({required this.view, required this.onGuess});
  final SpyView view;
  final VoidCallback? onGuess;
  @override
  State<_RoleStrip> createState() => _RoleStripState();
}

class _RoleStripState extends State<_RoleStrip> {
  bool _hidden = false;
  @override
  Widget build(BuildContext context) {
    final v = widget.view;
    final spy = v.isSpy;
    final text = _hidden
        ? '••••••'
        : spy
            ? '🕵️ ${S.of('youAreSpy')}'
            : '🤫 ${v.word ?? ''}';
    return GlassCard(
      radius: Tokens.r20,
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s12, vertical: 8),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: spy ? Tokens.coral : Tokens.sun,
                    fontSize: 19,
                    fontWeight: FontWeight.w800)),
            Text('${S.of('category')}: ${_catLabel(v.category)}',
                style: const TextStyle(color: Tokens.textDim, fontSize: 13)),
          ]),
        ),
        if (widget.onGuess != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: Tokens.s8),
            child: GameButton(
                key: const Key('spyGuessEarly'),
                label: S.of('knowTheWord'),
                color: Tokens.coral,
                size: GameButtonSize.medium,
                expand: false,
                onPressed: widget.onGuess),
          ),
        RoundIconButton(
            icon: _hidden
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            onPressed: () => setState(() => _hidden = !_hidden)),
      ]),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.player, this.highlight = false});
  final PublicPlayer? player;
  final bool highlight;
  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: highlight ? Tokens.sun : Colors.transparent,
                  width: 3)),
          child: ChibiAvatar(avatarId: player?.avatarId ?? '', size: 58),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 90,
          child: Text(player?.displayName ?? '—',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]);
}

class _AnswerChip extends StatelessWidget {
  const _AnswerChip({required this.answer});
  final int? answer;
  @override
  Widget build(BuildContext context) {
    final color = answer == null ? Tokens.textFaint : _answerColors[answer!];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.all(Radius.circular(99)),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 20)
        ],
      ),
      child: Text(
          answer == null
              ? '🤐 ${S.of('noReply')}'
              : '💬 ${S.of('spyAnswer_$answer')}',
          style: const TextStyle(
              color: Tokens.ink, fontSize: 24, fontWeight: FontWeight.w800)),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile(
      {super.key,
      required this.text,
      required this.color,
      required this.onTap,
      this.center = false});
  final String text;
  final Color color;
  final VoidCallback? onTap;
  final bool center;
  @override
  Widget build(BuildContext context) {
    final fg = Tokens.onColor(color);
    final body = Container(
      padding: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
          color: Tokens.shade(color, 0.18),
          borderRadius: const BorderRadius.all(Tokens.r20)),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Tokens.s16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Tokens.r20),
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Tokens.tint(color, 0.06), color]),
        ),
        child: Text(text,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: TextStyle(
                color: fg,
                fontSize: 18,
                height: 1.3,
                fontWeight: FontWeight.w800)),
      ),
    );
    return Semantics(
      button: true,
      label: text,
      onTap: onTap,
      excludeSemantics: true,
      child: onTap == null ? body : Pressable(onTap: onTap, child: body),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker(
      {required this.players, required this.selected, required this.onPick});
  final List<PublicPlayer> players;
  final String? selected;
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 104,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final p in players)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Tokens.s12),
              child: Pressable(
                onTap: () => onPick(p.playerId),
                semanticLabel: p.displayName,
                child: AnimatedScale(
                  duration: Tokens.fast,
                  scale: selected == p.playerId ? 1.08 : 1,
                  child: Opacity(
                    opacity:
                        selected == null || selected == p.playerId ? 1 : 0.5,
                    child: _MiniPlayer(
                        player: p, highlight: selected == p.playerId),
                  ),
                ),
              ),
            ),
        ]),
      );
}

class _PlayerGrid extends StatelessWidget {
  const _PlayerGrid(
      {required this.players,
      required this.you,
      required this.bubbles,
      required this.selected,
      required this.onTap,
      this.badge,
      this.disabledId});
  final List<PublicPlayer> players;
  final String you;
  final Map<String, String> bubbles;
  final String? selected;
  final void Function(PublicPlayer)? onTap;
  final String? Function(String id)? badge;
  final String? disabledId;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        spacing: Tokens.s8,
        runSpacing: Tokens.s12,
        children: [
          for (final p in players)
            SizedBox(
              width: 80,
              child: Pressable(
                onTap: onTap == null || p.playerId == disabledId
                    ? null
                    : () => onTap!(p),
                semanticLabel: p.displayName,
                child: Opacity(
                  opacity: p.playerId == disabledId ? 0.5 : 1,
                  child: Column(children: [
                    Stack(clipBehavior: Clip.none, children: [
                      AnimatedContainer(
                        duration: Tokens.fast,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected == p.playerId
                              ? Tokens.coral.withValues(alpha: 0.35)
                              : Colors.transparent,
                          border: Border.all(
                              color: selected == p.playerId
                                  ? Tokens.coral
                                  : Colors.transparent,
                              width: 3),
                        ),
                        child: ChibiAvatar(
                            avatarId: p.avatarId,
                            size: 56,
                            dimmed: !p.connected),
                      ),
                      if (badge?.call(p.playerId) case final b?)
                        PositionedDirectional(
                          top: -6,
                          end: -8,
                          child: PopIn(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: const BoxDecoration(
                                  color: Colors.white,
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(99))),
                              child: Text(b,
                                  style: const TextStyle(
                                      color: Tokens.ink,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ),
                      if (bubbles[p.playerId] case final phrase?)
                        PositionedDirectional(
                          bottom: -4,
                          start: -6,
                          child: PopIn(
                              child: Text(S.of('phrase_$phrase'),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      backgroundColor: Colors.white,
                                      color: Tokens.ink,
                                      fontWeight: FontWeight.w800))),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                        p.playerId == you
                            ? '${p.displayName} (${S.of('you')})'
                            : p.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color:
                                p.playerId == you ? Tokens.sun : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
        ],
      );
}

class _HistoryList extends StatelessWidget {
  const _HistoryList(
      {required this.view, required this.players, this.expanded = false});
  final SpyView view;
  final PublicPlayer? Function(String?) players;
  final bool expanded;
  @override
  Widget build(BuildContext context) {
    final items = view.history.reversed.toList();
    final list = ListView.separated(
      shrinkWrap: !expanded,
      physics: expanded ? null : const NeverScrollableScrollPhysics(),
      itemCount: expanded ? items.length : items.length.clamp(0, 2),
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final h = items[i];
        return GlassCard(
          radius: Tokens.r16,
          padding: const EdgeInsets.all(Tokens.s8),
          child: Row(children: [
            ChibiAvatar(avatarId: players(h.asker)?.avatarId ?? '', size: 30),
            const Icon(Icons.arrow_forward_rounded,
                size: 16, color: Tokens.textFaint),
            ChibiAvatar(avatarId: players(h.target)?.avatarId ?? '', size: 30),
            const SizedBox(width: Tokens.s8),
            Expanded(
              child: Text(h.question,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: Tokens.s8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: h.answer == null
                      ? Tokens.glass
                      : _answerColors[h.answer!],
                  borderRadius: const BorderRadius.all(Radius.circular(99))),
              child: Text(
                  h.answer == null ? '🤐' : S.of('spyAnswer_${h.answer}'),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: h.answer == null ? Colors.white : Tokens.ink)),
            ),
          ]),
        );
      },
    );
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Text('📝 ${S.of('questionsSoFar')} (${items.length})',
              style: const TextStyle(
                  color: Tokens.textDim, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (expanded) Expanded(child: list) else list,
        ]);
  }
}

class _WordGrid extends StatelessWidget {
  const _WordGrid({required this.options, required this.onPick});
  final List<String> options;
  final ValueChanged<int>? onPick;
  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        spacing: Tokens.s8,
        runSpacing: Tokens.s8,
        children: [
          for (final (i, w) in options.indexed)
            Semantics(
              button: true,
              label: w,
              onTap: onPick == null ? null : () => onPick!(i),
              excludeSemantics: true,
              child: Pressable(
                onTap: onPick == null ? null : () => onPick!(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.s16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Tokens.choiceColors[i % Tokens.choiceColors.length],
                    borderRadius: const BorderRadius.all(Tokens.r16),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: Text(w,
                      style: TextStyle(
                          color: Tokens.onColor(Tokens
                              .choiceColors[i % Tokens.choiceColors.length]),
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ),
        ],
      );
}

/* -------------------------------- results ------------------------------- */

/// End of a Spy match: who won, why, the word, the spies and the votes.
class SpyResults extends StatelessWidget {
  const SpyResults(
      {super.key,
      required this.view,
      required this.rewards,
      required this.actions});
  final RoomView view;
  final Widget rewards;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final f = view.spy!.final_!;
    final me = view.you;
    final iWasSpy = f.spies.contains(me);
    final won = (f.winner == 'spies') == iWasSpy;
    final byId = {for (final p in view.players) p.playerId: p};
    final title = f.winner == 'citizens'
        ? S.of('citizensWon')
        : S.of(f.spies.length > 1 ? 'spiesWonPlural' : 'spiesWon');
    final voteRows = f.voteCounts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Stack(children: [
      ListView(
        padding:
            const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s24),
        children: [
          FadeSlideIn(
            child: Column(children: [
              Text(title,
                  key: const Key('spyResultTitle'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: Tokens.s4),
              Text(S.of('reason_${f.reason}'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Tokens.textDim, fontSize: 16)),
              const SizedBox(height: Tokens.s8),
              Pill(
                  text: S.of(won ? 'youWonRound' : 'youLostRound'),
                  emoji: won ? '🏆' : '💪',
                  color: won ? Tokens.success : Tokens.orange,
                  solid: true),
            ]),
          ),
          const SizedBox(height: Tokens.s20),
          FadeSlideIn(
            delay: const Duration(milliseconds: 150),
            child: GlassCard(
              child: Column(children: [
                Text(S.of('wasTheWord'),
                    style: const TextStyle(color: Tokens.textDim)),
                const SizedBox(height: 6),
                PopIn(
                  child: Text('🔑 ${f.word}',
                      style: const TextStyle(
                          color: Tokens.sun,
                          fontSize: 32,
                          fontWeight: FontWeight.w800)),
                ),
                if (f.guessedWord != null) ...[
                  const SizedBox(height: 6),
                  Text('${S.of('guessedWord')}: ${f.guessedWord}',
                      style: TextStyle(
                          color: f.guessedWord == f.word
                              ? Tokens.success
                              : Tokens.coral,
                          fontWeight: FontWeight.w800)),
                ],
              ]),
            ),
          ),
          const SizedBox(height: Tokens.s16),
          FadeSlideIn(
            delay: const Duration(milliseconds: 300),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: Tokens.s20,
              children: [
                for (final id in f.spies)
                  Column(children: [
                    Stack(clipBehavior: Clip.none, children: [
                      Bob(
                          child: ChibiFullBody(
                              avatarId: byId[id]?.avatarId ?? '', height: 150)),
                      const PositionedDirectional(
                          top: 0,
                          end: 0,
                          child: Text('🕵️', style: TextStyle(fontSize: 34))),
                    ]),
                    Text(byId[id]?.displayName ?? '—',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(S.of('wasTheSpy'),
                        style: const TextStyle(color: Tokens.coral)),
                  ]),
              ],
            ),
          ),
          if (voteRows.isNotEmpty) ...[
            const SizedBox(height: Tokens.s16),
            Text('🗳️ ${S.of('votesReceived')}',
                style: Theme.of(context).textTheme.titleMedium),
            for (final e in voteRows)
              Container(
                margin: const EdgeInsets.only(top: Tokens.s8),
                padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.s12, vertical: 6),
                decoration: BoxDecoration(
                  color: f.spies.contains(e.key)
                      ? Tokens.coral.withValues(alpha: 0.2)
                      : Tokens.glass,
                  borderRadius: const BorderRadius.all(Tokens.r16),
                ),
                child: Row(children: [
                  ChibiAvatar(avatarId: byId[e.key]?.avatarId ?? '', size: 34),
                  const SizedBox(width: Tokens.s8),
                  Expanded(
                      child: Text(byId[e.key]?.displayName ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.w800))),
                  Text('${'🗳️' * e.value.clamp(0, 8)}  ${e.value}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
          ],
          const SizedBox(height: Tokens.s20),
          rewards,
          const SizedBox(height: Tokens.s24),
          ...actions,
        ],
      ),
      if (won) const Positioned.fill(child: Confetti()),
    ]);
  }
}
