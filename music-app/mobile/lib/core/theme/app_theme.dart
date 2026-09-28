import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF080A0C);
  static const Color surface = Color(0xFF111416);
  static const Color surfaceElevated = Color(0xFF181D20);
  static const Color accent = Color(0xFFD5FF63);
  static const Color accentSubtle = Color(0xFF2B665C);
  static const Color textPrimary = Color(0xFFF4F5F3);
  static const Color textSecondary = Color(0xFFA2AAA5);
  static const Color textMuted = Color(0xFF666D69);
  static const Color border = Color(0x1AFFFFFF);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      canvasColor: surface,
      cardColor: surface,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentSubtle,
        surface: surface,
        onPrimary: Colors.black,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xF0090B0D),
        selectedItemColor: accent,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 10,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: textPrimary, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -1.0),
        headlineMedium: TextStyle(color: textPrimary, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.8),
        titleLarge: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.4),
        titleMedium: TextStyle(color: textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 14, height: 1.4),
        bodyMedium: TextStyle(color: textSecondary, fontSize: 12, height: 1.4),
        bodySmall: TextStyle(color: textMuted, fontSize: 11),
      ),
    );
  }
}
