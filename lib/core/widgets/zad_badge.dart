import 'package:flutter/material.dart';
import '../theme/zad_tokens.dart';

/// Small rounded label chip. [gold] for accent badges (e.g. team type).
class ZadBadge extends StatelessWidget {
  final String label;
  final bool gold;
  const ZadBadge(this.label, {super.key, this.gold = false});

  @override
  Widget build(BuildContext context) {
    final c = gold ? ZadTokens.gold : ZadTokens.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZadTokens.s2, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ZadTokens.radiusSm),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: gold ? ZadTokens.text : c,
        ),
      ),
    );
  }
}
