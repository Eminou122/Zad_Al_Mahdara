import 'package:flutter/material.dart';
import '../theme/zad_tokens.dart';

/// Fully-rounded tinted pill chip (Stitch badge style).
/// [gold] for accent badges (e.g. team type).
class ZadBadge extends StatelessWidget {
  final String label;
  final bool gold;
  const ZadBadge(this.label, {super.key, this.gold = false});

  @override
  Widget build(BuildContext context) {
    final c = gold ? ZadTokens.gold : ZadTokens.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZadTokens.s2 + 2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: gold ? ZadTokens.goldDark : c,
        ),
      ),
    );
  }
}
