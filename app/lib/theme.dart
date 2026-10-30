import 'package:flutter/material.dart';

/// The "original" canvas style.
abstract final class Palette {
  static const background = Color(0xFFF2F3F0);
  static const card = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFE1E3DE);
  static const divider = Color(0xFFEEF0EC);
  static const fieldBorder = Color(0xFFC9CDC6);
  static const ink = Color(0xFF17191B);
  static const inkSoft = Color(0xFF3E4348);
  static const muted = Color(0xFF5B6066);
  static const teal = Color(0xFF0A6B5C);
  static const problemText = Color(0xFF8F3F09);
  static const heroLabel = Color(0xFFB9BEB8);
}

const sansFamily = 'IBMPlexSans';
const monoFamily = 'IBMPlexMono';

/// IBM Plex Mono with tabular figures, for amounts.
TextStyle amountStyle({
  double fontSize = 15,
  FontWeight fontWeight = FontWeight.w400,
  Color? color,
}) => TextStyle(
  fontFamily: monoFamily,
  fontFeatures: const [FontFeature.tabularFigures()],
  fontSize: fontSize,
  fontWeight: fontWeight,
  color: color,
);

ThemeData buildTheme() {
  const pill = StadiumBorder();
  const buttonText = TextStyle(
    fontFamily: sansFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
  OutlineInputBorder fieldBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: color),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: sansFamily,
    scaffoldBackgroundColor: Palette.background,
    colorScheme: const ColorScheme.light(
      primary: Palette.teal,
      onPrimary: Colors.white,
      surface: Palette.card,
      onSurface: Palette.ink,
      error: Palette.problemText,
    ),
    textTheme: ThemeData.light().textTheme.apply(
      fontFamily: sansFamily,
      bodyColor: Palette.ink,
      displayColor: Palette.ink,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.teal,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: Palette.card,
        foregroundColor: Palette.ink,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: Palette.fieldBorder),
        shape: pill,
        textStyle: buttonText.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.card,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: fieldBorder(Palette.fieldBorder),
      focusedBorder: fieldBorder(Palette.teal),
      errorBorder: fieldBorder(Palette.problemText),
      focusedErrorBorder: fieldBorder(Palette.problemText),
      errorStyle: const TextStyle(color: Palette.problemText, fontSize: 12),
    ),
  );
}
