import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sahra_client/sahra_client.dart';

import '../app_state.dart';
import '../config.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'room.dart';

/// Per-game look and private-room defaults for the hub.
class _HubInfo {
  const _HubInfo(this.emoji, this.color, this.privateConfig,
      {this.rules = const []});
  final String emoji;
  final Color color;
  final Map<String, dynamic> privateConfig;
  final List<(String, String)> rules;
}

const _hubs = {
  'quiz':
      _HubInfo('🧠', Tokens.sky, {'questionCount': 10, 'answerSeconds': 15}),
  'spy': _HubInfo('🕵️', Tokens.grape, {}, rules: [
    ('🤫', 'spyRule1'),
    ('❓', 'spyRule2'),
    ('🗳️', 'spyRule3'),
    ('🎯', 'spyRule4'),
  ]),
  'liar': _HubInfo('🤥', Tokens.coral, {}, rules: [
    ('🤫', 'liarRule1'),
    ('✍️', 'liarRule2'),
    ('👀', 'liarRule3'),
    ('🗳️', 'liarRule4'),
  ]),
  'emoji': _HubInfo('😎', Tokens.sun, {
    'questionCount': 10
  }, rules: [
    ('🧩', 'emojiRule1'),
    ('⚡', 'emojiRule2'),
    ('⌨️', 'emojiRule3'),
    ('🔤', 'emojiRule4'),
  ]),
  'draw': _HubInfo('🎨', Tokens.sky, {}, rules: [
    ('✏️', 'drawRule1'),
    ('⚡', 'drawRule2'),
    ('✋', 'drawRule3'),
    ('🙈', 'drawRule4'),
    ('🤖', 'drawRule5'),
  ]),
  'football': _HubInfo('⚽', Tokens.mint, {
    'questionCount': 10
  }, rules: [
    ('🕵️', 'fbRule1'),
    ('🧭', 'fbRule2'),
    ('📅', 'fbRule3'),
    ('🎲', 'fbRule4'),
    ('⚔️', 'fbRule5'),
  ]),
  'memory': _HubInfo('🧩', Tokens.mint, {
    'rounds': 6
  }, rules: [
    ('🃏', 'memRule1'),
    ('🎨', 'memRule2'),
    ('🔍', 'memRule3'),
    ('⏱️', 'memRule4'),
  ]),
  'stop': _HubInfo('🚌', Tokens.orange, {
    'rounds': 3
  }, rules: [
    ('🔤', 'stopRule1'),
    ('✍️', 'stopRule2'),
    ('⭐', 'stopRule3'),
    ('✋', 'stopRule4'),
  ]),
  'who': _HubInfo('👀', Tokens.pink, {
    'questionCount': 8
  }, rules: [
    ('❓', 'whoRule1'),
    ('🤫', 'whoRule2'),
    ('👑', 'whoRule3'),
    ('🏅', 'whoRule4'),
  ]),
};

/// Entry screen of a game: quick play, practice, ranked, private rooms.
/// Modes the server does not offer for a game are not shown.
class GameHubScreen extends StatefulWidget {
  const GameHubScreen({super.key, required this.gameId});
  final String gameId;
  @override
  State<GameHubScreen> createState() => _GameHubScreenState();
}

class _GameHubScreenState extends State<GameHubScreen> {
  final _code = TextEditingController();
  String? _busy;
  String? _error;
  int? _durationSec;
  bool _ranked = false;
  bool _practice = false;
  int _spies = 1;
  String _difficulty = 'medium';
  String _answerMode = 'choices';
  String _memMode = 'mixed';
  String _drawDiff = 'mixed';
  String _drawPlay = 'solo';
  String _drawSecs = '80';
  String _fbMode = 'mixed';
  String _fbDiff = 'mixed';
  String _fbFormat = 'group';

  String get gameId => widget.gameId;
  _HubInfo get info => _hubs[gameId]!;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).api.games().then((games) {
      final g = games.where((g) => g['id'] == gameId).firstOrNull;
      if (mounted && g != null) {
        setState(() {
          _durationSec = (g['expectedDurationSec'] as num).toInt();
          _ranked = (g['capabilities'] as Map?)?['ranked'] == true;
          _practice = g['practice'] == true;
        });
      }
    }).catchError((_) {});
  }

  Future<void> _go(
      String what, Future<GameSession> Function(AppState app) connect) async {
    setState(() {
      _busy = what;
      _error = null;
    });
    final app = AppScope.read(context);
    try {
      final session = await connect(app);
      if (!mounted) return;
      await Navigator.of(context).push(SoftRoute(RoomScreen(session: session)));
    } on ApiException catch (e) {
      setState(() => _error = switch (e.code) {
            'room_not_found' => S.of('roomNotFound'),
            'safe_mode_unavailable' => S.of('safeModeUnavailable'),
            _ => S.of('error'),
          });
    } catch (e) {
      // Test builds show the technical reason to help testers report issues.
      setState(() => _error =
          AppConfig.devSignIn ? '${S.of('error')}\n$e' : S.of('error'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final idle = _busy == null;
    return NightScaffold(
      glow: info.color,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Tokens.s20, Tokens.s8, Tokens.s20, Tokens.s32),
        children: [
          Center(
            child: Bob(
              child: GameIcon(emoji: info.emoji, color: info.color, size: 104),
            ),
          ),
          const SizedBox(height: Tokens.s16),
          Text(S.of('game_$gameId'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: Tokens.s4),
          Text(S.of('game_${gameId}_desc'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Tokens.textDim, fontSize: 16)),
          if (_durationSec != null) ...[
            const SizedBox(height: Tokens.s12),
            Center(
                child: Pill(
                    text:
                        '${S.of('expectedDuration')}: ~${(_durationSec! / 60).ceil()} ${S.of('minutes')}',
                    color: Tokens.sun,
                    emoji: '⏱️')),
          ],
          const SizedBox(height: Tokens.s24),
          FadeSlideIn(
            child: _ModeCard(
              key: const Key('quickPlay'),
              emoji: '⚡',
              title: S.of('quickPlay'),
              subtitle: S.of('quickPlayDesc'),
              color: Tokens.sun,
              primary: true,
              busy: _busy == 'quick',
              onTap: idle
                  ? () => _go(
                      'quick',
                      (a) => GameSession.quickPlay(a.api, a.client,
                          gameId: gameId, mode: 'casual'))
                  : null,
            ),
          ),
          if (_practice) ...[
            const SizedBox(height: Tokens.s12),
            FadeSlideIn(
              delay: const Duration(milliseconds: 35),
              child: _ModeCard(
                key: const Key('practice'),
                emoji: '🤖',
                title: S.of('practice'),
                subtitle: S.of('practiceDesc'),
                color: Tokens.grape,
                busy: _busy == 'practice',
                onTap: idle
                    ? () => _go(
                        'practice',
                        (a) => GameSession.practice(a.api, a.client,
                            gameId: gameId, config: info.privateConfig))
                    : null,
              ),
            ),
          ],
          if (_ranked) ...[
            const SizedBox(height: Tokens.s12),
            FadeSlideIn(
              delay: const Duration(milliseconds: 70),
              child: _ModeCard(
                emoji: '🏆',
                title: S.of('ranked'),
                subtitle: S.of('rankedDesc'),
                color: Tokens.coral,
                busy: _busy == 'ranked',
                onTap: idle
                    ? () => _go(
                        'ranked',
                        (a) => GameSession.quickPlay(a.api, a.client,
                            gameId: gameId, mode: 'ranked'))
                    : null,
              ),
            ),
          ],
          const SizedBox(height: Tokens.s12),
          FadeSlideIn(
            delay: const Duration(milliseconds: 140),
            child: _ModeCard(
              key: const Key('createRoom'),
              emoji: '🏠',
              title: S.of('createRoom'),
              subtitle: S.of('createRoomDesc'),
              color: Tokens.mint,
              busy: _busy == 'create',
              onTap: idle
                  ? () => _go(
                      'create',
                      (a) => GameSession.createPrivate(a.api, a.client,
                              gameId: gameId,
                              config: {
                                ...info.privateConfig,
                                if (gameId == 'spy') 'spies': _spies,
                                if (gameId == 'liar' ||
                                    gameId == 'emoji' ||
                                    gameId == 'memory')
                                  'difficulty': _difficulty,
                                if (gameId == 'memory') 'mode': _memMode,
                                if (gameId == 'draw') ...{
                                  'difficulty': _drawDiff,
                                  'teams': _drawPlay == 'teams',
                                  'drawSeconds': int.parse(_drawSecs),
                                },
                                if (gameId == 'emoji')
                                  'answerMode': _answerMode,
                                if (gameId == 'football') ...{
                                  'modes': _fbMode,
                                  'difficulty': _fbDiff,
                                  'duel': _fbFormat == 'duel',
                                },
                              }))
                  : null,
            ),
          ),
          if (gameId == 'spy') ...[
            const SizedBox(height: Tokens.s8),
            _SpyCountPicker(
                value: _spies, onChanged: (n) => setState(() => _spies = n)),
          ],
          if (gameId == 'liar' || gameId == 'emoji' || gameId == 'memory') ...[
            const SizedBox(height: Tokens.s8),
            _DifficultyPicker(
                value: _difficulty,
                hint: gameId == 'liar' ? 'liarDifficultyHint' : null,
                onChanged: (d) => setState(() => _difficulty = d)),
          ],
          if (gameId == 'memory') ...[
            const SizedBox(height: Tokens.s8),
            _ChipPicker(
                label: S.of('memModeLabel'),
                options: const {
                  'mixed': '🎲',
                  'cards': '🃏',
                  'sequence': '🎨',
                  'spot': '🔍'
                },
                textOf: (m) => S.of('mem_$m'),
                value: _memMode,
                onChanged: (m) => setState(() => _memMode = m)),
          ],
          if (gameId == 'draw') ...[
            const SizedBox(height: Tokens.s8),
            _ChipPicker(
                label: S.of('drawDiffLabel'),
                options: const {
                  'mixed': '🎲',
                  'easy': '🙂',
                  'medium': '😎',
                  'hard': '🔥'
                },
                textOf: (d) => S.of('drawDiff_$d'),
                value: _drawDiff,
                onChanged: (d) => setState(() => _drawDiff = d)),
            const SizedBox(height: Tokens.s8),
            _ChipPicker(
                label: S.of('drawTeamsLabel'),
                options: const {'solo': '🙋', 'teams': '🤝'},
                textOf: (m) => S.of(m == 'teams' ? 'drawTeams' : 'drawSolo'),
                value: _drawPlay,
                onChanged: (m) => setState(() => _drawPlay = m)),
            const SizedBox(height: Tokens.s8),
            _ChipPicker(
                label: S.of('drawTimeLabel'),
                options: const {'60': '⏱️', '80': '⏱️', '100': '⏱️'},
                textOf: (n) => '$n ${S.of('drawSecs')}',
                value: _drawSecs,
                onChanged: (n) => setState(() => _drawSecs = n)),
          ],
          if (gameId == 'football') ...[
            const SizedBox(height: Tokens.s8),
            _ChipPicker(
                label: S.of('fbModeLabel'),
                options: const {
                  'mixed': '🎲',
                  'player': '🕵️',
                  'career': '🧭',
                  'shared': '🤝',
                  'transfer': '🔁',
                  'history': '📜'
                },
                textOf: (m) => S.of('fb_mode_$m'),
                value: _fbMode,
                onChanged: (m) => setState(() => _fbMode = m)),
            const SizedBox(height: Tokens.s8),
            _ChipPicker(
                label: S.of('fbDiffLabel'),
                options: const {
                  'mixed': '🎲',
                  'easy': '🙂',
                  'medium': '😎',
                  'hard': '🔥'
                },
                textOf: (d) => S.of('drawDiff_$d'),
                value: _fbDiff,
                onChanged: (d) => setState(() => _fbDiff = d)),
            const SizedBox(height: Tokens.s8),
            _ChipPicker(
                label: S.of('fbFormatLabel'),
                options: const {'group': '👥', 'duel': '⚔️'},
                textOf: (m) => S.of(m == 'duel' ? 'fbDuel' : 'fbGroup'),
                value: _fbFormat,
                onChanged: (m) => setState(() => _fbFormat = m)),
          ],
          if (gameId == 'emoji') ...[
            const SizedBox(height: Tokens.s8),
            _AnswerModePicker(
                value: _answerMode,
                onChanged: (m) => setState(() => _answerMode = m)),
          ],
          const SizedBox(height: Tokens.s24),
          FadeSlideIn(
            delay: const Duration(milliseconds: 210),
            child: GlassCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Text('🎟️', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: Tokens.s8),
                      Text(S.of('haveCode'),
                          style: Theme.of(context).textTheme.titleMedium),
                    ]),
                    const SizedBox(height: Tokens.s12),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _code,
                          textCapitalization: TextCapitalization.characters,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.center,
                          maxLength: 6,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp('[A-Za-z0-9]')),
                            TextInputFormatter.withFunction((o, n) =>
                                n.copyWith(text: n.text.toUpperCase())),
                          ],
                          style: const TextStyle(
                              fontFamily: Tokens.body,
                              fontSize: 22,
                              letterSpacing: 6,
                              fontWeight: FontWeight.w900),
                          decoration: InputDecoration(
                              hintText: 'ABC123',
                              hintStyle: const TextStyle(
                                  letterSpacing: 6,
                                  color: Tokens.textFaint,
                                  fontFamily: Tokens.body),
                              semanticCounterText: '',
                              labelText: S.of('roomCode'),
                              counterText: ''),
                        ),
                      ),
                      const SizedBox(width: Tokens.s12),
                      GameButton(
                        label: S.of('join'),
                        expand: false,
                        color: Tokens.sky,
                        busy: _busy == 'join',
                        onPressed: idle
                            ? () => _go(
                                'join',
                                (a) => GameSession.joinByCode(a.api, a.client,
                                    gameId: gameId, code: _code.text.trim()))
                            : null,
                      ),
                    ]),
                  ]),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Tokens.s16),
            Shake(
              key: ValueKey(_error),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Tokens.coral, fontWeight: FontWeight.w700)),
            ),
          ],
          if (info.rules.isNotEmpty) ...[
            const SizedBox(height: Tokens.s24),
            FadeSlideIn(
              delay: const Duration(milliseconds: 260),
              child: GlassCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('📜 ${S.of('howToPlay')}',
                          style: Theme.of(context).textTheme.titleMedium),
                      for (final (emoji, key) in info.rules)
                        Padding(
                          padding: const EdgeInsets.only(top: Tokens.s12),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(emoji,
                                    style: const TextStyle(fontSize: 20)),
                                const SizedBox(width: Tokens.s12),
                                Expanded(
                                  child: Text(S.of(key),
                                      style: const TextStyle(
                                          color: Tokens.textDim,
                                          fontSize: 15,
                                          height: 1.5)),
                                ),
                              ]),
                        ),
                    ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpyCountPicker extends StatelessWidget {
  const _SpyCountPicker({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(S.of('spyCount'),
              style: const TextStyle(
                  color: Tokens.textDim, fontWeight: FontWeight.w700)),
        ),
        for (final n in const [1, 2])
          Padding(
            padding: const EdgeInsetsDirectional.only(start: Tokens.s8),
            child: Pressable(
              onTap: () => onChanged(n),
              semanticLabel: '${S.of('spyCount')} $n',
              child: AnimatedContainer(
                duration: Tokens.fast,
                padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.s12, vertical: 6),
                decoration: BoxDecoration(
                  color: value == n ? Tokens.mint : Tokens.glass,
                  borderRadius: const BorderRadius.all(Radius.circular(99)),
                  border: Border.all(color: Tokens.glassBorder),
                ),
                child: Text('🕵️ × $n',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: value == n ? Tokens.ink : Colors.white)),
              ),
            ),
          ),
      ]);
}

/// A labelled row of choice chips (wraps on small screens).
class _ChipPicker extends StatelessWidget {
  const _ChipPicker(
      {required this.label,
      required this.options,
      required this.textOf,
      required this.value,
      required this.onChanged});
  final String label;
  final Map<String, String> options; // value -> emoji
  final String Function(String) textOf;
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label,
            style: const TextStyle(
                color: Tokens.textDim, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: Tokens.s8, runSpacing: Tokens.s8, children: [
          for (final e in options.entries)
            Pressable(
              key: Key('chip_${e.key}'),
              onTap: () => onChanged(e.key),
              semanticLabel: '$label ${textOf(e.key)}',
              child: AnimatedContainer(
                duration: Tokens.fast,
                padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.s12, vertical: 6),
                decoration: BoxDecoration(
                  color: value == e.key ? Tokens.mint : Tokens.glass,
                  borderRadius: const BorderRadius.all(Radius.circular(99)),
                  border: Border.all(color: Tokens.glassBorder),
                ),
                child: Text('${e.value} ${textOf(e.key)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: value == e.key ? Tokens.ink : Colors.white)),
              ),
            ),
        ]),
      ]);
}

/// Private Guess with Emoji rooms: pick from choices, or type the answer.
class _AnswerModePicker extends StatelessWidget {
  const _AnswerModePicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  static const _emoji = {'choices': '🔘', 'typed': '⌨️'};
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(S.of('answerMode'),
                style: const TextStyle(
                    color: Tokens.textDim, fontWeight: FontWeight.w700)),
          ),
          for (final m in const ['choices', 'typed'])
            Padding(
              padding: const EdgeInsetsDirectional.only(start: Tokens.s8),
              child: Pressable(
                key: Key('answerMode_$m'),
                onTap: () => onChanged(m),
                semanticLabel: '${S.of('answerMode')} ${S.of('answerMode_$m')}',
                child: AnimatedContainer(
                  duration: Tokens.fast,
                  padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.s12, vertical: 6),
                  decoration: BoxDecoration(
                    color: value == m ? Tokens.mint : Tokens.glass,
                    borderRadius: const BorderRadius.all(Radius.circular(99)),
                    border: Border.all(color: Tokens.glassBorder),
                  ),
                  child: Text('${_emoji[m]} ${S.of('answerMode_$m')}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: value == m ? Tokens.ink : Colors.white)),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        Text(S.of('answerModeHint'),
            style: const TextStyle(color: Tokens.textFaint, fontSize: 12.5)),
      ]);
}

class _DifficultyPicker extends StatelessWidget {
  const _DifficultyPicker(
      {required this.value, required this.onChanged, this.hint});
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  static const _emoji = {'easy': '🌱', 'medium': '🔥', 'hard': '🌶️'};
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(S.of('difficulty'),
                style: const TextStyle(
                    color: Tokens.textDim, fontWeight: FontWeight.w700)),
          ),
          for (final d in const ['easy', 'medium', 'hard'])
            Padding(
              padding: const EdgeInsetsDirectional.only(start: Tokens.s8),
              child: Pressable(
                onTap: () => onChanged(d),
                semanticLabel: '${S.of('difficulty')} ${S.of('diff_$d')}',
                child: AnimatedContainer(
                  duration: Tokens.fast,
                  padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.s12, vertical: 6),
                  decoration: BoxDecoration(
                    color: value == d ? Tokens.mint : Tokens.glass,
                    borderRadius: const BorderRadius.all(Radius.circular(99)),
                    border: Border.all(color: Tokens.glassBorder),
                  ),
                  child: Text('${_emoji[d]} ${S.of('diff_$d')}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: value == d ? Tokens.ink : Colors.white)),
                ),
              ),
            ),
        ]),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(S.of(hint!),
              style: const TextStyle(color: Tokens.textFaint, fontSize: 12.5)),
        ],
      ]);
}

class _ModeCard extends StatelessWidget {
  const _ModeCard(
      {super.key,
      required this.emoji,
      required this.title,
      required this.subtitle,
      required this.color,
      required this.onTap,
      this.primary = false,
      this.busy = false});
  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Tokens.onColor(color) : Colors.white;
    final enabled = onTap != null || busy;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: title,
      hint: subtitle,
      onTap: onTap,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(Tokens.s16),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Tokens.r24),
              gradient: primary
                  ? Tokens.gradient(Tokens.tint(color, 0.05), Tokens.orange)
                  : LinearGradient(colors: [
                      color.withValues(alpha: 0.22),
                      color.withValues(alpha: 0.08)
                    ]),
              border: Border.all(
                  color: primary
                      ? Colors.white.withValues(alpha: 0.35)
                      : color.withValues(alpha: 0.4),
                  width: 1.5),
              boxShadow: primary
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.4),
                          blurRadius: 24,
                          offset: const Offset(0, 10))
                    ]
                  : null,
            ),
            child: Row(children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: primary
                      ? Colors.white.withValues(alpha: 0.35)
                      : color.withValues(alpha: 0.25),
                  borderRadius: const BorderRadius.all(Tokens.r16),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 30)),
              ),
              const SizedBox(width: Tokens.s16),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: fg,
                              fontSize: 20,
                              height: 1.25,
                              fontWeight: FontWeight.w800)),
                      Text(subtitle,
                          style: TextStyle(
                              color: fg.withValues(alpha: 0.75),
                              fontSize: 13.5,
                              height: 1.4,
                              fontWeight: FontWeight.w600)),
                    ]),
              ),
              const SizedBox(width: Tokens.s8),
              if (busy)
                SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 3, color: fg))
              else
                Icon(Icons.arrow_forward_ios_rounded,
                    color: fg.withValues(alpha: 0.7), size: 18),
            ]),
          ),
        ),
      ),
    );
  }
}
