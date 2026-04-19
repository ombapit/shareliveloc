import 'package:flutter/material.dart';

class AppTheme {
  // WhatsApp-inspired palette
  static const Color primary = Color(0xFF00A884);
  static const Color primaryDark = Color(0xFF008069);
  static const Color primaryDeeper = Color(0xFF005C4B);
  static const Color bubbleOut = Color(0xFFD9FDD3);
  static const Color bubbleIn = Color(0xFFFFFFFF);
  static const Color chatBackground = Color(0xFFEFEAE2);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: primaryDark,
      brightness: Brightness.light,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryDark,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: primary.withValues(alpha: 0.2),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            color: primaryDark,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primaryDark);
          }
          return const IconThemeData(color: Colors.grey);
        }),
      ),
    );
  }
}
