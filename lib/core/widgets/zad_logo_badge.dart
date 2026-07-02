import 'package:flutter/material.dart';
import '../theme/zad_tokens.dart';

/// The app emblem as a polished circular badge (cream disk, gold ring, soft shadow).
class ZadLogoBadge extends StatelessWidget {
  final double size;
  const ZadLogoBadge({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: ZadTokens.surface,
        boxShadow: ZadTokens.cardShadow,
      ),
      child: ClipOval(
        // Slight over-scale hides any residual edge pixels in the asset.
        child: Transform.scale(
          scale: 1.04,
          child: Image.asset(
            'assets/images/zad_al_mahdara_logo.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
