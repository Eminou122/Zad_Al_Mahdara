import 'package:flutter/material.dart';
import '../../../../core/theme/zad_tokens.dart';

/// Small labeled metric (icon, value, label) used inside dashboard cards.
class BudgetMetricTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? valueColor;

  const BudgetMetricTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: ZadTokens.gold),
        const SizedBox(height: ZadTokens.s1),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: valueColor ?? ZadTokens.text,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: ZadTokens.textMuted),
        ),
      ],
    );
  }
}
