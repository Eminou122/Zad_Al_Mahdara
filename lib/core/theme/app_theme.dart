import 'package:flutter/material.dart';
import 'zad_tokens.dart';

class AppTheme {
  static final light = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: ZadTokens.background,
    colorScheme: const ColorScheme.light(
      primary: ZadTokens.primary,
      onPrimary: Colors.white,
      secondary: ZadTokens.gold,
      onSecondary: ZadTokens.text,
      surface: ZadTokens.surface,
      onSurface: ZadTokens.text,
      error: ZadTokens.danger,
      onError: Colors.white,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: ZadTokens.text, fontSize: 16),
      bodyMedium: TextStyle(color: ZadTokens.text, fontSize: 14),
      bodySmall: TextStyle(color: ZadTokens.textMuted, fontSize: 13),
      titleLarge: TextStyle(
        color: ZadTokens.text,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
      titleMedium: TextStyle(
        color: ZadTokens.text,
        fontSize: 17,
        fontWeight: FontWeight.bold,
      ),
      titleSmall: TextStyle(
        color: ZadTokens.text,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: ZadTokens.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ZadTokens.primary,
        side: const BorderSide(color: ZadTokens.primary),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: ZadTokens.primary),
    ),
    cardTheme: const CardThemeData(
      color: ZadTokens.surface,
      elevation: 1,
      shadowColor: Color(0x22000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(ZadTokens.radiusMd)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: ZadTokens.primaryDark,
      foregroundColor: Colors.white,
      centerTitle: true,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ZadTokens.surface,
      labelStyle: const TextStyle(color: ZadTokens.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZadTokens.radiusSm + 2),
        borderSide: const BorderSide(color: ZadTokens.goldSoft),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZadTokens.radiusSm + 2),
        borderSide: const BorderSide(color: ZadTokens.goldSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZadTokens.radiusSm + 2),
        borderSide: const BorderSide(color: ZadTokens.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ZadTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZadTokens.radiusLg),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: ZadTokens.primaryDark,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: ZadTokens.primary,
    ),
    dividerTheme: const DividerThemeData(color: ZadTokens.goldSoft),
    listTileTheme: const ListTileThemeData(iconColor: ZadTokens.primary),
  );
}
