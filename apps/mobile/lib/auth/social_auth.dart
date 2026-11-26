import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../config.dart';

class NotConfigured implements Exception {}

/// Gets an ID token from Google or Apple; the server verifies it.
/// Requires platform setup (OAuth client ids, Apple capability) described in docs/mobile.md.
class SocialAuth {
  static bool _googleReady = false;

  static bool get googleAvailable =>
      AppConfig.googleServerClientId.isNotEmpty && !kIsWeb;
  static bool get appleAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<String> googleIdToken() async {
    if (!googleAvailable) throw NotConfigured();
    if (!_googleReady) {
      await GoogleSignIn.instance
          .initialize(serverClientId: AppConfig.googleServerClientId);
      _googleReady = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;
    if (token == null) throw NotConfigured();
    return token;
  }

  static Future<String> appleIdToken() async {
    if (!appleAvailable) throw NotConfigured();
    final cred = await SignInWithApple.getAppleIDCredential(scopes: const []);
    final token = cred.identityToken;
    if (token == null) throw NotConfigured();
    return token;
  }
}
