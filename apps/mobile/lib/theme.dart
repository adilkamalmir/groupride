import 'package:flutter/material.dart';

class AppTheme {
  static const asphalt = Color(0xFF1A1D23);
  static const asphaltLight = Color(0xFF2A2F3A);
  static const signal = Color(0xFFE85D04);
  static const signalSoft = Color(0xFFFF8C42);
  static const mist = Color(0xFFE8ECF1);
  static const steel = Color(0xFF8B95A5);
  static const riding = Color(0xFF2DC653);
  static const stopped = Color(0xFFF4D35E);
  static const emergency = Color(0xFFE63946);
  static const fuel = Color(0xFF4CC9F0);

  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: signal,
        secondary: signalSoft,
        surface: asphaltLight,
        error: emergency,
        onPrimary: Colors.white,
        onSurface: mist,
      ),
      scaffoldBackgroundColor: asphalt,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: mist,
          letterSpacing: -0.3,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: signal,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: mist,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: steel),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: asphaltLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      cardTheme: CardThemeData(
        color: asphaltLight,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'riding':
        return riding;
      case 'stopped':
        return stopped;
      case 'emergency':
        return emergency;
      case 'fuelneeded':
      case 'fuel_needed':
        return fuel;
      default:
        return steel;
    }
  }
}
