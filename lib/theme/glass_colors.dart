import 'package:flutter/material.dart';

/// Color palette — Liquid Glass design system
class GlassColors {
  GlassColors._();

  // ===== Core / Accent Colors =====
  static const Color liquidBlue = Color(0xFF007AFF);
  static const Color liquidPurple = Color(0xFFAF52DE);
  static const Color liquidIndigo = Color(0xFF5856D6);
  static const Color liquidTeal = Color(0xFF5AC8FA);

  // ===== System / Neutral Colors =====
  static const Color systemGray = Color(0xFF8E8E93);
  static const Color systemGray2 = Color(0xFFAEAEB2);
  static const Color systemGray3 = Color(0xFFC7C7CC);
  static const Color systemGray4 = Color(0xFFD1D1D6);

  // ===== Semantic Status =====
  static const Color systemRed = Color(0xFFFF3B30);
  static const Color systemOrange = Color(0xFFFF9500);
  static const Color systemYellow = Color(0xFFFFCC00);
  static const Color systemGreen = Color(0xFF34C759);

  // ===== Glass / Overlay Colors =====
  static const Color glassLight = Color.fromRGBO(255, 255, 255, 0.3);
  static const Color glassDark = Color.fromRGBO(0, 0, 0, 0.2);
  static const Color glassBlur = Color(0xFFF2F2F7);
  static const Color glassAccent = liquidBlue;

  // ===== Dark Mode Backgrounds =====
  static const Color bgDarkPrimary = Color(0xFF000000);
  static const Color bgDarkSecondary = Color(0xFF1C1C1E);
  static const Color bgDarkTertiary = Color(0xFF2C2C2E);
  static const Color bgDarkElevated = Color(0xFF3A3A3C);

  // ===== Light Mode Backgrounds =====
  static const Color bgLightPrimary = Color(0xFFF2F2F7);
  static const Color bgLightSecondary = Color(0xFFFFFFFF);
  static const Color bgLightTertiary = Color(0xFFEFEFF4);

  // ===== Text Colors =====
  static const Color textDarkPrimary = Color(0xFFFFFFFF);
  static const Color textDarkSecondary = Color(0x99FFFFFF); // 60%
  static const Color textDarkMuted = Color(0x4DFFFFFF); // 30%
  static const Color textLightPrimary = Color(0xFF000000);
  static const Color textLightSecondary = Color(0xFF8E8E93);

  // ===== Gradients =====
  static const LinearGradient accentGradient = LinearGradient(
    colors: [liquidBlue, liquidIndigo],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient purpleGradient = LinearGradient(
    colors: [liquidPurple, liquidIndigo],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient tealGradient = LinearGradient(
    colors: [liquidTeal, liquidBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ===== Sidebar =====
  static const Color sidebarBg = Color(0xFF1C1C1E);
  static const Color sidebarActive = liquidBlue;
  static const Color sidebarInactive = Color(0xFF8E8E93);
  static const Color sidebarHover = Color(0xFF2C2C2E);

  // Aliases for backward compatibility
  static const Color success = systemGreen;
  static const Color warning = systemOrange;
  static const Color error = systemRed;
  static const Color info = liquidBlue;
}
