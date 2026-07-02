import 'package:flutter/material.dart';
import '../theme/zad_tokens.dart';
import 'zad_card.dart';

/// Icon + muted message inside a cream card, for empty lists/sections.
class ZadEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const ZadEmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return ZadCard(
      padding: const EdgeInsets.all(ZadTokens.s5),
      child: Column(
        children: [
          Icon(icon, size: 36, color: ZadTokens.gold),
          const SizedBox(height: ZadTokens.s2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ZadTokens.textMuted),
          ),
        ],
      ),
    );
  }
}
