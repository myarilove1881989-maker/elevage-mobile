import 'package:flutter/material.dart';

abstract final class V2Colors {
  static const navy = Color(0xFF063B63);
  static const green = Color(0xFF078637);
  static const background = Color(0xFFFCF7FF);
  static const border = Color(0xFF315D79);
  static const muted = Color(0xFF587087);
}

ThemeData designSystemV2([ThemeData? source]) {
  final base = source ?? ThemeData(useMaterial3: true);
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: V2Colors.border, width: 1.25),
  );
  final button = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Roboto'),
    scaffoldBackgroundColor: V2Colors.background,
    colorScheme: base.colorScheme.copyWith(
      primary: V2Colors.green,
      secondary: V2Colors.navy,
      surface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: V2Colors.navy,
      foregroundColor: Colors.white,
      centerTitle: false,
      elevation: 0,
      toolbarHeight: 64,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: outline,
      enabledBorder: outline,
      disabledBorder: outline.copyWith(
        borderSide: const BorderSide(color: Color(0xFF91A4B0)),
      ),
      focusedBorder: outline.copyWith(
        borderSide: const BorderSide(color: V2Colors.green, width: 2),
      ),
      errorBorder: outline.copyWith(
        borderSide: BorderSide(color: base.colorScheme.error, width: 1.5),
      ),
      focusedErrorBorder: outline.copyWith(
        borderSide: BorderSide(color: base.colorScheme.error, width: 2),
      ),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: const TextStyle(
        color: V2Colors.navy,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 18.67,
        color: V2Colors.navy,
        fontWeight: FontWeight.w600,
      ),
      prefixIconColor: V2Colors.green,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: V2Colors.border, width: 1.25),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: V2Colors.green,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: button,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: V2Colors.green,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: V2Colors.navy,
        side: const BorderSide(color: V2Colors.border, width: 1.25),
        minimumSize: const Size(48, 48),
        shape: button,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: V2Colors.green,
      foregroundColor: Colors.white,
    ),
  );
}
