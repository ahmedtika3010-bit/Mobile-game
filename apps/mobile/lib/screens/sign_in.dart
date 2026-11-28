import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sahra_client/sahra_client.dart';

import '../app_state.dart';
import '../auth/social_auth.dart';
import '../config.dart';
import '../design/chibi_avatar.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'onboarding.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _devName = TextEditingController();
  final _inviteCode = TextEditingController();

  /// A random key generated once and kept on this device. The server only
  /// stores its hash, and it is the only way to sign back into the account.
  static Future<String> _deviceKey() async {
    const store = FlutterSecureStorage();
    var key = await store.read(key: 'tester_device_key');
    if (key == null || key.length < 32) {
      final r = Random.secure();
      key = List.generate(
          32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await store.write(key: 'tester_device_key', value: key);
    }
    return key;
  }

  void _testerSignIn(AppState app) {
    final code = _inviteCode.text.trim();
    if (code.isEmpty) return;
    _run(() async => app.api.signInTester(code, await _deviceKey()));
  }

  bool _busy = false;
  String? _error;

  Future<void> _run(Future<dynamic> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = AppScope.read(context);
    try {
      final profile = await f();
      await app.afterSignIn(profile);
      if (!mounted) return;
      if (app.canPlay) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context)
            .pushReplacement(SoftRoute(const OnboardingScreen()));
      }
    } on NotConfigured {
      setState(() => _error = S.of('providerNotConfigured'));
    } on ApiException catch (e) {
      setState(() => _error = switch (e.code) {
            'wrong_invite_code' => S.of('testerWrongCode'),
            'too_many_attempts' => S.of('testerTooMany'),
            _ when e.status >= 500 => S.of('testerServerWaking'),
            _ => S.of('error'),
          });
    } catch (_) {
      setState(() => _error =
          S.of(AppConfig.testerSignIn ? 'testerServerWaking' : 'error'));
      setState(() => _error = S.of('error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return NightScaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Tokens.s24, Tokens.s8, Tokens.s24, Tokens.s32),
        children: [
          const SizedBox(height: Tokens.s16),
          // A little crowd of characters waiting for you.
          SizedBox(
            height: 190,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, id) in const [
                  'chibi_p_layla',
                  'chibi_p_youssef',
                  'chibi_p_nour',
                  'chibi_p_karim'
                ].indexed)
                  Flexible(
                    child: Bob(
                      phase: i * 0.22,
                      amplitude: 5,
                      child: ChibiFullBody(
                          avatarId: id, height: i == 1 || i == 2 ? 180 : 150),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s24),
          const Center(child: Logo(size: 44)),
          const SizedBox(height: Tokens.s8),
          Text(S.of('signInTitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18, color: Tokens.textDim, height: 1.5)),
          const SizedBox(height: Tokens.s32),
          if (AppConfig.testerSignIn) ...[
            FadeSlideIn(child: _testerCard(app)),
            const SizedBox(height: Tokens.s16),
          ],
          if (!AppConfig.testerSignIn || SocialAuth.googleAvailable) ...[
            FadeSlideIn(
              child: GameButton(
                label: S.of('signInGoogle'),
                color: Colors.white,
                leading: const _GoogleMark(),
                busy: _busy,
                onPressed: () => _run(() async =>
                    app.api.signInWithGoogle(await SocialAuth.googleIdToken())),
              ),
            ),
            const SizedBox(height: Tokens.s12),
          ],
          if (!AppConfig.testerSignIn || SocialAuth.appleAvailable)
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: GameButton(
                label: S.of('signInApple'),
                color: const Color(0xFF15121F),
                icon: Icons.apple_rounded,
                busy: _busy,
                onPressed: () => _run(() async =>
                    app.api.signInWithApple(await SocialAuth.appleIdToken())),
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
          const SizedBox(height: Tokens.s16),
          Text(S.of('signInPrivacy'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Tokens.textFaint, fontSize: 13)),
          if (AppConfig.devSignIn) ...[
            const SizedBox(height: Tokens.s32),
            GlassCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Icon(Icons.science_rounded,
                          color: Tokens.textDim, size: 18),
                      const SizedBox(width: 6),
                      Text(S.of('devOnly'),
                          style: const TextStyle(
                              color: Tokens.textDim,
                              fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: Tokens.s12),
                    TextField(
                      key: const Key('devName'),
                      controller: _devName,
                      decoration: InputDecoration(labelText: S.of('devName')),
                    ),
                    const SizedBox(height: Tokens.s12),
                    GameButton(
                      key: const Key('devSignIn'),
                      label: S.of('signInDev'),
                      color: Tokens.grape,
                      size: GameButtonSize.medium,
                      busy: _busy,
                      onPressed: () {
                        final name = _devName.text.trim();
                        if (name.isNotEmpty) {
                          _run(() => app.api.signInDev(name));
                        }
                      },
                    ),
                  ]),
            ),
          ],
        ],
      ),
    );
  }
}

extension on _SignInScreenState {
  Widget _testerCard(AppState app) => GlassCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Text('🎟️', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(S.of('testerTitle'),
                style: const TextStyle(
                    fontFamily: Tokens.display,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text(S.of('testerHint'),
              style: const TextStyle(color: Tokens.textDim, fontSize: 13)),
          const SizedBox(height: Tokens.s12),
          TextField(
            key: const Key('inviteCode'),
            controller: _inviteCode,
            textCapitalization: TextCapitalization.characters,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            autocorrect: false,
            style: const TextStyle(
                fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.w700),
            decoration: InputDecoration(labelText: S.of('testerCode')),
            onSubmitted: (_) => _testerSignIn(app),
          ),
          const SizedBox(height: Tokens.s12),
          GameButton(
            key: const Key('testerSignIn'),
            label: S.of('testerGo'),
            color: Tokens.mint,
            busy: _busy,
            onPressed: () => _testerSignIn(app),
          ),
        ]),
      );
}

/// Simple four-colour "G" mark drawn in code.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();
  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => const SweepGradient(colors: [
          Color(0xFFEA4335),
          Color(0xFFFBBC05),
          Color(0xFF34A853),
          Color(0xFF4285F4),
          Color(0xFFEA4335),
        ]).createShader(r),
        child: const Text('G',
            textDirection: TextDirection.ltr,
            style: TextStyle(
                fontFamily: Tokens.body,
                fontSize: 24,
                height: 1.1,
                fontWeight: FontWeight.w900,
                color: Colors.white)),
      );
}
