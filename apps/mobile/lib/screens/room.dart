import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sahra_client/sahra_client.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../design/chibi_avatar.dart';
import '../design/sfx.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'liar_pane.dart';
import 'draw_pane.dart';
import 'memory_pane.dart';
import 'stop_pane.dart';
import 'spy_pane.dart';
import 'who_pane.dart';

const _phrases = ['gg', 'nice', 'wow', 'good_luck', 'thanks', 'oops', 'hurry'];
const _phraseEmoji = {
  'gg': '👏',
  'nice': '🔥',
  'wow': '😮',
  'good_luck': '🍀',
  'thanks': '🙏',
  'oops': '🙈',
  'hurry': '⏩',
};
const _choiceLabels = ['أ', 'ب', 'ج', 'د', 'هـ', 'و'];
const _choiceShapes = [
  Icons.change_history_rounded,
  Icons.diamond_rounded,
  Icons.circle,
  Icons.square_rounded,
  Icons.star_rounded,
  Icons.favorite_rounded,
];
const _categoryEmoji = {
  'geography': '🌍',
  'history': '🏛️',
  'science': '🔬',
  'sports': '⚽',
  'general': '💡',
  'entertainment': '🎬',
  'movies': '🎬',
  'football': '⚽',
  'food': '🍽️',
  'places': '🗺️',
  'sayings': '💬',
  'games': '🎮',
};
const _maxSeats = 8;

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

  /// Last finished match, kept on screen until the player moves on (the
  /// server resets the room to the lobby a few seconds after a match).
  RoomView? _results;
  ConnectionStatus _status = ConnectionStatus.connected;
  final Map<String, String> _bubbles = {};
  Timer? _tick;
  int? _lastCount;

  @override
  void initState() {
    super.initState();
    _subs.add(s.views.listen((v) {
      _soundsFor(_view, v);
      setState(() {
        final q = v.quiz;
        if (((v.phase == 'results' || q?.stage == 'finished') &&
                q?.ranking != null) ||
            v.spy?.final_ != null ||
            v.liar?.final_ != null ||
            v.who?.final_ != null ||
            v.stop?.final_ != null ||
            v.memory?.ranking != null ||
            v.draw?.ranking != null) {
          _results = v;
        } else if (v.phase == 'countdown' || v.phase == 'playing') {
          if (_results != null) _summary = null;
          _results = null;
        }
        _view = v;
      });
    }));
    _subs.add(s.summaries.listen((m) => setState(() => _summary = m)));
    _subs.add(s.statusChanges.listen((st) => setState(() => _status = st)));
    _subs.add(s.errors.listen(_onError));
    _subs.add(s.quickChat.listen((c) {
      Sfx.play('pop', volume: 0.45);
      setState(() => _bubbles[c.from] = c.phraseId);
      Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _bubbles.remove(c.from));
      });
    }));
    // Re-sync the clock now and then; repaint countdowns every 250 ms.
    _tick = Timer.periodic(const Duration(milliseconds: 250), (t) {
      if (t.tick % 40 == 0) s.syncClock();
      final v = _view;
      if (mounted && v?.phase == 'countdown' && v?.countdownEndsAt != null) {
        final n = ((v!.countdownEndsAt! - s.serverNow) / 1000).ceil();
        if (n != _lastCount && n >= 1 && n <= 5) Sfx.play('tick', volume: 0.5);
        _lastCount = n;
        setState(() {});
      }
    });
  }

  /// Plays the sound that matches what just changed in the room.
  void _soundsFor(RoomView? old, RoomView v) {
    if (old == null) return;
    if ((v.phase == 'lobby' || v.phase == 'countdown') &&
        v.players.length > old.players.length) {
      Sfx.play('join', volume: 0.5);
    }
    if (old.phase == 'countdown' && v.phase == 'playing') Sfx.play('go');
    final spyDone = v.spy?.final_ != null && old.spy?.final_ == null;
    final liarDone = v.liar?.final_ != null && old.liar?.final_ == null;
    final whoDone = v.who?.final_ != null && old.who?.final_ == null;
    final stopDone = v.stop?.final_ != null && old.stop?.final_ == null;
    final memDone = v.memory?.ranking != null && old.memory?.ranking == null;
    final drawDone = v.draw?.ranking != null && old.draw?.ranking == null;
    final finishedNow = spyDone ||
        drawDone ||
        stopDone ||
        memDone ||
        liarDone ||
        whoDone ||
        (v.quiz?.ranking != null &&
            (v.phase == 'results' || v.quiz?.stage == 'finished') &&
            old.quiz?.ranking == null);
    if (finishedNow) {
      final f = v.spy?.final_;
      final ranking = v.liar?.final_?.ranking ??
          v.stop?.final_?.ranking ??
          v.memory?.ranking ??
          v.draw?.ranking ??
          v.quiz?.ranking ??
          const [];
      final won = whoDone ||
          (f != null
              ? (f.winner == 'spies') == f.spies.contains(v.you)
              : ranking.where((r) => r.playerId == v.you).firstOrNull?.place ==
                  1);
      if (won) {
        Sfx.play('win');
        HapticFeedback.heavyImpact();
      } else {
        Sfx.play('finish');
      }
    }
  }

  void _onError(String code) {
    if (!mounted) return;
    final text = switch (code) {
      'not_enough_content' => S.of('notEnoughContent'),
      'not_enough_players' => S.of('needMorePlayers'),
      'drawing_limit' => S.of('drawLimit'),
      'safe_mode_unavailable' => S.of('safeModeUnavailable'),
      'too_fast' ||
      'already_guessed' ||
      'too_late' ||
      'too_early' ||
      'already_answered' ||
      'not_accepting' =>
        null,
      _ => S.of('error'),
    };
    if (text != null) _toast(text);
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
    return NightScaffold(
      glow: Tokens.sky,
      title:
          v?.code != null ? _CodeChip(code: v!.code!, onCopy: _copyCode) : null,
      actions: [
        RoundIconButton(
          icon:
              Sfx.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          tooltip: S.of(Sfx.enabled ? 'soundOff' : 'soundOn'),
          onPressed: () async {
            await Sfx.setEnabled(!Sfx.enabled);
            if (mounted) setState(() {});
          },
        ),
        if (v?.isSafeMode == true) ...[
          const SizedBox(width: Tokens.s8),
          Tooltip(
              message: S.of('safeModeInfo'),
              child: Pill(
                  text: S.of('safeMode'),
                  color: Tokens.mint,
                  icon: Icons.shield_rounded)),
        ],
      ],
      bottom: _PhraseBar(onSend: s.sendPhrase),
      body: Column(children: [
        AnimatedSize(
          duration: Tokens.medium,
          child: _status == ConnectionStatus.connected
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(
                      Tokens.s16, 0, Tokens.s16, Tokens.s8),
                  padding: const EdgeInsets.all(Tokens.s12),
                  decoration: BoxDecoration(
                      color: _status == ConnectionStatus.lost
                          ? Tokens.danger
                          : Tokens.sun,
                      borderRadius: const BorderRadius.all(Tokens.r16)),
                  child: Row(children: [
                    if (_status != ConnectionStatus.lost)
                      const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Tokens.ink))
                    else
                      const Icon(Icons.wifi_off_rounded, color: Colors.white),
                    const SizedBox(width: Tokens.s8),
                    Expanded(
                      child: Text(
                          S.of(_status == ConnectionStatus.lost
                              ? 'connectionLost'
                              : 'reconnecting'),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _status == ConnectionStatus.lost
                                  ? Colors.white
                                  : Tokens.ink)),
                    ),
                  ]),
                ),
        ),
        Expanded(
          child: v == null
              ? const Center(
                  child: CircularProgressIndicator(color: Tokens.sun))
              : AnimatedSwitcher(
                  duration: Tokens.medium,
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(
                          scale: Tween(begin: 0.97, end: 1.0).animate(a),
                          child: c)),
                  child: _body(v)),
        ),
      ]),
    );
  }

  void _copyCode() {
    final code = _view?.code;
    if (code == null) return;
    Clipboard.setData(ClipboardData(text: code));
    _toast(S.of('codeCopied'));
  }

  Widget _body(RoomView v) {
    final me = v.me;
    if (_results != null &&
        (_results!.spy != null ||
            _results!.liar != null ||
            _results!.who != null ||
            _results!.stop != null ||
            _results!.memory != null ||
            _results!.draw != null)) {
      final rewards = _summary == null
          ? const SizedBox.shrink()
          : _SummaryCard(summary: _summary!);
      final actions = [
        if (v.mode == 'private' || v.phase == 'lobby') ...[
          GameButton(
              label: S.of('playAgain'),
              icon: Icons.replay_rounded,
              color: Tokens.sun,
              onPressed: () => setState(() {
                    _results = null;
                    _summary = null;
                  })),
          const SizedBox(height: Tokens.s12),
        ],
        GameButton(
            label: S.of('backHome'),
            icon: Icons.home_rounded,
            color: Tokens.grape,
            onPressed: () => Navigator.of(context).pop()),
      ];
      if (_results!.draw != null) {
        return DrawResults(
            key: const ValueKey('results'),
            view: _results!,
            rewards: rewards,
            actions: actions);
      }
      if (_results!.memory != null) {
        return MemoryResults(
            key: const ValueKey('results'),
            view: _results!,
            rewards: rewards,
            actions: actions);
      }
      if (_results!.stop != null) {
        return StopResults(
            key: const ValueKey('results'),
            view: _results!,
            rewards: rewards,
            actions: actions);
      }
      if (_results!.who != null) {
        return WhoResults(
            key: const ValueKey('results'),
            view: _results!,
            rewards: rewards,
            actions: actions);
      }
      return _results!.liar != null
          ? LiarResults(
              key: const ValueKey('results'),
              view: _results!,
              rewards: rewards,
              actions: actions)
          : SpyResults(
              key: const ValueKey('results'),
              view: _results!,
              rewards: rewards,
              actions: actions);
    }
    if (_results != null) {
      return _Results(
          key: const ValueKey('results'),
          view: _results!,
          summary: _summary,
          canRematch:
              v.mode == 'private' || v.mode == 'practice' || v.phase == 'lobby',
          onRematch: () => setState(() {
                _results = null;
                _summary = null;
                // Practice restarts straight away (the server skips the wait).
                if (v.mode == 'practice') s.start();
              }),
          onPlayer: _playerSheet);
    }
    if (me?.waiting == true) {
      return _Waiting(
          key: const ValueKey('waiting'),
          view: v,
          bubbles: _bubbles,
          onPlayer: _playerSheet);
    }
    if (v.phase == 'playing' && v.draw != null) {
      return DrawPane(
          key: const ValueKey('draw'),
          view: v,
          session: s,
          bubbles: _bubbles,
          onPlayer: _playerSheet);
    }
    if (v.phase == 'playing' && v.memory != null) {
      return MemoryPane(
          key: const ValueKey('memory'),
          view: v,
          session: s,
          bubbles: _bubbles);
    }
    if (v.phase == 'playing' && v.stop != null) {
      return StopPane(
          key: const ValueKey('stop'), view: v, session: s, bubbles: _bubbles);
    }
    if (v.phase == 'playing' && v.who != null) {
      return WhoPane(
          key: const ValueKey('who'), view: v, session: s, bubbles: _bubbles);
    }
    if (v.phase == 'playing' && v.liar != null) {
      return LiarPane(
          key: const ValueKey('liar'), view: v, session: s, bubbles: _bubbles);
    }
    if (v.phase == 'playing' && v.spy != null) {
      return SpyPane(
          key: const ValueKey('spy'),
          view: v,
          session: s,
          bubbles: _bubbles,
          onPlayer: _playerSheet);
    }
    final quiz = v.quiz;
    if (v.phase == 'playing' && quiz != null) {
      return _QuestionPane(
          key: ValueKey('q${quiz.question?.index}-${quiz.stage}'),
          view: v,
          session: s,
          onPlayer: _playerSheet,
          bubbles: _bubbles);
    }
    if (v.phase == 'countdown' && v.countdownEndsAt != null) {
      return _Countdown(
          key: const ValueKey('countdown'),
          view: v,
          session: s,
          bubbles: _bubbles);
    }
    return _Lobby(
        key: const ValueKey('lobby'),
        view: v,
        session: s,
        bubbles: _bubbles,
        onPlayer: _playerSheet,
        onCopy: _copyCode);
  }

  void _playerSheet(PublicPlayer p) {
    if (p.playerId == _view?.you) return;
    final api = AppScope.read(context).api;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(Tokens.s24, 0, Tokens.s24, Tokens.s24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ChibiAvatar(avatarId: p.avatarId, size: 88),
            const SizedBox(height: Tokens.s8),
            Text(p.displayName,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: Tokens.s16),
            _SheetButton(
              icon: Icons.flag_rounded,
              color: Tokens.coral,
              label: S.of('report'),
              onTap: () async {
                Navigator.pop(ctx);
                final reason = await _pickReason();
                if (reason == null) return;
                try {
                  await api.report(
                      userId: p.playerId,
                      reason: reason,
                      roomId: _view?.roomId,
                      matchId: _view?.matchId);
                  _toast(S.of('reportSent'));
                } catch (_) {
                  _toast(S.of('error'));
                }
              },
            ),
            const SizedBox(height: Tokens.s8),
            _SheetButton(
              icon: Icons.block_rounded,
              color: Tokens.textDim,
              label: S.of('block'),
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
      ),
    );
  }

  Future<String?> _pickReason() => showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                  Tokens.s24, 0, Tokens.s24, Tokens.s24),
              children: [
                Text(S.of('reportReason'),
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: Tokens.s12),
                for (final r in const [
                  'bullying',
                  'hate_or_harassment',
                  'cheating',
                  'inappropriate_name_or_avatar',
                  'child_safety',
                  'threat_or_self_harm',
                  'other'
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: Tokens.s8),
                    child: _SheetButton(
                        label: S.of('reason_$r'),
                        onTap: () => Navigator.pop(ctx, r)),
                  ),
              ]),
        ),
      );

  void _toast(String t) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t)));
    }
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton(
      {required this.label, required this.onTap, this.icon, this.color});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        child: GlassCard(
          radius: Tokens.r16,
          padding:
              const EdgeInsets.symmetric(horizontal: Tokens.s16, vertical: 14),
          child: Row(children: [
            if (icon != null) ...[
              Icon(icon, color: color),
              const SizedBox(width: Tokens.s12),
            ],
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700))),
          ]),
        ),
      );
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code, required this.onCopy});
  final String code;
  final VoidCallback onCopy;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onCopy,
        semanticLabel: '${S.of('roomCode')}: $code',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: const BoxDecoration(
              color: Tokens.glass,
              borderRadius: BorderRadius.all(Radius.circular(99)),
              border:
                  Border.fromBorderSide(BorderSide(color: Tokens.glassBorder))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(code,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                    fontFamily: Tokens.body,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 3)),
            const SizedBox(width: 6),
            const Icon(Icons.copy_rounded, size: 16, color: Tokens.textDim),
          ]),
        ),
      );
}

/* ---------------------------------- lobby ---------------------------------- */

class _Lobby extends StatelessWidget {
  const _Lobby(
      {super.key,
      required this.view,
      required this.session,
      required this.bubbles,
      required this.onPlayer,
      required this.onCopy});
  final RoomView view;
  final GameSession session;
  final Map<String, String> bubbles;
  final void Function(PublicPlayer) onPlayer;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final me = view.me;
    final isHost = me?.isHost == true;
    final private = view.mode == 'private';
    final practice = view.mode == 'practice';
    final hostStarts = private || practice;
    final enough = view.players.length >=
        (const {'spy', 'liar', 'who'}.contains(view.gameId) ? 3 : 2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s16),
      child: Column(children: [
        if (private && view.code != null)
          FadeSlideIn(child: _CodeCard(code: view.code!, onCopy: onCopy))
        else if (practice)
          const FadeSlideIn(child: _PracticeCard())
        else
          FadeSlideIn(child: _Searching(mode: view.mode)),
        const SizedBox(height: Tokens.s20),
        Row(children: [
          Text(S.of('lobby'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: Tokens.s8),
          Pill(
              text: '${view.players.length}/$_maxSeats',
              color: Tokens.sky,
              icon: Icons.people_alt_rounded),
          const Spacer(),
          Text(
              '⏱️ ~${(view.expectedDurationSec / 60).ceil()} ${S.of('minutes')}',
              style: const TextStyle(color: Tokens.textDim)),
        ]),
        const SizedBox(height: Tokens.s12),
        Expanded(
            child: _Seats(
                view: view,
                bubbles: bubbles,
                onPlayer: onPlayer,
                showEmpty: private)),
        if (private && !enough)
          Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s12),
              child: Text(S.of('needMorePlayers'),
                  style: const TextStyle(color: Tokens.textDim))),
        if (hostStarts && isHost && view.phase == 'lobby')
          GameButton(
              key: const Key('startMatch'),
              label: S.of('start'),
              icon: Icons.play_arrow_rounded,
              color: Tokens.sun,
              onPressed: enough ? session.start : null),
        if (private && !isHost && view.phase == 'lobby')
          GameButton(
            label: me?.ready == true ? S.of('ready') : S.of('imReady'),
            icon: me?.ready == true
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: me?.ready == true ? Tokens.success : Tokens.grape,
            onPressed: () => session.setReady(!(me?.ready ?? false)),
          ),
      ]),
    );
  }
}

class _PracticeCard extends StatelessWidget {
  const _PracticeCard();
  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(Tokens.s20),
        child: Row(children: [
          const Bob(child: Text('🤖', style: TextStyle(fontSize: 40))),
          const SizedBox(width: Tokens.s16),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(S.of('practice'),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              Text(S.of('practiceLobby'),
                  style: const TextStyle(color: Tokens.textDim, height: 1.4)),
            ]),
          ),
        ]),
      );
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.onCopy});
  final String code;
  final VoidCallback onCopy;
  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(Tokens.s20),
        child: Column(children: [
          Text(S.of('shareCode'),
              style: const TextStyle(color: Tokens.textDim, fontSize: 15)),
          const SizedBox(height: Tokens.s12),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final ch in code.split(''))
                  Container(
                    width: 40,
                    height: 52,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.all(Tokens.r12),
                      boxShadow: [
                        BoxShadow(
                            color: Tokens.shade(Tokens.grape, 0.1),
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: Text(ch,
                        style: const TextStyle(
                            fontFamily: Tokens.body,
                            color: Tokens.ink,
                            fontSize: 26,
                            fontWeight: FontWeight.w900)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s16),
          GameButton(
              label: S.of('copyCode'),
              icon: Icons.copy_rounded,
              color: Tokens.grape,
              size: GameButtonSize.medium,
              expand: false,
              onPressed: onCopy),
        ]),
      );
}

class _Searching extends StatelessWidget {
  const _Searching({required this.mode});
  final String mode;
  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(Tokens.s20),
        child: Row(children: [
          const _Radar(),
          const SizedBox(width: Tokens.s16),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(S.of('searching'),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              Text(S.of(mode == 'ranked' ? 'ranked' : 'quickPlay'),
                  style: const TextStyle(color: Tokens.textDim)),
            ]),
          ),
        ]),
      );
}

class _Radar extends StatefulWidget {
  const _Radar();
  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 56,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Stack(alignment: Alignment.center, children: [
            for (final d in [0.0, 0.5])
              Opacity(
                opacity: (1 - ((_c.value + d) % 1)).clamp(0.0, 1.0),
                child: Container(
                  width: 56 * ((_c.value + d) % 1),
                  height: 56 * ((_c.value + d) % 1),
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Tokens.sun, width: 2)),
                ),
              ),
            const Text('🔎', style: TextStyle(fontSize: 24)),
          ]),
        ),
      );
}

class _Seats extends StatelessWidget {
  const _Seats(
      {required this.view,
      required this.bubbles,
      required this.onPlayer,
      this.showEmpty = true});
  final RoomView view;
  final Map<String, String> bubbles;
  final void Function(PublicPlayer) onPlayer;
  final bool showEmpty;

  @override
  Widget build(BuildContext context) {
    final players = view.players;
    final seats =
        showEmpty ? (players.length + 1).clamp(4, _maxSeats) : players.length;
    return GridView.builder(
      padding: const EdgeInsets.only(top: Tokens.s12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: Tokens.s16,
          crossAxisSpacing: Tokens.s8,
          childAspectRatio: 0.72),
      itemCount: seats,
      itemBuilder: (_, i) {
        if (i >= players.length) return const _EmptySeat();
        final p = players[i];
        return FadeSlideIn(
          key: ValueKey(p.playerId),
          child: _PlayerSeat(
              player: p,
              isMe: p.playerId == view.you,
              bubble: bubbles[p.playerId],
              showReady: view.mode == 'private' && view.phase == 'lobby',
              onTap: () => onPlayer(p)),
        );
      },
    );
  }
}

class _PlayerSeat extends StatelessWidget {
  const _PlayerSeat(
      {required this.player,
      required this.isMe,
      required this.bubble,
      required this.showReady,
      required this.onTap});
  final PublicPlayer player;
  final bool isMe;
  final String? bubble;
  final bool showReady;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = player;
    return Pressable(
      onTap: onTap,
      semanticLabel: p.displayName,
      child: Column(children: [
        Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: isMe ? Tokens.sun : Colors.transparent, width: 3),
            ),
            child: Bob(
                amplitude: 3,
                phase: (p.playerId.hashCode % 100) / 100,
                child: ChibiAvatar(
                    avatarId: p.avatarId, size: 62, dimmed: !p.connected)),
          ),
          if (p.isHost)
            const Positioned(
                top: -10, child: Text('👑', style: TextStyle(fontSize: 20))),
          if (p.isBot)
            PositionedDirectional(
                bottom: 0,
                start: 0,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      color: Tokens.night, shape: BoxShape.circle),
                  child: const Text('🤖', style: TextStyle(fontSize: 14)),
                )),
          if (showReady && p.ready)
            const PositionedDirectional(
                bottom: 0,
                end: 0,
                child: CircleAvatar(
                    radius: 11,
                    backgroundColor: Tokens.success,
                    child: Icon(Icons.check_rounded,
                        size: 15, color: Colors.white))),
          if (!p.connected)
            const PositionedDirectional(
                bottom: 0,
                end: 0,
                child: CircleAvatar(
                    radius: 11,
                    backgroundColor: Tokens.danger,
                    child: Icon(Icons.wifi_off_rounded,
                        size: 13, color: Colors.white))),
          if (bubble != null)
            Positioned(
                top: -18,
                child: PopIn(
                    child: _Bubble(
                        text:
                            '${_phraseEmoji[bubble] ?? ''} ${S.of('phrase_$bubble')}'))),
        ]),
        const SizedBox(height: 6),
        Text(isMe ? '${p.displayName} (${S.of('you')})' : p.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: isMe ? Tokens.sun : Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _EmptySeat extends StatelessWidget {
  const _EmptySeat();
  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.18), width: 2),
          ),
          child: const Icon(Icons.person_add_alt_1_rounded,
              color: Tokens.textFaint),
        ),
        const SizedBox(height: 6),
        Text(S.of('emptySeat'),
            style: const TextStyle(color: Tokens.textFaint, fontSize: 12.5)),
      ]);
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
        padding:
            const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s16),
        child: Column(children: [
          GlassCard(
            child: Row(children: [
              const Text('⏳', style: TextStyle(fontSize: 32)),
              const SizedBox(width: Tokens.s12),
              Expanded(
                child: Text(S.of('waitingNextRound'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
          Expanded(
              child: _Seats(
                  view: view,
                  bubbles: bubbles,
                  onPlayer: onPlayer,
                  showEmpty: false)),
        ]),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Tokens.r12),
            boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 6)]),
        child: Text(text,
            maxLines: 1,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Tokens.ink)),
      );
}

/* -------------------------------- countdown -------------------------------- */

class _Countdown extends StatelessWidget {
  const _Countdown(
      {super.key,
      required this.view,
      required this.session,
      required this.bubbles});
  final RoomView view;
  final GameSession session;
  final Map<String, String> bubbles;

  @override
  Widget build(BuildContext context) {
    final n = ((view.countdownEndsAt! - session.serverNow) / 1000)
        .ceil()
        .clamp(0, 99);
    return Column(children: [
      const Spacer(),
      Text(S.of('getReady'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: Tokens.s8),
      Text(S.of('startingIn'),
          style: const TextStyle(color: Tokens.textDim, fontSize: 16)),
      const SizedBox(height: Tokens.s16),
      Semantics(
        label: '${S.of('startingIn')} $n',
        child: PopIn(
          key: ValueKey(n),
          from: 1.8,
          child: Container(
            width: 170,
            height: 170,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: Tokens.gradient(Tokens.sun, Tokens.orange),
              border: Border.all(color: Colors.white, width: 6),
              boxShadow: [
                BoxShadow(
                    color: Tokens.sun.withValues(alpha: 0.55),
                    blurRadius: 50,
                    spreadRadius: 6)
              ],
            ),
            child: Text(n == 0 ? '🚀' : '$n',
                style: const TextStyle(
                    fontSize: 92,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: Tokens.ink)),
          ),
        ),
      ),
      const Spacer(),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: Tokens.s12,
        runSpacing: Tokens.s12,
        children: [
          for (final (i, p) in view.players.indexed)
            Bob(
                phase: i * 0.2,
                child: Column(children: [
                  ChibiAvatar(avatarId: p.avatarId, size: 52),
                  const SizedBox(height: 2),
                  Text(p.displayName,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ])),
        ],
      ),
      const SizedBox(height: Tokens.s32),
    ]);
  }
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
    final quiz = widget.view.quiz!;
    final q = quiz.question;
    if (q == null) return;
    final reveal = quiz.reveal;
    if (reveal != null) {
      // Each question/stage gets a fresh pane, so this runs once per reveal.
      if ((reveal.points[widget.view.you] ?? 0) > 0) {
        Sfx.correct();
      } else if (quiz.yourChoice != null) {
        Sfx.wrong();
      }
    }
    final wait = q.revealAt - widget.session.serverNow;
    if (wait <= 0) {
      _show(q.index);
    } else {
      _revealTimer = Timer(Duration(milliseconds: wait), () => _show(q.index));
    }
  }

  void _show(int index) {
    if (!mounted) return;
    if (widget.view.quiz?.reveal == null) Sfx.play('whoosh', volume: 0.5);
    setState(() => _visible = true);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.session.markQuestionShown(index));
  }

  @override
  void didUpdateWidget(covariant _QuestionPane old) {
    super.didUpdateWidget(old);
    final now = widget.view.quiz!, before = old.view.quiz!;
    if (now.question?.typed != true || now.reveal != null) return;
    if (now.yourChoice != null && before.yourChoice == null) {
      Sfx.correct();
      HapticFeedback.mediumImpact();
    } else if (now.yourGuesses.length > before.yourGuesses.length) {
      Sfx.wrong();
      HapticFeedback.heavyImpact();
    }
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
    final avatarOf = {
      for (final p in widget.view.players) p.playerId: p.avatarId
    };
    List<String> pickersOf(int i) => [
          for (final e in (reveal?.picks ?? const <String, int>{}).entries)
            if (e.value == i && avatarOf[e.key] != null) avatarOf[e.key]!
        ];
    final grid =
        q.choices.length == 4 && q.choices.every((c) => c.length <= 16);

    Widget choice(int i) => _ChoiceTile(
          key: Key('choice$i'),
          label: _choiceLabels[i],
          shape: _choiceShapes[i % _choiceShapes.length],
          text: q.choices[i],
          color: Tokens.choiceColors[i % Tokens.choiceColors.length],
          tall: grid,
          pickers: pickersOf(i),
          state: reveal != null
              ? (i == reveal.correctChoice
                  ? _ChoiceState.correct
                  : (i == chosen ? _ChoiceState.wrong : _ChoiceState.faded))
              : (chosen == null
                  ? _ChoiceState.open
                  : (i == chosen ? _ChoiceState.picked : _ChoiceState.faded)),
          onTap: (_visible && chosen == null && reveal == null)
              ? () {
                  HapticFeedback.mediumImpact();
                  Sfx.play('pop', volume: 0.6);
                  setState(() => _picked = i);
                  widget.session.answer(q.index, i);
                }
              : null,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, Tokens.s8),
      child: Column(children: [
        Row(children: [
          Pill(
              text: S.of('cat_${q.category}'),
              emoji: _categoryEmoji[q.category] ?? '❓',
              color: Tokens.sun),
          const Spacer(),
          Text('${S.of('question')} ${q.index + 1} ${S.of('of')} ${q.total}',
              style: const TextStyle(
                  color: Tokens.textDim, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: Tokens.s8),
        StepDots(index: q.index, total: q.total),
        const SizedBox(height: Tokens.s20),
        // Question card with the timer (or the verdict) sitting on its edge.
        Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 150),
                margin: const EdgeInsets.only(top: 30),
                padding: const EdgeInsets.fromLTRB(
                    Tokens.s20, Tokens.s48, Tokens.s20, Tokens.s24),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.all(Tokens.r32),
                  boxShadow: [
                    BoxShadow(
                        color: Tokens.shade(Tokens.grape, 0.12),
                        offset: const Offset(0, 6)),
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 24,
                        offset: const Offset(0, 12)),
                  ],
                ),
                child: !_visible
                    ? Bob(
                        child: Text(
                            '👀 ${S.of(q.emojis != null ? 'puzzleComing' : 'questionComing')}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Tokens.inkSoft,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)))
                    : AnimatedOpacity(
                        duration: Tokens.medium,
                        opacity: _visible ? 1 : 0,
                        child: AnimatedScale(
                          duration: Tokens.medium,
                          curve: Curves.easeOutBack,
                          scale: _visible ? 1 : 0.9,
                          child: q.emojis != null
                              ? _EmojiPuzzle(emojis: q.emojis!)
                              : Text(q.prompt,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Tokens.ink,
                                      fontSize: 24,
                                      height: 1.4,
                                      fontWeight: FontWeight.w800)),
                        ),
                      ),
              ),
              if (reveal == null)
                ServerTimerRing(
                    startsAt: q.revealAt,
                    endsAt: q.deadline,
                    size: 64,
                    serverNow: () => widget.session.serverNow)
              else
                _Verdict(points: myPoints ?? 0, answered: chosen != null),
            ]),
        const SizedBox(height: Tokens.s20),
        Expanded(
          child: AnimatedOpacity(
            duration: Tokens.medium,
            opacity: _visible ? 1 : 0,
            child: q.typed
                ? _TypedAnswer(
                    question: q,
                    quiz: quiz,
                    enabled: _visible,
                    onGuess: (text) => widget.session.guess(q.index, text))
                : grid
                ? Column(children: [
                    for (final row in [
                      [0, 1],
                      [2, 3]
                    ]) ...[
                      Expanded(
                        child: Row(children: [
                          Expanded(child: choice(row[0])),
                          const SizedBox(width: Tokens.s12),
                          Expanded(child: choice(row[1])),
                        ]),
                      ),
                      if (row.first == 0) const SizedBox(height: Tokens.s12),
                    ]
                  ])
                : ListView.separated(
                    itemCount: q.choices.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: Tokens.s12),
                    itemBuilder: (_, i) => choice(i),
                  ),
          ),
        ),
        const SizedBox(height: Tokens.s12),
        _ScoreStrip(
            view: widget.view,
            onPlayer: widget.onPlayer,
            points: reveal?.points,
            footer: reveal != null
                ? null
                : q.typed
                    ? '${quiz.answeredCount}/${widget.view.players.length} ${S.of('solvedWord')}'
                    : chosen != null
                        ? '${S.of('yourAnswerSaved')} · ${quiz.answeredCount}/${widget.view.players.length} ${S.of('answered')}'
                        : null),
      ]),
    );
  }
}

/// The emoji puzzle, drawn big. Emoji keep their own left-to-right order.
class _EmojiPuzzle extends StatelessWidget {
  const _EmojiPuzzle({required this.emojis});
  final String emojis;
  @override
  Widget build(BuildContext context) => Semantics(
        label: emojis,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(emojis,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 64, height: 1.15, letterSpacing: 6)),
        ),
      );
}

/// Guess with Emoji, typed mode: the answer box, your wrong guesses (only
/// you see them), the answer's shape after half time, and the answer at the end.
class _TypedAnswer extends StatefulWidget {
  const _TypedAnswer(
      {required this.question,
      required this.quiz,
      required this.enabled,
      required this.onGuess});
  final QuizQuestion question;
  final QuizView quiz;
  final bool enabled;
  final ValueChanged<String> onGuess;
  static const maxGuesses = 3;
  @override
  State<_TypedAnswer> createState() => _TypedAnswerState();
}

class _TypedAnswerState extends State<_TypedAnswer> {
  final _text = TextEditingController();
  String? _pending;

  @override
  void didUpdateWidget(covariant _TypedAnswer old) {
    super.didUpdateWidget(old);
    // The server answered our last guess: clear the box for the next try.
    if (widget.quiz.yourGuesses.length != old.quiz.yourGuesses.length ||
        widget.quiz.yourChoice != null) {
      _pending = null;
      _text.clear();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty || _pending != null) return;
    setState(() => _pending = t);
    Sfx.play('pop', volume: 0.6);
    widget.onGuess(t);
  }

  @override
  Widget build(BuildContext context) {
    final quiz = widget.quiz;
    final reveal = quiz.reveal;
    final guesses = quiz.yourGuesses;
    final left = _TypedAnswer.maxGuesses - guesses.length;
    final solved = quiz.yourChoice != null;

    Widget banner(String text, Color color) => PopIn(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Tokens.s16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: const BorderRadius.all(Tokens.r20),
              border: Border.all(color: color, width: 2),
            ),
            child: Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, height: 1.4)),
          ),
        );

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.question.hint != null && reveal == null) ...[
          Text('${S.of('emojiHint')} 💡',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Tokens.textDim, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          PopIn(
            child: Text(widget.question.hint!,
                key: const Key('emojiHint'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Tokens.sun,
                    fontSize: 26,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: Tokens.s12),
        ],
        if (reveal != null)
          banner('${S.of('emojiAnswerWas')}: ${reveal.answer ?? ''}',
              Tokens.success)
        else if (solved)
          banner(S.of('emojiSolved'), Tokens.success)
        else if (left <= 0)
          banner(S.of('emojiOutOfTries'), Tokens.orange)
        else ...[
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('emojiGuess'),
                controller: _text,
                enabled: widget.enabled && _pending == null,
                maxLength: 60,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                    hintText: S.of('emojiTypeHere'), counterText: ''),
              ),
            ),
            const SizedBox(width: Tokens.s8),
            GameButton(
              label: S.of('emojiSend'),
              expand: false,
              color: Tokens.sun,
              busy: _pending != null,
              onPressed: widget.enabled ? _send : null,
            ),
          ]),
          const SizedBox(height: Tokens.s8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _TypedAnswer.maxGuesses; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(i < left ? '❤️' : '🤍',
                    style: const TextStyle(fontSize: 18)),
              ),
            const SizedBox(width: Tokens.s8),
            Text('$left ${S.of('emojiTriesLeft')}',
                style: const TextStyle(
                    color: Tokens.textDim, fontWeight: FontWeight.w700)),
          ]),
        ],
        if (guesses.isNotEmpty && reveal == null && !solved) ...[
          const SizedBox(height: Tokens.s12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Tokens.s8,
            runSpacing: Tokens.s8,
            children: [
              for (final g in guesses)
                Shake(
                  key: ValueKey(g),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Tokens.s12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Tokens.danger.withValues(alpha: 0.2),
                      borderRadius: const BorderRadius.all(Radius.circular(99)),
                      border: Border.all(color: Tokens.danger),
                    ),
                    child: Text('❌ $g',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.lineThrough)),
                  ),
                ),
            ],
          ),
        ],
      ]),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.points, required this.answered});
  final int points;
  final bool answered;
  @override
  Widget build(BuildContext context) {
    final ok = points > 0;
    final (emoji, text, color) = ok
        ? ('🎉', '${S.of('correct')}  +$points', Tokens.success)
        : answered
            ? ('😅', S.of('wrong'), Tokens.danger)
            : ('⏰', S.of('noAnswer'), Tokens.orange);
    return PopIn(
      from: 0.3,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.all(Radius.circular(99)),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 20)
          ],
        ),
        child: Text('$emoji  $text',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                height: 1.2,
                fontWeight: FontWeight.w800)),
      ),
    );
  }
}

enum _ChoiceState { open, picked, correct, wrong, faded }

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile(
      {super.key,
      required this.label,
      required this.shape,
      required this.text,
      required this.color,
      required this.state,
      this.tall = false,
      this.pickers = const [],
      this.onTap});
  final String label;
  final IconData shape;
  final String text;
  final Color color;
  final _ChoiceState state;
  final bool tall;

  /// Avatars of the players who picked this choice (shown after the reveal).
  final List<String> pickers;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final face = switch (state) {
      _ChoiceState.correct => Tokens.success,
      _ChoiceState.wrong => Tokens.danger,
      _ChoiceState.faded => Color.lerp(color, Tokens.night, 0.7)!,
      _ => color,
    };
    final fg = state == _ChoiceState.faded
        ? Colors.white.withValues(alpha: 0.45)
        : Tokens.onColor(face);
    final picked = state == _ChoiceState.picked;
    final content = AnimatedContainer(
      duration: Tokens.medium,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: state == _ChoiceState.faded ? 2 : 6),
      decoration: BoxDecoration(
        color: Tokens.shade(face, 0.18),
        borderRadius: const BorderRadius.all(Tokens.r24),
        boxShadow: [
          if (picked || state == _ChoiceState.correct)
            BoxShadow(
                color: face.withValues(alpha: 0.7),
                blurRadius: 24,
                spreadRadius: 1),
        ],
      ),
      child: AnimatedContainer(
        duration: Tokens.medium,
        padding: EdgeInsets.symmetric(
            horizontal: Tokens.s16, vertical: tall ? Tokens.s12 : 18),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Tokens.r24),
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Tokens.tint(face, 0.06), face]),
          border: Border.all(
              color:
                  picked ? Colors.white : Colors.white.withValues(alpha: 0.2),
              width: picked ? 4 : 1.5),
        ),
        child: tall
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                _ShapeBadge(shape: shape, state: state, fg: fg),
                const SizedBox(height: Tokens.s8),
                Flexible(
                  child: Text(text,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: fg,
                          fontSize: 20,
                          height: 1.3,
                          fontWeight: FontWeight.w800)),
                ),
              ])
            : Row(children: [
                _ShapeBadge(shape: shape, state: state, fg: fg),
                const SizedBox(width: Tokens.s12),
                Expanded(
                    child: Text(text,
                        style: TextStyle(
                            color: fg,
                            fontSize: 19,
                            height: 1.3,
                            fontWeight: FontWeight.w800))),
              ]),
      ),
    );
    final tile = Semantics(
      button: true,
      label: '$label: $text',
      onTap: onTap,
      excludeSemantics: true,
      child: Shake(
        enabled: state == _ChoiceState.wrong,
        child: AnimatedScale(
          duration: Tokens.medium,
          curve: Curves.easeOutBack,
          scale: picked || state == _ChoiceState.correct
              ? 1.03
              : state == _ChoiceState.faded
                  ? 0.96
                  : 1,
          child:
              onTap == null ? content : Pressable(onTap: onTap, child: content),
        ),
      ),
    );
    if (pickers.isEmpty) return tile;
    return Stack(clipBehavior: Clip.none, fit: StackFit.passthrough, children: [
      tile,
      PositionedDirectional(
        top: -10,
        end: 6,
        child: PopIn(child: _Pickers(avatarIds: pickers)),
      ),
    ]);
  }
}

/// A small overlapping stack of the avatars that picked a choice.
class _Pickers extends StatelessWidget {
  const _Pickers({required this.avatarIds});
  final List<String> avatarIds;
  static const _size = 30.0, _step = 19.0, _max = 4;
  @override
  Widget build(BuildContext context) {
    final shown = avatarIds.take(_max).toList();
    final extra = avatarIds.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    return SizedBox(
      width: _size + _step * (count - 1),
      height: _size,
      child: Stack(children: [
        for (final (i, id) in shown.indexed)
          PositionedDirectional(
            start: i * _step,
            child: Container(
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2)),
              child: ChibiAvatar(avatarId: id, size: _size - 4),
            ),
          ),
        if (extra > 0)
          PositionedDirectional(
            start: shown.length * _step,
            child: Container(
              width: _size,
              height: _size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Tokens.night,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2)),
              child: Text('+$extra',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ),
      ]),
    );
  }
}

class _ShapeBadge extends StatelessWidget {
  const _ShapeBadge(
      {required this.shape, required this.state, required this.fg});
  final IconData shape;
  final _ChoiceState state;
  final Color fg;
  @override
  Widget build(BuildContext context) {
    final icon = switch (state) {
      _ChoiceState.correct => Icons.check_rounded,
      _ChoiceState.wrong => Icons.close_rounded,
      _ => shape,
    };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Icon(icon, color: fg, size: 22),
    );
  }
}

class _ScoreStrip extends StatelessWidget {
  const _ScoreStrip(
      {required this.view, required this.onPlayer, this.points, this.footer});
  final RoomView view;
  final void Function(PublicPlayer) onPlayer;
  final Map<String, int>? points;
  final String? footer;
  @override
  Widget build(BuildContext context) {
    final scores = view.quiz?.scores ?? const {};
    final players = view.players
        .where((p) => scores.containsKey(p.playerId))
        .toList()
      ..sort((a, b) =>
          (scores[b.playerId] ?? 0).compareTo(scores[a.playerId] ?? 0));
    return GlassCard(
      radius: Tokens.r20,
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s8, vertical: 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 46,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final (i, p) in players.indexed)
              Pressable(
                onTap: () => onPlayer(p),
                semanticLabel: '${p.displayName} ${scores[p.playerId] ?? 0}',
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 12, 4),
                  decoration: BoxDecoration(
                    color: p.playerId == view.you
                        ? Tokens.sun.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: const BorderRadius.all(Radius.circular(99)),
                  ),
                  child: Row(children: [
                    Text(i == 0 ? '🥇' : '${i + 1}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 4),
                    ChibiAvatar(
                        avatarId: p.avatarId, size: 32, dimmed: !p.connected),
                    const SizedBox(width: 6),
                    Text('${scores[p.playerId] ?? 0}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    if ((points?[p.playerId] ?? 0) > 0) ...[
                      const SizedBox(width: 4),
                      PopIn(
                        child: Text('+${points![p.playerId]}',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                                color: Tokens.success,
                                fontSize: 13,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ]),
                ),
              ),
          ]),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text('✓ $footer',
                style: const TextStyle(
                    color: Tokens.textDim,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }
}

/* --------------------------------- results --------------------------------- */

class _Results extends StatefulWidget {
  const _Results(
      {super.key,
      required this.view,
      required this.summary,
      required this.onPlayer,
      required this.onRematch,
      required this.canRematch});
  final RoomView view;
  final MatchSummary? summary;
  final void Function(PublicPlayer) onPlayer;
  final VoidCallback onRematch;
  final bool canRematch;

  @override
  State<_Results> createState() => _ResultsState();
}

class _ResultsState extends State<_Results> {
  final _shareKey = GlobalKey();
  bool _sharing = false;

  RoomView get view => widget.view;
  MatchSummary? get summary => widget.summary;
  void Function(PublicPlayer) get onPlayer => widget.onPlayer;

  Future<void> _share(RankingEntry mine, int total) async {
    setState(() => _sharing = true);
    try {
      final boundary = _shareKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final text = S
          .of('shareText')
          .replaceAll('{place}', '${mine.place}')
          .replaceAll('{total}', '$total')
          .replaceAll('{score}', '${mine.score}');
      await SharePlus.instance.share(ShareParams(
        text: text,
        files: [
          XFile.fromData(data!.buffer.asUint8List(),
              mimeType: 'image/png', name: 'sahra-result.png')
        ],
        fileNameOverrides: ['sahra-result.png'],
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
    final ranking = view.quiz!.ranking!;
    final byId = {for (final p in view.players) p.playerId: p};
    final mine = ranking.where((r) => r.playerId == view.you).firstOrNull;
    final won = mine?.place == 1;
    final top = ranking.where((r) => r.place <= 3).take(3).toList();
    final rest = ranking.skip(top.length).toList();
    PublicPlayer? player(String id) => byId[id];

    return Stack(children: [
      ListView(
        padding:
            const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s24),
        children: [
          FadeSlideIn(
            child: Column(children: [
              Text('${S.of('results')} 🏁',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium),
              Text(S.of(won ? 'youWon' : 'nextTime'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Tokens.textDim, fontSize: 16)),
            ]),
          ),
          const SizedBox(height: Tokens.s16),
          _Podium(
              entries: top, player: player, you: view.you, onPlayer: onPlayer),
          for (final (i, r) in rest.indexed)
            FadeSlideIn(
              delay: Duration(milliseconds: 600 + i * 60),
              child: Container(
                margin: const EdgeInsets.only(top: Tokens.s8),
                padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.s16, vertical: Tokens.s8),
                decoration: BoxDecoration(
                  color: r.playerId == view.you
                      ? Tokens.sun.withValues(alpha: 0.2)
                      : Tokens.glass,
                  borderRadius: const BorderRadius.all(Tokens.r16),
                ),
                child: Row(children: [
                  SizedBox(
                      width: 28,
                      child: Text('${r.place}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800))),
                  ChibiAvatar(
                      avatarId: player(r.playerId)?.avatarId ?? 'chibi_base_1',
                      size: 38,
                      expression: ChibiExpression.neutral),
                  const SizedBox(width: Tokens.s12),
                  Expanded(
                      child: Text(player(r.playerId)?.displayName ?? '—',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16))),
                  Text('${r.score}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 18)),
                ]),
              ),
            ),
          if (mine != null && player(mine.playerId) != null) ...[
            const SizedBox(height: Tokens.s20),
            FadeSlideIn(
              delay: const Duration(milliseconds: 650),
              child: RepaintBoundary(
                key: _shareKey,
                child: _ShareCard(
                    entry: mine,
                    player: player(mine.playerId)!,
                    total: ranking.length,
                    questions: view.quiz?.question?.total),
              ),
            ),
            const SizedBox(height: Tokens.s12),
            GameButton(
                key: const Key('shareResult'),
                label: S.of('shareResult'),
                icon: Icons.ios_share_rounded,
                color: Tokens.sky,
                size: GameButtonSize.medium,
                busy: _sharing,
                onPressed: () => _share(mine, ranking.length)),
          ],
          const SizedBox(height: Tokens.s20),
          if (summary != null)
            FadeSlideIn(
              delay: const Duration(milliseconds: 700),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.s8, vertical: Tokens.s16),
                child: Column(children: [
                  if (view.mode != 'practice') ...[
                    Text(S.of('rewards'),
                        style: const TextStyle(
                            color: Tokens.textDim,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: Tokens.s8),
                    Row(children: [
                      Expanded(
                          child: _Stat(
                              icon: '⭐',
                              label: S.of('xp'),
                              value: summary!.xp,
                              color: Tokens.sun)),
                      Expanded(
                          child: _Stat(
                              icon: '🪙',
                              label: S.of('coins'),
                              value: summary!.coins,
                              color: Tokens.orange)),
                      if (summary!.ratingAfter != null)
                        Expanded(
                          child: _Stat(
                            icon: '🏆',
                            label: summary!.provisional
                                ? S.of('provisional')
                                : S.of('rating'),
                            value: summary!.ratingAfter!,
                            plain: true,
                            delta:
                                summary!.ratingAfter! - summary!.ratingBefore!,
                            color: Tokens.sky,
                          ),
                        ),
                    ]),
                  ],
                  for (final n in summary!.notes)
                    if (S.has('note_$n'))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            Tokens.s8, Tokens.s12, Tokens.s8, 0),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('💡'),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(S.of('note_$n'),
                                    style: const TextStyle(
                                        color: Tokens.textDim,
                                        fontSize: 13.5,
                                        height: 1.5)),
                              ),
                            ]),
                      ),
                ]),
              ),
            ),
          const SizedBox(height: Tokens.s24),
          if (widget.canRematch) ...[
            GameButton(
                label: S.of('playAgain'),
                icon: Icons.replay_rounded,
                color: Tokens.sun,
                onPressed: widget.onRematch),
            const SizedBox(height: Tokens.s12),
          ],
          GameButton(
              label: S.of('backHome'),
              icon: Icons.home_rounded,
              color: Tokens.grape,
              onPressed: () => Navigator.of(context).pop()),
        ],
      ),
      if (won) const Positioned.fill(child: Confetti()),
    ]);
  }
}

/// The player's own result, drawn as a card that can be shared as an image.
class _ShareCard extends StatelessWidget {
  const _ShareCard(
      {required this.entry,
      required this.player,
      required this.total,
      this.questions});
  final RankingEntry entry;
  final PublicPlayer player;
  final int total;
  final int? questions;
  @override
  Widget build(BuildContext context) {
    const medals = {1: '🥇', 2: '🥈', 3: '🥉'};
    return Container(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s16, Tokens.s16, 0),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Tokens.r24),
        gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF3A1F86), Tokens.night, Tokens.nightDeep]),
        border: Border.all(color: Tokens.sun.withValues(alpha: 0.6), width: 2),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Logo(size: 22),
              const SizedBox(height: Tokens.s12),
              Text(player.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              Text(
                  '${medals[entry.place] ?? '🎯'} ${S.of('place')} ${entry.place} ${S.of('of')} $total',
                  style: const TextStyle(
                      color: Tokens.sun,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: Tokens.s8),
              Row(children: [
                Text('${entry.score}',
                    style: const TextStyle(
                        fontFamily: Tokens.display,
                        fontSize: 40,
                        height: 1.1,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Text(S.of('points'),
                    style: const TextStyle(
                        color: Tokens.textDim, fontWeight: FontWeight.w700)),
              ]),
              Text(
                  '✅ ${S.of('correctAnswers')}: ${entry.correct}${questions != null ? '/$questions' : ''}',
                  style: const TextStyle(
                      color: Tokens.textDim, fontWeight: FontWeight.w700)),
              const SizedBox(height: Tokens.s8),
              Text(S.of('canYouBeatMe'),
                  style: const TextStyle(
                      color: Tokens.mint,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
        ChibiFullBody(avatarId: player.avatarId, height: 150),
      ]),
    );
  }
}

/// XP / coins / rating earned in a match, with any notes.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final MatchSummary summary;
  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s8, vertical: Tokens.s16),
        child: Column(children: [
          Text(S.of('rewards'),
              style: const TextStyle(
                  color: Tokens.textDim, fontWeight: FontWeight.w700)),
          const SizedBox(height: Tokens.s8),
          Row(children: [
            Expanded(
                child: _Stat(
                    icon: '⭐',
                    label: S.of('xp'),
                    value: summary.xp,
                    color: Tokens.sun)),
            Expanded(
                child: _Stat(
                    icon: '🪙',
                    label: S.of('coins'),
                    value: summary.coins,
                    color: Tokens.orange)),
          ]),
          for (final n in summary.notes)
            if (S.has('note_$n'))
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Tokens.s8, Tokens.s12, Tokens.s8, 0),
                child: Text('💡 ${S.of('note_$n')}',
                    style: const TextStyle(
                        color: Tokens.textDim, fontSize: 13.5, height: 1.5)),
              ),
        ]),
      );
}

class _Podium extends StatelessWidget {
  const _Podium(
      {required this.entries,
      required this.player,
      required this.you,
      required this.onPlayer});
  final List<RankingEntry> entries;
  final PublicPlayer? Function(String) player;
  final String you;
  final void Function(PublicPlayer) onPlayer;

  @override
  Widget build(BuildContext context) {
    // Visual order: 2nd, 1st, 3rd.
    final order = [
      if (entries.length > 1) entries[1],
      if (entries.isNotEmpty) entries[0],
      if (entries.length > 2) entries[2],
    ];
    const heights = {1: 120.0, 2: 88.0, 3: 64.0};
    const colors = {1: Tokens.sun, 2: Color(0xFFC9D3E6), 3: Color(0xFFE59A5C)};
    const medals = {1: '🥇', 2: '🥈', 3: '🥉'};
    return SizedBox(
      height: 290,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, r) in order.indexed)
            Expanded(
              child: FadeSlideIn(
                delay: Duration(
                    milliseconds: 150 + (r.place == 1 ? 300 : i * 120)),
                offset: 60,
                child:
                    Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (r.place == 1)
                    const Bob(
                        child: Text('👑', style: TextStyle(fontSize: 30))),
                  Pressable(
                    onTap: player(r.playerId) == null
                        ? null
                        : () => onPlayer(player(r.playerId)!),
                    child: ChibiAvatar(
                      avatarId: player(r.playerId)?.avatarId ?? 'chibi_base_1',
                      size: r.place == 1 ? 84 : 64,
                      expression: r.place == 1
                          ? ChibiExpression.happy
                          : ChibiExpression.neutral,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(player(r.playerId)?.displayName ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: r.playerId == you ? Tokens.sun : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  Text('${r.score}',
                      style: const TextStyle(
                          color: Tokens.textDim,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const SizedBox(height: 6),
                  Container(
                    height: heights[r.place] ?? 56,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.topCenter,
                    padding: const EdgeInsets.only(top: Tokens.s8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colors[r.place] ?? Tokens.glassStrong,
                            Tokens.shade(colors[r.place] ?? Tokens.night, 0.2),
                          ]),
                      borderRadius:
                          const BorderRadius.vertical(top: Tokens.r20),
                    ),
                    child: Text(medals[r.place] ?? '${r.place}',
                        style: const TextStyle(fontSize: 30)),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color,
      this.plain = false,
      this.delta});
  final String icon, label;
  final int value;
  final Color color;
  final bool plain;
  final int? delta;
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        fontWeight: FontWeight.w800, fontSize: 24, color: color, height: 1.2);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(icon, style: const TextStyle(fontSize: 30)),
      CountUp(value: value, prefix: plain ? '' : '+', style: style),
      if (delta != null)
        Text('${delta! >= 0 ? '+' : ''}$delta',
            textDirection: TextDirection.ltr,
            style: TextStyle(
                color: delta! >= 0 ? Tokens.success : Tokens.coral,
                fontWeight: FontWeight.w800)),
      Text(label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Tokens.textDim, fontSize: 13)),
    ]);
  }
}

/* --------------------------------- phrases --------------------------------- */

class _PhraseBar extends StatelessWidget {
  const _PhraseBar({required this.onSend});
  final void Function(String) onSend;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Tokens.nightDeep.withValues(alpha: 0.85),
          border: const Border(top: BorderSide(color: Tokens.glassBorder)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.s12, vertical: Tokens.s8),
              children: [
                for (final p in _phrases)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Pressable(
                      onTap: () => onSend(p),
                      semanticLabel: S.of('phrase_$p'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Tokens.glass,
                          borderRadius: BorderRadius.all(Radius.circular(99)),
                          border: Border.fromBorderSide(
                              BorderSide(color: Tokens.glassBorder)),
                        ),
                        child: Text(
                            '${_phraseEmoji[p] ?? ''} ${S.of('phrase_$p')}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}
