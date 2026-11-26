import 'package:flutter/material.dart';
import 'tokens.dart';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Cairo',
    colorScheme: ColorScheme.fromSeed(
        seedColor: Tokens.grape,
        primary: Tokens.grape,
        secondary: Tokens.sun,
        surface: Tokens.paper),
    scaffoldBackgroundColor: Tokens.paper,
  );
  final text =
      base.textTheme.apply(bodyColor: Tokens.ink, displayColor: Tokens.ink);
  return base.copyWith(
    textTheme: text.copyWith(
      headlineMedium:
          text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Tokens.ink,
        centerTitle: true),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Tokens.r16),
          borderSide: BorderSide(color: Tokens.ink.withValues(alpha: 0.12))),
      enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Tokens.r16),
          borderSide: BorderSide(color: Tokens.ink.withValues(alpha: 0.12))),
    ),
  );
}
