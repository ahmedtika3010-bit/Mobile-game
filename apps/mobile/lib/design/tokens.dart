import 'package:flutter/material.dart';

/// Design tokens shared by every screen and game. The look is "a night out
/// with friends": a deep night sky, warm lantern light and candy-bright game
/// colours. Each game gets its own accent but shares surfaces, radii,
/// spacing, type and motion.
class Tokens {
  // Night sky (backgrounds).
  static const nightDeep = Color(0xFF0E0828);
  static const night = Color(0xFF1C1150);
  static const plum = Color(0xFF3A1A7A);
  static const dusk = Color(0xFF5B2A8C);

  // Candy accents.
  static const sun = Color(0xFFFFC83D);
  static const orange = Color(0xFFFF8A3D);
  static const coral = Color(0xFFFF5A7A);
  static const pink = Color(0xFFFF6FD8);
  static const grape = Color(0xFF8E5BFF);
  static const sky = Color(0xFF3DA5FF);
  static const mint = Color(0xFF1FD1A5);

  // Text and light surfaces.
  static const ink = Color(0xFF1A1033);
  static const inkSoft = Color(0xFF6B6290);
  static const paper = Color(0xFFFFF8EC);
  static const card = Colors.white;
  static const textDim = Color(0xB3FFFFFF); // white 70%
  static const textFaint = Color(0x80FFFFFF); // white 50%

  // Glass surfaces on the night background.
  static const glass = Color(0x1AFFFFFF); // white 10%
  static const glassStrong = Color(0x29FFFFFF); // white 16%
  static const glassBorder = Color(0x24FFFFFF); // white 14%

  static const success = Color(0xFF22D37A);
  static const danger = Color(0xFFFF4D5E);

  static const display = 'Baloo';
  static const body = 'Cairo';

  /// Accent per game, so each has its own personality.
  static const gameAccent = {'quiz': sky};

  /// Answer colours (each also has a shape and a letter, so colour is never
  /// the only cue).
  static const choiceColors = [coral, sky, sun, mint, grape, pink];

  static const r8 = Radius.circular(8);
  static const r12 = Radius.circular(12);
  static const r16 = Radius.circular(16);
  static const r20 = Radius.circular(20);
  static const r24 = Radius.circular(24);
  static const r32 = Radius.circular(32);

  static const s4 = 4.0,
      s8 = 8.0,
      s12 = 12.0,
      s16 = 16.0,
      s20 = 20.0,
      s24 = 24.0,
      s32 = 32.0,
      s48 = 48.0;

  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 500);

  static LinearGradient gradient(Color a, Color b) => LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]);

  /// Darker shade of a colour, for 3D edges and shadows.
  static Color shade(Color c, [double amount = 0.16]) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness - amount).clamp(0.0, 1.0)).toColor();
  }

  /// Lighter tint of a colour, for highlights.
  static Color tint(Color c, [double amount = 0.1]) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  /// Text colour that stays readable on [bg].
  static Color onColor(Color bg) =>
      bg.computeLuminance() > 0.55 ? ink : Colors.white;
}

/// Animation quality, adjustable for low-end devices.
enum GraphicsQuality { low, medium, high }
