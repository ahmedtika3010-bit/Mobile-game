import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'tokens.dart';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: Tokens.display,
    fontFamilyFallback: const [Tokens.body],
    colorScheme: ColorScheme.fromSeed(
      seedColor: Tokens.grape,
      brightness: Brightness.dark,
      primary: Tokens.sun,
      onPrimary: Tokens.ink,
      secondary: Tokens.grape,
      surface: Tokens.night,
      onSurface: Colors.white,
      error: Tokens.danger,
    ),
    scaffoldBackgroundColor: Tokens.nightDeep,
  );
  final text = base.textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
      fontFamily: Tokens.display,
      fontFamilyFallback: const [Tokens.body]);
  OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(
      borderRadius: const BorderRadius.all(Tokens.r16),
      borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    textTheme: text.copyWith(
      displaySmall: text.displaySmall
          ?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
      headlineMedium: text.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w800, height: 1.2),
      headlineSmall: text.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: Colors.white,
      centerTitle: true,
      titleTextStyle: TextStyle(
          fontFamily: Tokens.display,
          fontFamilyFallback: [Tokens.body],
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Colors.white),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tokens.glass,
      labelStyle: const TextStyle(color: Tokens.textDim),
      floatingLabelStyle:
          const TextStyle(color: Tokens.sun, fontWeight: FontWeight.w700),
      hintStyle: const TextStyle(color: Tokens.textFaint),
      helperStyle: const TextStyle(color: Tokens.textFaint),
      counterStyle: const TextStyle(color: Tokens.textFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: border(Tokens.glassBorder),
      enabledBorder: border(Tokens.glassBorder),
      focusedBorder: border(Tokens.sun, 2),
      errorBorder: border(Tokens.danger),
    ),
    textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Tokens.sun, selectionColor: Color(0x55FFC83D)),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Tokens.night,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Tokens.textFaint,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Tokens.r32)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.white,
      contentTextStyle: const TextStyle(
          fontFamily: Tokens.display,
          fontFamilyFallback: [Tokens.body],
          color: Tokens.ink,
          fontWeight: FontWeight.w700,
          fontSize: 15),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Tokens.r16)),
      insetPadding: const EdgeInsets.all(Tokens.s16),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: Tokens.night,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Tokens.r16)),
      textStyle: TextStyle(
          fontFamily: Tokens.display,
          fontFamilyFallback: [Tokens.body],
          color: Colors.white,
          fontWeight: FontWeight.w700),
    ),
    listTileTheme: const ListTileThemeData(
        iconColor: Colors.white, textColor: Colors.white),
    dividerTheme: const DividerThemeData(color: Tokens.glassBorder),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
