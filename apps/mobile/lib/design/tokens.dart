import 'package:flutter/material.dart';

/// Design tokens shared by every screen and game. Each game gets its own
/// accent colour but uses the same surfaces, radii, spacing and type scale.
class Tokens {
  // Brand palette (placeholder until the brand is final).
  static const ink = Color(0xFF1E1638);
  static const inkSoft = Color(0xFF5B5277);
  static const night = Color(0xFF2B1B5E);
  static const nightDeep = Color(0xFF1A1040);
  static const sun = Color(0xFFFFB627);
  static const coral = Color(0xFFFF6B6B);
  static const mint = Color(0xFF2EC4B6);
  static const sky = Color(0xFF4D96FF);
  static const grape = Color(0xFF8B5CF6);
  static const paper = Color(0xFFFFF8EC);
  static const card = Colors.white;

  static const success = Color(0xFF22C55E);
  static const danger = Color(0xFFEF4444);

  /// Accent per game, so each has its own personality.
  static const gameAccent = {'quiz': sky};

  // Choice colours for multiple-choice answers (colour + shape label for accessibility).
  static const choiceColors = [coral, sky, sun, mint, grape, Color(0xFFF472B6)];

  static const r8 = Radius.circular(8);
  static const r16 = Radius.circular(16);
  static const r24 = Radius.circular(24);

  static const s4 = 4.0,
      s8 = 8.0,
      s12 = 12.0,
      s16 = 16.0,
      s24 = 24.0,
      s32 = 32.0;

  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 280);
}

/// Animation quality, adjustable for low-end devices.
enum GraphicsQuality { low, medium, high }
