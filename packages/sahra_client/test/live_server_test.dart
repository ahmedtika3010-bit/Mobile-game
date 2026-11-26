// Runs against a real server: SAHRA_SERVER=http://localhost:2567 dart test
// The server must have DEV_AUTH=1 and approved quiz content.
@Tags(['live'])
library;

import 'dart:async';
import 'dart:io';

import 'package:sahra_client/sahra_client.dart';
import 'package:test/test.dart';

void main() {
  final base = Platform.environment['SAHRA_SERVER'];

  Future<SahraApi> player(String name) async {
    final api = SahraApi(Uri.parse(base!));
    await api.signInDev('dart-$name-${DateTime.now().microsecondsSinceEpoch}');
    await api.updateProfile(displayName: name, dateOfBirth: '1994-04-04');
    return api;
  }

  test('private room: create, join by code, play to the end with a reconnect', () async {
    final client = ColyseusClient(Uri.parse(base!));
    final hostApi = await player('host');
    final guestApi = await player('guest');

    final host = await GameSession.createPrivate(hostApi, client,
        gameId: 'quiz', config: {'questionCount': 5, 'answerSeconds': 8});
    final code = (await host.views.firstWhere((v) => v.code != null)).code!;
    final guest = await GameSession.joinByCode(guestApi, client, gameId: 'quiz', code: code);
    await host.views.firstWhere((v) => v.players.length == 2);
    expect(host.view!.commMode, 'normal');

    void autoAnswer(GameSession s) {
      s.views.listen((v) {
        final q = v.quiz?.question;
        if (v.quiz?.stage == 'question' && q != null && v.quiz!.yourChoice == null) {
          final wait = q.revealAt - s.serverNow + 50;
          Timer(Duration(milliseconds: wait < 0 ? 0 : wait), () {
            s.markQuestionShown(q.index);
            s.answer(q.index, 0);
          });
        }
      });
    }

    autoAnswer(host);
    autoAnswer(guest);
    host.start();

    // Drop the guest's connection during question 2; the session reconnects by itself.
    await guest.views.firstWhere((v) => v.quiz?.question?.index == 1);
    final reconnecting = guest.statusChanges.firstWhere((s) => s == ConnectionStatus.reconnecting);
    final back = guest.statusChanges.firstWhere((s) => s == ConnectionStatus.connected);
    await guest.debugDropConnection();
    await reconnecting;
    await back.timeout(const Duration(seconds: 20));

    final summary = await guest.summaries.first.timeout(const Duration(seconds: 90));
    expect(summary.xp, greaterThan(0));
    expect(guest.lastSummary, isNotNull);
    final ranking = host.view!.quiz?.ranking ?? (await host.views.firstWhere((v) => v.quiz?.ranking != null)).quiz!.ranking!;
    expect(ranking, hasLength(2));

    await guest.leave();
    await host.leave();
  }, timeout: const Timeout(Duration(minutes: 3)), skip: base == null ? 'set SAHRA_SERVER to run' : false);
}
