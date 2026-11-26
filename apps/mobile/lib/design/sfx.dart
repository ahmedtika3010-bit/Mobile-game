import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Short game sounds (assets/sfx) plus matching haptics. Sound can be muted;
/// the choice is remembered on the device.
class Sfx {
  static bool enabled = true;
  static const _key = 'sfx_enabled';
  static const _store = FlutterSecureStorage();

  static Future<void> load() async {
    try {
      enabled = (await _store.read(key: _key)) != 'false';
    } catch (_) {}
  }

  static Future<void> setEnabled(bool on) async {
    enabled = on;
    try {
      await _store.write(key: _key, value: '$on');
    } catch (_) {}
  }

  static Future<void> play(String name, {double volume = 0.7}) async {
    if (!enabled) return;
    try {
      final p = AudioPlayer();
      await p.setPlayerMode(
          kIsWeb ? PlayerMode.mediaPlayer : PlayerMode.lowLatency);
      p.onPlayerComplete.first.then((_) => p.dispose());
      await p.play(AssetSource('sfx/$name.wav'), volume: volume);
    } catch (_) {
      // Sound is a nicety; never let it break the game.
    }
  }

  static void correct() {
    play('correct');
    HapticFeedback.heavyImpact();
  }

  static void wrong() {
    play('wrong', volume: 0.5);
    HapticFeedback.vibrate();
  }
}
