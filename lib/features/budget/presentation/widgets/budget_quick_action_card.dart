import 'package:flutter/material.dart';
import '../../../../core/widgets/zad_action_card.dart';

/// Compact tappable action card for the dashboard quick-actions grid.
/// Thin wrapper over [ZadActionCard] so budget tiles match the home tiles.
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
    return ZadActionCard(icon: icon, title: label, onTap: onTap);
  }
}
