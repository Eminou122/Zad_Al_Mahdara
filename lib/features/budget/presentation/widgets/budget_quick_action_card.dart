import 'package:flutter/material.dart';
import '../../../../core/theme/zad_tokens.dart';

/// Compact tappable action card for the dashboard quick-actions grid.
class BudgetQuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const BudgetQuickActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZadTokens.surface,
      elevation: 1,
      shadowColor: const Color(0x22000000),
      borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(ZadTokens.s3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: ZadTokens.primary),
              const SizedBox(height: ZadTokens.s1 + 2),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: ZadTokens.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
