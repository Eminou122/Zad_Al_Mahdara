import 'package:flutter/material.dart';

/// Mahdari Oasis design tokens — single source of truth for the visual identity.
class ZadTokens {
  ZadTokens._();

  // Colors
  static const background = Color(0xFFF8F0DD); // warm sand
  static const surface = Color(0xFFFFFBEF); // cream card
  static const primary = Color(0xFF1D5B3C); // deep Mauritanian green
  static const primaryDark = Color(0xFF14432C); // AppBar / emphasis
  static const gold = Color(0xFFC9A227); // illumination accent
  static const goldSoft = Color(0xFFE8D9A8); // borders, dividers
  static const text = Color(0xFF33291C); // warm dark brown
  static const textMuted = Color(0xFF8A7B62);
  static const danger = Color(0xFFB3261E);
  static const warning = Color(0xFFB26A00);

  // Radius
  static const radiusSm = 8.0;
  static const radiusMd = 14.0;
  static const radiusLg = 20.0;

  // Spacing scale
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 24.0;
  static const s6 = 32.0;

  // Layout
  static const contentMaxWidth = 560.0;

  // Shadow
  static const cardShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
}
