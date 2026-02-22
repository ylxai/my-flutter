import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'glass_colors.dart';

/// App theme — supports both light and dark mode
class GlassTheme {
  GlassTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: GlassColors.liquidBlue,
      scaffoldBackgroundColor: GlassColors.bgDarkPrimary,
      colorScheme: const ColorScheme.dark(
        primary: GlassColors.liquidBlue,
        secondary: GlassColors.liquidIndigo,
        tertiary: GlassColors.liquidTeal,
        surface: GlassColors.bgDarkSecondary,
        error: GlassColors.systemRed,
      ),
      textTheme: GoogleFonts.interTextTheme(
        const TextTheme(
          displayLarge: TextStyle(
            color: GlassColors.textDarkPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          headlineLarge: TextStyle(
            color: GlassColors.textDarkPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          headlineMedium: TextStyle(
            color: GlassColors.textDarkPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: TextStyle(
            color: GlassColors.textDarkPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            color: GlassColors.textDarkPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          bodyLarge: TextStyle(
            color: GlassColors.textDarkPrimary,
            fontSize: 14,
          ),
          bodyMedium: TextStyle(
            color: GlassColors.textDarkSecondary,
            fontSize: 13,
          ),
          bodySmall: TextStyle(color: GlassColors.textDarkMuted, fontSize: 12),
          labelLarge: TextStyle(
            color: GlassColors.textDarkPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerColor: Colors.white.withValues(alpha: 0.08),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: GlassColors.liquidBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: GlassColors.textDarkPrimary,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: GlassColors.bgDarkTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: GlassColors.liquidBlue, width: 2),
        ),
        hintStyle: const TextStyle(color: GlassColors.systemGray),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: GlassColors.liquidBlue,
      scaffoldBackgroundColor: GlassColors.glassBlur,
      colorScheme: const ColorScheme.light(
        primary: GlassColors.liquidBlue,
        secondary: GlassColors.liquidIndigo,
        tertiary: GlassColors.liquidTeal,
        surface: GlassColors.bgLightSecondary,
        error: GlassColors.systemRed,
      ),
      textTheme: GoogleFonts.interTextTheme(),
      dividerColor: Colors.black.withValues(alpha: 0.08),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: GlassColors.bgLightSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: GlassColors.liquidBlue, width: 2),
        ),
        hintStyle: const TextStyle(color: GlassColors.systemGray),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }
}
