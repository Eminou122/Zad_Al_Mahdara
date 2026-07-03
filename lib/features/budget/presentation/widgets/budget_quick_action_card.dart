import 'package:flutter/material.dart';
import '../../../../core/theme/zad_tokens.dart';

/// Stitch-style circular quick action: tinted (or gold-filled) icon disk
/// with a small label below. Used in the budget dashboard actions row.
class BudgetQuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  const BudgetQuickActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          // Stitch: gold disk + dark-gold icon for the primary action,
          // cream disks + green icons for the rest, all softly elevated.
          color: filled ? ZadTokens.gold : ZadTokens.surfaceContainer,
          elevation: 1,
          shadowColor: const Color(0x22000000),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 24,
                color: filled ? ZadTokens.goldDark : ZadTokens.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: ZadTokens.s2),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: ZadTokens.text,
          ),
        ),
      ],
    );
  }
}
