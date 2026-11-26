import 'package:flutter/foundation.dart';

/// Build-time configuration. Pass values with --dart-define.
class AppConfig {
  /// Working title only; the brand is not final.
  static const appName =
      String.fromEnvironment('APP_NAME', defaultValue: 'سهرة');

  static Uri get serverUrl {
    const fromEnv = String.fromEnvironment('SERVER_URL');
    if (fromEnv.isNotEmpty) return Uri.parse(fromEnv);
    // Web build served by the game server itself: same origin.
    if (kIsWeb) return Uri(scheme: Uri.base.scheme, host: Uri.base.host, port: Uri.base.port);
    // Android emulator reaches the host machine at 10.0.2.2.
    return defaultTargetPlatform == TargetPlatform.android
        ? Uri.parse('http://10.0.2.2:2567')
        : Uri.parse('http://localhost:2567');
  }

  /// OAuth "web/server" client id from Google Cloud; empty = Google sign-in disabled.
  static const googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Developer sign-in: debug builds, or local test builds made with
  /// --dart-define=DEV_SIGN_IN=true. The server also refuses it unless DEV_AUTH=1.
  static bool get devSignIn =>
      kDebugMode || const bool.fromEnvironment('DEV_SIGN_IN');
}
