import 'package:flutter/material.dart';

/// Approximates `app/globals.css` Sportsmagician palette (OKLCH → sRGB).
class AppColors {
  static const Color background = Color(0xFF1B2238);
  static const Color foreground = Color(0xFFF8FAFC);
  static const Color card = Color(0xFF2D3A5C);
  static const Color muted = Color(0xFF3D4A6B);
  static const Color mutedForeground = Color(0xFFE0E4EE);
  static const Color primary = Color(0xFFF59E42);
  static const Color primaryForeground = Color(0xFF1B2238);
  static const Color accent = Color(0xFFF5D563);
  static const Color destructive = Color(0xFFE85D4A);
  static const Color border = Color(0xFF455078);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.background,
      primary: AppColors.primary,
      onPrimary: AppColors.primaryForeground,
      secondary: AppColors.card,
      onSecondary: AppColors.foreground,
      error: AppColors.destructive,
      onError: AppColors.foreground,
      onSurface: AppColors.foreground,
      outline: AppColors.border,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.card,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      labelStyle: const TextStyle(color: AppColors.mutedForeground),
      hintStyle: TextStyle(color: AppColors.mutedForeground.withValues(alpha: 0.8)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.primaryForeground,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.foreground,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.mutedForeground,
      indicatorColor: AppColors.primary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.card,
      foregroundColor: AppColors.foreground,
      elevation: 0,
      centerTitle: false,
    ),
    dividerColor: AppColors.border,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.card,
      contentTextStyle: const TextStyle(color: AppColors.foreground),
    ),
  );
  return base;
}
