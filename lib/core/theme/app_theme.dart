import 'package:flutter/material.dart';

class AppTheme {
  static const sand = Color(0xFFF5E6C8);
  static const green = Color(0xFF2E7D32);
  static const brown = Color(0xFF3E2723);
  static const cream = Color(0xFFFFF8E1);

  static final light = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: sand,
    colorScheme: ColorScheme.light(
      primary: green,
      onPrimary: Colors.white,
      surface: cream,
      onSurface: brown,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: brown, fontSize: 16),
      bodyMedium: TextStyle(color: brown, fontSize: 14),
      titleLarge: TextStyle(color: brown, fontSize: 22, fontWeight: FontWeight.bold),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: green,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
    cardTheme: const CardThemeData(
      color: cream,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: green,
      foregroundColor: Colors.white,
      centerTitle: true,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cream,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
