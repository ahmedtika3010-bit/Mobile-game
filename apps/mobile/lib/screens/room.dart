import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sahra_client/sahra_client.dart';

import '../app_state.dart';
import '../design/chibi_avatar.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';

const _phrases = ['gg', 'nice', 'wow', 'good_luck', 'thanks', 'oops', 'hurry'];
const _choiceLabels = ['أ', 'ب', 'ج', 'د', 'هـ', 'و'];

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.session});
  final GameSession session;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  GameSession get s => widget.session;
  final _subs = <StreamSubscription<dynamic>>[];
  RoomView? _view;
  MatchSummary? _summary;
  ConnectionStatus _status = ConnectionStatus.connected;
  final Map<String, String> _bubbles = {};
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _subs.add(s.views.listen((v) => setState(() {
          if (v.phase == 'lobby' || v.phase == 'countdown') _summary = null;
          _view = v;
        })));
    _subs.add(s.summaries.listen((m) => setState(() => _summary = m)));
    _subs.add(s.statusChanges.listen((st) => setState(() => _status = st)));
    _subs.add(s.errors.listen(_onError));
    _subs.add(s.quickChat.listen((c) {
      setState(() => _bubbles[c.from] = c.phraseId);
      Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _bubbles.remove(c.from));
      });
    }));
    // Re-sync the clock now and then; repaint countdowns every 250 ms.
    _tick = Timer.periodic(const Duration(milliseconds: 250), (t) {
      if (t.tick % 40 == 0) s.syncClock();
      if (mounted && (_view?.phase == 'countdown')) setState(() {});
    });
  }

  void _onError(String code) {
    if (!mounted) return;
    final text = switch (code) {
      'not_enough_content' => S.of('notEnoughContent'),
      'not_enough_players' => S.of('needMorePlayers'),
      'too_late' ||
      'too_early' ||
      'already_answered' ||
      'not_accepting' =>
        null,
      _ => S.of('error'),
    };
    if (text != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  void dispose() {
    for (final x in _subs) {
      x.cancel();
    }
    _tick?.cancel();
    s.leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _view;
    return Scaffold(
      backgroundColor: Tokens.night,
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: v?.code != null
            ? GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: v.code!));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(S.of('shareCode'))));
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${S.of('roomCode')}: ',
                      style: const TextStyle(fontSize: 16)),
                  Text(v!.code!,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, letterSpacing: 3)),
                  const SizedBox(width: 6),
                  const Icon(Icons.copy_rounded, size: 18),
                ]),
              )
            : Text(S.of('game_quiz')),
        actions: [
          if (v?.isSafeMode == true)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Tokens.s8),
              child: Tooltip(
                  message: S.of('safeModeInfo'),
                  child: Pill(
                      text: S.of('safeMode'),
                      color: Tokens.mint,
                      icon: Icons.shield_rounded)),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (_status != ConnectionStatus.connected)
            Container(
              width: double.infinity,
              color:
                  _status == ConnectionStatus.lost ? Tokens.danger : Tokens.sun,
              padding: const EdgeInsets.all(Tokens.s8),
              child: Text(
                  S.of(_status == ConnectionStatus.lost
                      ? 'connectionLost'
                      : 'reconnecting'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          Expanded(
            child: v == null
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : AnimatedSwitcher(duration: Tokens.medium, child: _body(v)),
          ),
          _PhraseBar(onSend: s.sendPhrase),
        ]),
      ),
    );
  }

  Widget _body(RoomView v) {
    final me = v.me;
    if (me?.waiting == true) {
      return _Waiting(
          key: const ValueKey('waiting'),
          view: v,
          bubbles: _bubbles,
          onPlayer: _playerSheet);
    }
    final quiz = v.quiz;
    if ((v.phase == 'results' || quiz?.stage == 'finished') &&
        quiz?.ranking != null) {
      return _Results(
          key: const ValueKey('results'),
          view: v,
          summary: _summary,
          onPlayer: _playerSheet);
    }
    if (v.phase == 'playing' && quiz != null) {
      return _QuestionPane(
          key: ValueKey('q${quiz.question?.index}-${quiz.stage}'),
          view: v,
          session: s,
          onPlayer: _playerSheet,
          bubbles: _bubbles);
    }
    return _Lobby(
        key: const ValueKey('lobby'),
        view: v,
        session: s,
        bubbles: _bubbles,
        onPlayer: _playerSheet);
  }

  void _playerSheet(PublicPlayer p) {
    if (p.playerId == _view?.you) return;
    final api = AppScope.read(context).api;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: Tokens.s16),
          ChibiAvatar(avatarId: p.avatarId, size: 64),
          Text(p.displayName, style: Theme.of(ctx).textTheme.titleMedium),
          ListTile(
            leading: const Icon(Icons.flag_rounded, color: Tokens.coral),
            title: Text(S.of('report')),
            onTap: () async {
              Navigator.pop(ctx);
              final reason = await _pickReason();
              if (reason == null) return;
              try {
                await api.report(
                    userId: p.playerId, reason: reason, roomId: _view?.roomId);
                _toast(S.of('reportSent'));
              } catch (_) {
                _toast(S.of('error'));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: Text(S.of('block')),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await api.block(p.playerId);
                _toast(S.of('blocked'));
              } catch (_) {
                _toast(S.of('error'));
              }
            },
          ),
        ]),
      ),
    );
  }

  Future<String?> _pickReason() => showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            Padding(
                padding: const EdgeInsets.all(Tokens.s16),
                child: Text(S.of('reportReason'),
                    style: Theme.of(ctx).textTheme.titleMedium)),
            for (final r in const [
              'bullying',
              'hate_or_harassment',
              'cheating',
              'inappropriate_name_or_avatar',
              'child_safety',
              'threat_or_self_harm',
              'other'
            ])
              ListTile(
                  title: Text(S.of('reason_$r')),
                  onTap: () => Navigator.pop(ctx, r)),
          ]),
        ),
      );

  void _toast(String t) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    }
  }
}

/* ---------------------------------- lobby ---------------------------------- */

class _Lobby extends StatelessWidget {
  const _Lobby(
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
  Widget build(BuildContext context) {
    final me = view.me;
    final isHost = me?.isHost == true;
    final private = view.mode == 'private';
    final countdown = view.phase == 'countdown' && view.countdownEndsAt != null
        ? ((view.countdownEndsAt! - session.serverNow) / 1000)
            .ceil()
            .clamp(0, 99)
        : null;
    return Padding(
      padding: const EdgeInsets.all(Tokens.s16),
      child: Column(children: [
        Text(
            countdown != null
                ? '${S.of('startingIn')} $countdown'
                : (private ? S.of('lobby') : S.of('searching')),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
            '${S.of('expectedDuration')}: ~${(view.expectedDurationSec / 60).ceil()} ${S.of('minutes')}',
            style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: Tokens.s16),
        Expanded(
            child:
                _PlayersGrid(view: view, bubbles: bubbles, onPlayer: onPlayer)),
        if (private && view.players.length < 2)
          Padding(
              padding: const EdgeInsets.all(Tokens.s8),
              child: Text(S.of('needMorePlayers'),
                  style: const TextStyle(color: Colors.white70))),
        if (private && isHost && view.phase == 'lobby')
          GameButton(
              key: const Key('startMatch'),
              label: S.of('start'),
              color: Tokens.sun,
              onPressed: view.players.length >= 2 ? session.start : null),
        if (private && !isHost && view.phase == 'lobby')
          GameButton(
            label: me?.ready == true ? S.of('ready') : S.of('notReady'),
            color: me?.ready == true ? Tokens.success : Tokens.inkSoft,
            onPressed: () => session.setReady(!(me?.ready ?? false)),
          ),
      ]),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting(
      {super.key,
      required this.view,
      required this.bubbles,
      required this.onPlayer});
  final RoomView view;
  final Map<String, String> bubbles;
  final void Function(PublicPlayer) onPlayer;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Tokens.s16),
        child: Column(children: [
          Text(S.of('waitingNextRound'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: Tokens.s16),
          Expanded(
              child: _PlayersGrid(
                  view: view, bubbles: bubbles, onPlayer: onPlayer)),
        ]),
      );
}

class _PlayersGrid extends StatelessWidget {
  const _PlayersGrid(
      {required this.view, required this.bubbles, required this.onPlayer});
  final RoomView view;
  final Map<String, String> bubbles;
  final void Function(PublicPlayer) onPlayer;

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 4,
        mainAxisSpacing: Tokens.s12,
        crossAxisSpacing: Tokens.s8,
        childAspectRatio: 0.7,
        children: [
          for (final p in view.players)
            GestureDetector(
              onTap: () => onPlayer(p),
              child: Column(children: [
                Stack(clipBehavior: Clip.none, children: [
                  ChibiAvatar(
                      avatarId: p.avatarId, size: 64, dimmed: !p.connected),
                  if (bubbles[p.playerId] != null)
                    Positioned(
                        top: -8,
                        left: 0,
                        right: 0,
                        child: Center(
                            child: _Bubble(
                                text: S.of('phrase_${bubbles[p.playerId]}')))),
                  if (p.isHost)
                    const Positioned(
                        bottom: 0,
                        right: 0,
                        child: Text('👑', style: TextStyle(fontSize: 18))),
                ]),
                const SizedBox(height: 4),
                Text(p.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: p.playerId == view.you
                            ? FontWeight.w900
                            : FontWeight.w600)),
                if (p.ready && view.mode == 'private' && view.phase == 'lobby')
                  const Icon(Icons.check_circle,
                      color: Tokens.success, size: 16),
                if (!p.connected)
                  const Icon(Icons.wifi_off_rounded,
                      color: Colors.white54, size: 16),
              ]),
            ),
        ],
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: const BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.all(Tokens.r8)),
        child: Text(text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

/* -------------------------------- question --------------------------------- */

class _QuestionPane extends StatefulWidget {
  const _QuestionPane(
      {super.key,
      required this.view,
      required this.session,
      required this.onPlayer,
      required this.bubbles});
  final RoomView view;
  final GameSession session;
  final void Function(PublicPlayer) onPlayer;
  final Map<String, String> bubbles;

  @override
  State<_QuestionPane> createState() => _QuestionPaneState();
}

class _QuestionPaneState extends State<_QuestionPane> {
  Timer? _revealTimer;
  bool _visible = false;
  int? _picked;

  @override
  void initState() {
    super.initState();
    final q = widget.view.quiz!.question;
    if (q == null) return;
    final wait = q.revealAt - widget.session.serverNow;
    if (wait <= 0) {
      _show(q.index);
    } else {
      _revealTimer = Timer(Duration(milliseconds: wait), () => _show(q.index));
    }
  }

  void _show(int index) {
    if (!mounted) return;
    setState(() => _visible = true);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.session.markQuestionShown(index));
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quiz = widget.view.quiz!;
    final q = quiz.question;
    final reveal = quiz.reveal;
    final chosen = quiz.yourChoice ?? _picked;
    if (q == null) return const SizedBox.shrink();
    final myPoints = reveal?.points[widget.view.you];
    return Padding(
      padding: const EdgeInsets.all(Tokens.s16),
      child: Column(children: [
        Row(children: [
          Pill(text: S.of('cat_${q.category}'), color: Tokens.sun),
          const Spacer(),
          Text('${S.of('question')} ${q.index + 1} ${S.of('of')} ${q.total}',
              style: const TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: Tokens.s12),
        if (reveal == null)
          ServerTimerBar(
              startsAt: q.revealAt,
              endsAt: q.deadline,
              serverNow: () => widget.session.serverNow)
        else
          _RevealBanner(points: myPoints ?? 0, answered: chosen != null),
        const SizedBox(height: Tokens.s16),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(Tokens.s16),
          alignment: Alignment.center,
          decoration: const BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.all(Tokens.r24)),
          child: AnimatedOpacity(
            duration: Tokens.fast,
            opacity: _visible ? 1 : 0,
            child: Text(q.prompt,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        const SizedBox(height: Tokens.s16),
        Expanded(
          child: AnimatedOpacity(
            duration: Tokens.fast,
            opacity: _visible ? 1 : 0,
            child: ListView.separated(
              itemCount: q.choices.length,
              separatorBuilder: (_, __) => const SizedBox(height: Tokens.s8),
              itemBuilder: (_, i) => _ChoiceButton(
                key: Key('choice$i'),
                label: _choiceLabels[i],
                text: q.choices[i],
                color: Tokens.choiceColors[i % Tokens.choiceColors.length],
                state: reveal != null
                    ? (i == reveal.correctChoice
                        ? _ChoiceState.correct
                        : (i == chosen
                            ? _ChoiceState.wrong
                            : _ChoiceState.faded))
                    : (chosen == null
                        ? _ChoiceState.open
                        : (i == chosen
                            ? _ChoiceState.picked
                            : _ChoiceState.faded)),
                onTap: (_visible && chosen == null && reveal == null)
                    ? () {
                        HapticFeedback.lightImpact();
                        setState(() => _picked = i);
                        widget.session.answer(q.index, i);
                      }
                    : null,
              ),
            ),
          ),
        ),
        _ScoreStrip(view: widget.view, onPlayer: widget.onPlayer),
        if (reveal == null && chosen != null)
          Padding(
            padding: const EdgeInsets.only(top: Tokens.s8),
            child: Text(
                '${S.of('yourAnswerSaved')} · ${quiz.answeredCount}/${widget.view.players.length} ${S.of('answered')}',
                style: const TextStyle(color: Colors.white70)),
          ),
      ]),
    );
  }
}

class _RevealBanner extends StatelessWidget {
  const _RevealBanner({required this.points, required this.answered});
  final int points;
  final bool answered;
  @override
  Widget build(BuildContext context) {
    final ok = points > 0;
    final text = ok
        ? '${S.of('correct')}  +$points ${S.of('points')}'
        : (answered ? S.of('wrong') : S.of('noAnswer'));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: Tokens.medium,
      curve: Curves.elasticOut,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: Pill(
          text: text,
          color: ok ? Tokens.success : Tokens.coral,
          icon: ok ? Icons.check_rounded : Icons.close_rounded),
    );
  }
}

enum _ChoiceState { open, picked, correct, wrong, faded }

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton(
      {super.key,
      required this.label,
      required this.text,
      required this.color,
      required this.state,
      this.onTap});
  final String label;
  final String text;
  final Color color;
  final _ChoiceState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = switch (state) {
      _ChoiceState.correct => Tokens.success,
      _ChoiceState.wrong => Tokens.danger,
      _ChoiceState.faded => color.withValues(alpha: 0.35),
      _ => color,
    };
    return Semantics(
      button: true,
      label: '$label: $text',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Tokens.fast,
          padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s16, vertical: Tokens.s16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.all(Tokens.r16),
            border: state == _ChoiceState.picked
                ? Border.all(color: Colors.white, width: 3)
                : null,
          ),
          child: Row(children: [
            CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900))),
            const SizedBox(width: Tokens.s12),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800))),
            if (state == _ChoiceState.correct)
              const Icon(Icons.check_circle_rounded, color: Colors.white),
          ]),
        ),
      ),
    );
  }
}

class _ScoreStrip extends StatelessWidget {
  const _ScoreStrip({required this.view, required this.onPlayer});
  final RoomView view;
  final void Function(PublicPlayer) onPlayer;
  @override
  Widget build(BuildContext context) {
    final scores = view.quiz?.scores ?? const {};
    final players = view.players
        .where((p) => scores.containsKey(p.playerId))
        .toList()
      ..sort((a, b) =>
          (scores[b.playerId] ?? 0).compareTo(scores[a.playerId] ?? 0));
    return SizedBox(
      height: 72,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final p in players)
          GestureDetector(
            onTap: () => onPlayer(p),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(children: [
                ChibiAvatar(
                    avatarId: p.avatarId, size: 40, dimmed: !p.connected),
                Text('${scores[p.playerId] ?? 0}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/* --------------------------------- results --------------------------------- */

class _Results extends StatelessWidget {
  const _Results(
      {super.key,
      required this.view,
      required this.summary,
      required this.onPlayer});
  final RoomView view;
  final MatchSummary? summary;
  final void Function(PublicPlayer) onPlayer;

  @override
  Widget build(BuildContext context) {
    final ranking = view.quiz!.ranking!;
    final byId = {for (final p in view.players) p.playerId: p};
    return ListView(padding: const EdgeInsets.all(Tokens.s16), children: [
      Text(S.of('results'),
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
      const SizedBox(height: Tokens.s16),
      for (final r in ranking)
        Container(
          margin: const EdgeInsets.only(bottom: Tokens.s8),
          padding: const EdgeInsets.all(Tokens.s12),
          decoration: BoxDecoration(
            color: r.playerId == view.you
                ? Tokens.sun
                : Colors.white.withValues(alpha: 0.1),
            borderRadius: const BorderRadius.all(Tokens.r16),
          ),
          child: Row(children: [
            Text(
                r.place == 1
                    ? '🥇'
                    : r.place == 2
                        ? '🥈'
                        : r.place == 3
                            ? '🥉'
                            : '${r.place}',
                style: const TextStyle(fontSize: 26, color: Colors.white)),
            const SizedBox(width: Tokens.s12),
            ChibiAvatar(
              avatarId: byId[r.playerId]?.avatarId ?? 'chibi_base_1',
              size: 44,
              expression: r.place == 1
                  ? ChibiExpression.happy
                  : ChibiExpression.neutral,
            ),
            const SizedBox(width: Tokens.s12),
            Expanded(
              child: Text(byId[r.playerId]?.displayName ?? '—',
                  style: TextStyle(
                      color: r.playerId == view.you ? Tokens.ink : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
            ),
            Text('${r.score}',
                style: TextStyle(
                    color: r.playerId == view.you ? Tokens.ink : Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18)),
          ]),
        ),
      const SizedBox(height: Tokens.s16),
      if (summary != null)
        Container(
          padding: const EdgeInsets.all(Tokens.s16),
          decoration: const BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.all(Tokens.r24)),
          child: Wrap(
              alignment: WrapAlignment.spaceEvenly,
              spacing: Tokens.s16,
              runSpacing: Tokens.s8,
              children: [
                _Stat(icon: '⭐', label: S.of('xp'), value: '+${summary!.xp}'),
                _Stat(
                    icon: '🪙',
                    label: S.of('coins'),
                    value: '+${summary!.coins}'),
                if (summary!.ratingAfter != null)
                  _Stat(
                    icon: '🏆',
                    label: summary!.provisional
                        ? S.of('provisional')
                        : S.of('rating'),
                    value:
                        '${summary!.ratingAfter} (${summary!.ratingAfter! - summary!.ratingBefore! >= 0 ? '+' : ''}${summary!.ratingAfter! - summary!.ratingBefore!})',
                  ),
              ]),
        ),
      if (summary != null)
        for (final n in summary!.notes)
          if (S.has('note_$n'))
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s8),
              child: Text(S.of('note_$n'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
      const SizedBox(height: Tokens.s24),
      GameButton(
          label: S.of('backHome'),
          color: Tokens.inkSoft,
          onPressed: () => Navigator.of(context).pop()),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});
  final String icon, label, value;
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 28)),
        Text(value,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        Text(label, style: const TextStyle(color: Tokens.inkSoft)),
      ]);
}

/* --------------------------------- phrases --------------------------------- */

class _PhraseBar extends StatelessWidget {
  const _PhraseBar({required this.onSend});
  final void Function(String) onSend;
  @override
  Widget build(BuildContext context) => Container(
        height: 52,
        color: Tokens.nightDeep,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s8, vertical: Tokens.s8),
          children: [
            for (final p in _phrases)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ActionChip(
                    label: Text(S.of('phrase_$p')), onPressed: () => onSend(p)),
              ),
          ],
        ),
      );
}
