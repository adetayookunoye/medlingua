import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/triage_encounter.dart';

class AppTheme {
  // MedLingua Brand Colors
  static const Color primaryGreen = Color(0xFF0D9488); // Teal - Trust & Health
  static const Color primaryDark = Color(0xFF115E59);
  static const Color accentOrange = Color(0xFFF59E0B); // Warm accent
  static const Color bgLight = Color(0xFFF0FDF4);
  static const Color bgWhite = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF1E293B);
  static const Color textMuted = Color(0xFF64748B);
  static const Color dangerRed = Color(0xFFEF4444);
  static const Color warningYellow = Color(0xFFF59E0B);
  static const Color safeGreen = Color(0xFF22C55E);

  // Triage severity colors
  static const Color triageEmergency = Color(0xFFDC2626);
  static const Color triageUrgent = Color(0xFFF97316);
  static const Color triageStandard = Color(0xFFEAB308);
  static const Color triageRoutine = Color(0xFF22C55E);

  // Spacing scale (consistent 4pt grid)
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 12;
  static const double spacingLg = 16;
  static const double spacingXl = 20;
  static const double spacingXxl = 24;
  static const double spacingSection = 32;

  // Border radius scale
  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;
  static const double radiusFull = 20;

  /// Map triage severity to its display color.
  static Color severityColor(TriageSeverity severity) {
    switch (severity) {
      case TriageSeverity.emergency:
        return triageEmergency;
      case TriageSeverity.urgent:
        return triageUrgent;
      case TriageSeverity.standard:
        return triageStandard;
      case TriageSeverity.routine:
        return triageRoutine;
    }
  }

  /// Map triage severity to its display icon.
  static IconData severityIcon(TriageSeverity severity) {
    switch (severity) {
      case TriageSeverity.emergency:
        return Icons.warning;
      case TriageSeverity.urgent:
        return Icons.schedule;
      case TriageSeverity.standard:
        return Icons.info_outline;
      case TriageSeverity.routine:
        return Icons.check_circle_outline;
    }
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        primary: primaryGreen,
        secondary: accentOrange,
        surface: bgWhite,
        error: dangerRed,
      ),
      textTheme: GoogleFonts.interTextTheme().copyWith(
        headlineLarge: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: textDark,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textDark,
        ),
        bodyLarge: GoogleFonts.inter(fontSize: 16, color: textDark),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: textMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: bgWhite,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
