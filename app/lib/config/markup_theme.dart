// app/lib/config/markup_theme.dart
import 'package:flutter/material.dart';

abstract final class MarkupColors {
  static const darkGreen = Color(0xFF1b4332);
  static const mediumGreen = Color(0xFF2D6A4F);
  static const lightGreen = Color(0xFF95D5B2);
  static const bgGreen = Color(0xFFE9F7EE);
  static const orange = Color(0xFFc45200);
  static const bgOrange = Color(0xFFFFF8F0);
  static const textPrimary = Color(0xFF111111);
  static const textSecondary = Color(0xFF555555);
  static const textHint = Color(0xFF888888);
  static const surface = Color(0xFFFAFAFA);
  static const cardBg = Colors.white;
}

ThemeData markupTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MarkupColors.darkGreen,
      primary: MarkupColors.darkGreen,
      secondary: MarkupColors.mediumGreen,
      surface: MarkupColors.surface,
    ),
    scaffoldBackgroundColor: MarkupColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: MarkupColors.textPrimary,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: MarkupColors.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    fontFamily: null, // system default
  );
}
