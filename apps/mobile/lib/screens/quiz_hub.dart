import 'package:flutter/material.dart';
import 'package:sahra_client/sahra_client.dart';

import '../app_state.dart';
import '../config.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'room.dart';

class QuizHubScreen extends StatefulWidget {
  const QuizHubScreen({super.key});
  @override
  State<QuizHubScreen> createState() => _QuizHubScreenState();
}

class _QuizHubScreenState extends State<QuizHubScreen> {
  final _code = TextEditingController();
  String? _busy;
  String? _error;
  int? _durationSec;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).api.games().then((games) {
      final q = games.where((g) => g['id'] == 'quiz').firstOrNull;
      if (mounted && q != null) {
        setState(
            () => _durationSec = (q['expectedDurationSec'] as num).toInt());
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
      await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RoomScreen(session: session)));
    } on ApiException catch (e) {
      setState(() => _error = e.code == 'room_not_found'
          ? '${S.of('roomCode')}: ✗'
          : S.of('error'));
    } catch (e) {
      // Test builds show the technical reason to help testers report issues.
      setState(() => _error = AppConfig.devSignIn ? '${S.of('error')}\n$e' : S.of('error'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.night,
      appBar:
          AppBar(foregroundColor: Colors.white, title: Text(S.of('game_quiz'))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(Tokens.s24), children: [
          const Center(child: Text('🧠', style: TextStyle(fontSize: 72))),
          const SizedBox(height: Tokens.s8),
          Text(S.of('game_quiz_desc'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16)),
          if (_durationSec != null) ...[
            const SizedBox(height: Tokens.s8),
            Center(
                child: Pill(
                    text:
                        '${S.of('expectedDuration')}: ~${(_durationSec! / 60).ceil()} ${S.of('minutes')}',
                    color: Tokens.sun,
                    icon: Icons.timer_outlined)),
          ],
          const SizedBox(height: Tokens.s32),
          GameButton(
            key: const Key('quickPlay'),
            label: S.of('quickPlay'),
            icon: Icons.bolt_rounded,
            color: Tokens.sun,
            busy: _busy == 'quick',
            onPressed: _busy == null
                ? () => _go(
                    'quick',
                    (a) => GameSession.quickPlay(a.api, a.client,
                        gameId: 'quiz', mode: 'casual'))
                : null,
          ),
          const SizedBox(height: Tokens.s12),
          GameButton(
            label: S.of('ranked'),
            icon: Icons.emoji_events_rounded,
            color: Tokens.coral,
            busy: _busy == 'ranked',
            onPressed: _busy == null
                ? () => _go(
                    'ranked',
                    (a) => GameSession.quickPlay(a.api, a.client,
                        gameId: 'quiz', mode: 'ranked'))
                : null,
          ),
          const SizedBox(height: Tokens.s12),
          GameButton(
            key: const Key('createRoom'),
            label: S.of('createRoom'),
            icon: Icons.add_home_rounded,
            color: Tokens.mint,
            busy: _busy == 'create',
            onPressed: _busy == null
                ? () => _go(
                    'create',
                    (a) => GameSession.createPrivate(a.api, a.client,
                        gameId: 'quiz',
                        config: {'questionCount': 10, 'answerSeconds': 15}))
                : null,
          ),
          const SizedBox(height: Tokens.s24),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                textDirection: TextDirection.ltr,
                maxLength: 6,
                decoration: InputDecoration(
                    labelText: S.of('roomCode'), counterText: ''),
              ),
            ),
            const SizedBox(width: Tokens.s12),
            GameButton(
              label: S.of('join'),
              expand: false,
              color: Tokens.sky,
              busy: _busy == 'join',
              onPressed: _busy == null
                  ? () => _go(
                      'join',
                      (a) => GameSession.joinByCode(a.api, a.client,
                          gameId: 'quiz', code: _code.text.trim()))
                  : null,
            ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: Tokens.s16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Tokens.coral)),
          ],
        ]),
      ),
    );
  }
}
