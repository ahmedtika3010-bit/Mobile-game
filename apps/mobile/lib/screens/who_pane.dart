import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sahra_client/sahra_client.dart';

import '../design/chibi_avatar.dart';
import '../design/sfx.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'spy_pane.dart' show PartyPlayerGrid;

const _catEmoji = {
  'funny': '😂',
  'friends': '🤝',
  'everyday': '☕',
  'personality': '✨',
};
const _titleEmoji = {
  'funny': '😂',
  'friends': '❤️',
  'everyday': '☕',
  'personality': '✨',
  'mystery': '🧩',
};

/// The live "Who Among Us?" match: anonymous vote, then a gentle reveal.
class WhoPane extends StatefulWidget {
  const WhoPane(
      {super.key,
      required this.view,
      required this.session,
      required this.bubbles});
  final RoomView view;
  final GameSession session;
  final Map<String, String> bubbles;

  @override
  State<WhoPane> createState() => _WhoPaneState();
}

class _WhoPaneState extends State<WhoPane> {
  int _stageStart = 0;
  String _stageKey = '';
  String? _selected;
  bool _sent = false;

  WhoView get g => widget.view.who!;
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
  void didUpdateWidget(WhoPane old) {
    super.didUpdateWidget(old);
    _syncStage();
  }

  void _syncStage() {
    final key = '${g.index}-${g.stage}';
    if (key == _stageKey) return;
    final previous = _stageKey;
    _stageKey = key;
    _stageStart = widget.session.serverNow;
    _sent = false;
    _selected = null;
    if (previous.isEmpty) return;
    if (g.stage == 'vote') Sfx.play('whoosh', volume: 0.6);
    if (g.stage == 'reveal') {
      final picked = g.reveal?.picks.contains(you) == true;
      Sfx.play(picked ? 'win' : 'pop', volume: 0.6);
      if (picked) HapticFeedback.mediumImpact();
    }
  }

  void _send(String? target) {
    if (_sent) return;
    setState(() => _sent = true);
    Sfx.play('pop', volume: 0.6);
    if (target == null) {
      widget.session.whoSkip(g.index);
    } else {
      widget.session.whoVote(g.index, target);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, Tokens.s8),
        child: Column(children: [
          Row(children: [
            Pill(
                text:
                    '${S.of('questionOf')} ${g.index} ${S.of('of')} ${g.total}',
                color: Tokens.pink,
                emoji: '👀'),
            const Spacer(),
            ServerTimerRing(
                startsAt: _stageStart,
                endsAt: g.stageEndsAt,
                size: 54,
                serverNow: () => widget.session.serverNow),
          ]),
          const SizedBox(height: Tokens.s12),
          Expanded(
            child: AnimatedSwitcher(
              duration: Tokens.medium,
              child: KeyedSubtree(
                  key: ValueKey(_stageKey),
                  child: g.stage == 'reveal' ? _reveal() : _vote()),
            ),
          ),
        ]),
      );

  Widget _questionCard() => PopIn(
        from: 0.8,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Tokens.s20),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Tokens.r24),
            gradient: Tokens.gradient(Tokens.pink, Tokens.grape),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                  color: Tokens.pink.withValues(alpha: 0.4), blurRadius: 24),
            ],
          ),
          child: Column(children: [
            Text(_catEmoji[g.category] ?? '👀',
                style: const TextStyle(fontSize: 34)),
            const SizedBox(height: 4),
            Text(g.questionText ?? '',
                key: const Key('whoQuestion'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    height: 1.4,
                    fontWeight: FontWeight.w800)),
          ]),
        ),
      );

  Widget _vote() {
    final done = g.yourChoice != null || _sent;
    return Column(children: [
      _questionCard(),
      const SizedBox(height: Tokens.s12),
      Text(S.of(done ? 'whoVoteSent' : 'whoVoteHint'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Tokens.textDim, height: 1.4)),
      const SizedBox(height: Tokens.s12),
      Expanded(
        child: SingleChildScrollView(
          child: PartyPlayerGrid(
            players: widget.view.players,
            you: you,
            bubbles: widget.bubbles,
            selected:
                g.yourChoice == 'skip' ? null : (g.yourChoice ?? _selected),
            disabledId: you,
            onTap: done
                ? null
                : (p) {
                    if (p.playerId == you) return;
                    HapticFeedback.selectionClick();
                    setState(() => _selected = p.playerId);
                  },
          ),
        ),
      ),
      if (done)
        Bob(
          child: Text('⏳ ${S.of('waitingOthers')} ${g.answeredCount}/$n',
              style: const TextStyle(
                  color: Tokens.textDim,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        )
      else
        Row(children: [
          Expanded(
            flex: 2,
            child: GameButton(
              key: const Key('whoVote'),
              label: S.of('whoVoteButton'),
              icon: Icons.how_to_vote,
              color: Tokens.pink,
              onPressed: _selected == null ? null : () => _send(_selected),
            ),
          ),
          const SizedBox(width: Tokens.s8),
          Expanded(
            child: GameButton(
              key: const Key('whoSkip'),
              label: S.of('skip'),
              color: Tokens.glassStrong,
              onPressed: () => _send(null),
            ),
          ),
        ]),
    ]);
  }

  Widget _reveal() {
    final r = g.reveal;
    if (r == null) return const SizedBox.shrink();
    return ListView(children: [
      Text(g.questionText ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Tokens.textDim,
              fontSize: 17,
              height: 1.4,
              fontWeight: FontWeight.w700)),
      const SizedBox(height: Tokens.s16),
      if (r.kind == 'pick') ...[
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Tokens.s24,
          children: [
            for (final id in r.picks)
              PopIn(
                child: Column(children: [
                  Stack(clipBehavior: Clip.none, children: [
                    Bob(
                        child: ChibiFullBody(
                            avatarId: _player(id)?.avatarId ?? '',
                            height: r.picks.length > 1 ? 150 : 190)),
                    const PositionedDirectional(
                        top: -8,
                        end: -4,
                        child: Text('👑', style: TextStyle(fontSize: 38))),
                  ]),
                  const SizedBox(height: Tokens.s8),
                  Text(
                      id == you
                          ? S.of('you')
                          : (_player(id)?.displayName ?? '—'),
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800)),
                  if (r.counts?[id] case final c?)
                    Text('$c ${S.of('votesWord')}',
                        style: const TextStyle(
                            color: Tokens.sun, fontWeight: FontWeight.w800)),
                ]),
              ),
          ],
        ),
        const SizedBox(height: Tokens.s12),
        Text(S.of(r.picks.length > 1 ? 'whoTie' : 'whoMostSaid'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Tokens.pink, fontSize: 18, fontWeight: FontWeight.w800)),
      ] else
        PopIn(
          child: GlassCard(
            child: Column(children: [
              Text(r.kind == 'too_few' ? '🤫' : '🌈',
                  style: const TextStyle(fontSize: 64)),
              const SizedBox(height: Tokens.s8),
              Text(S.of(r.kind == 'too_few' ? 'whoTooFew' : 'whoSpread'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 19, height: 1.4, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
    ]);
  }
}

/// End of a Who Among Us match: a friendly group summary, no ranking.
class WhoResults extends StatelessWidget {
  const WhoResults(
      {super.key,
      required this.view,
      required this.rewards,
      required this.actions});
  final RoomView view;
  final Widget rewards;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final f = view.who!.final_!;
    final me = view.you;
    final byId = {for (final p in view.players) p.playerId: p};
    return Stack(children: [
      ListView(
        padding:
            const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s24),
        children: [
          FadeSlideIn(
            child: Column(children: [
              Text(S.of('whoDone'),
                  key: const Key('whoResultTitle'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: Tokens.s8),
              Wrap(
                  alignment: WrapAlignment.center,
                  spacing: Tokens.s8,
                  runSpacing: Tokens.s8,
                  children: [
                    Pill(
                        text: '${f.questions} ${S.of('questionsWord')}',
                        emoji: '❓',
                        color: Tokens.sky),
                    Pill(
                        text: '${f.votesCast} ${S.of('votesWord')}',
                        emoji: '🗳️',
                        color: Tokens.pink),
                    Pill(
                        text: '${f.skips} ${S.of('skipsWord')}',
                        emoji: '⏭️',
                        color: Tokens.sun),
                  ]),
            ]),
          ),
          const SizedBox(height: Tokens.s20),
          Text('🏅 ${S.of('whoTitles')}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Tokens.s8),
          for (final p in view.players)
            if (f.titles[p.playerId] case final t?)
              FadeSlideIn(
                child: Container(
                  margin: const EdgeInsets.only(bottom: Tokens.s8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.s12, vertical: 8),
                  decoration: BoxDecoration(
                    color: p.playerId == me
                        ? Tokens.pink.withValues(alpha: 0.18)
                        : Tokens.glass,
                    borderRadius: const BorderRadius.all(Tokens.r16),
                    border: Border.all(color: Tokens.glassBorder),
                  ),
                  child: Row(children: [
                    ChibiAvatar(avatarId: p.avatarId, size: 40),
                    const SizedBox(width: Tokens.s8),
                    Expanded(
                      child: Text(
                          p.playerId == me
                              ? '${p.displayName} (${S.of('you')})'
                              : p.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    Text('${_titleEmoji[t] ?? '✨'} ${S.of('whoTitle_$t')}',
                        style: const TextStyle(
                            color: Tokens.sun, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
          if (f.highlights.isNotEmpty) ...[
            const SizedBox(height: Tokens.s12),
            Text('📸 ${S.of('whoHighlights')}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Tokens.s8),
            for (final h in f.highlights)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GlassCard(
                  radius: Tokens.r16,
                  padding: const EdgeInsets.all(Tokens.s8),
                  child: Row(children: [
                    Expanded(
                      child: Text(h.text,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: Tokens.s8),
                    for (final id in h.picks)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 4),
                        child: ChibiAvatar(
                            avatarId: byId[id]?.avatarId ?? '', size: 32),
                      ),
                  ]),
                ),
              ),
          ],
          const SizedBox(height: Tokens.s20),
          rewards,
          const SizedBox(height: Tokens.s24),
          ...actions,
        ],
      ),
      const Positioned.fill(child: IgnorePointer(child: Confetti())),
    ]);
  }
}
