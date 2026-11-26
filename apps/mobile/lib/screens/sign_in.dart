import 'package:flutter/material.dart';

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
    } catch (_) {
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
                  'chibi_sira',
                  'chibi_kairo',
                  'chibi_forest',
                  'chibi_rithia'
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
