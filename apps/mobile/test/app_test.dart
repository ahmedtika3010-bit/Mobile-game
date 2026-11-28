import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahra/app_state.dart';
import 'package:sahra/design/widgets.dart';
import 'package:sahra/main.dart';
import 'package:sahra/screens/onboarding.dart';
import 'package:sahra/screens/sign_in.dart';
import 'package:sahra_client/sahra_client.dart';

AppState _state() => AppState(
      api: SahraApi(Uri.parse('http://localhost:1'), store: MemoryTokenStore()),
      client: ColyseusClient(Uri.parse('http://localhost:1')),
    )..loading = false;

/// The background and characters animate forever, so pump fixed frames
/// instead of waiting for animations to settle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('home is right-to-left and lets guests browse games',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 16000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SahraApp(state: _state()));
    await _settle(tester);
    expect(Directionality.of(tester.element(find.text('تحدي المعلومات'))),
        TextDirection.rtl);
    expect(find.text('تحدي المعلومات'), findsOneWidget);
    // The other three games are visible but clearly not playable yet.
    expect(find.textContaining('قريباً'), findsNothing);
  });

  testWidgets('playing without an account asks the guest to sign in',
      (tester) async {
    await tester.pumpWidget(SahraApp(state: _state()));
    await _settle(tester);
    await tester.tap(find.text('العب دلوقتي').first);
    await _settle(tester);
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('onboarding needs a name and a full date of birth',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final state = _state()
      ..user = UserProfile.fromJson({
        'id': 'u1',
        'displayName': null,
        'avatarId': 'chibi_base_1',
        'ageBand': 'unknown',
        'onboarded': false,
        'status': 'active',
      });
    await tester.pumpWidget(AppScope(
        state: state,
        child: const MaterialApp(
            home: Directionality(
                textDirection: TextDirection.rtl, child: OnboardingScreen()))));
    await _settle(tester);
    Finder submit() => find.byKey(const Key('onboardSubmit'));
    VoidCallback? onPressed() => tester.widget<GameButton>(submit()).onPressed;
    expect(onPressed(), isNull);
    await tester.enterText(find.byKey(const Key('displayName')), 'سارة');
    await tester.pump();
    expect(onPressed(), isNull, reason: 'date of birth still missing');
  });
}
