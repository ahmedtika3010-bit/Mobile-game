import 'package:flutter/material.dart';

import '../app_state.dart';
import '../auth/social_auth.dart';
import '../config.dart';
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
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => app.canPlay ? const _Done() : const OnboardingScreen(),
      ));
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
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(Tokens.s24), children: [
          Text(S.of('signInTitle'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Tokens.s32),
          GameButton(
            label: S.of('signInGoogle'),
            color: Tokens.sky,
            busy: _busy,
            onPressed: () => _run(() async =>
                app.api.signInWithGoogle(await SocialAuth.googleIdToken())),
          ),
          const SizedBox(height: Tokens.s12),
          GameButton(
            label: S.of('signInApple'),
            color: Tokens.ink,
            busy: _busy,
            onPressed: () => _run(() async =>
                app.api.signInWithApple(await SocialAuth.appleIdToken())),
          ),
          if (_error != null) ...[
            const SizedBox(height: Tokens.s16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Tokens.danger)),
          ],
          if (AppConfig.devSignIn) ...[
            const SizedBox(height: Tokens.s32),
            const Divider(),
            const SizedBox(height: Tokens.s16),
            TextField(
              key: const Key('devName'),
              controller: _devName,
              decoration: InputDecoration(labelText: S.of('devName')),
            ),
            const SizedBox(height: Tokens.s12),
            GameButton(
              key: const Key('devSignIn'),
              label: S.of('signInDev'),
              color: Tokens.inkSoft,
              busy: _busy,
              onPressed: () {
                final name = _devName.text.trim();
                if (name.isNotEmpty) _run(() => app.api.signInDev(name));
              },
            ),
          ],
        ]),
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done();
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => Navigator.of(context).pop());
    return const SizedBox.shrink();
  }
}
