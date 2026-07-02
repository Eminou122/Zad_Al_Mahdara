import 'package:flutter/material.dart';
import '../theme/zad_tokens.dart';
import 'zad_card.dart';

/// Empty state with a tinted circular icon (Stitch style).
/// Compact form (default) sits inside a card for lists/sections.
/// [big] renders the large centered variant with optional [title]/[action],
/// used by placeholder screens (notifications, admin).
class ZadEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? title;
  final Widget? action;
  final bool big;

  const ZadEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.title,
    this.action,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final circle = big ? 120.0 : 60.0;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: circle,
          height: circle,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ZadTokens.gold.withValues(alpha: 0.12),
          ),
          child: Icon(
            icon,
            size: big ? 48 : 30,
            color: big ? ZadTokens.primaryDark : ZadTokens.gold,
          ),
        ),
        SizedBox(height: big ? ZadTokens.s4 : ZadTokens.s3),
        if (title != null) ...[
          Text(
            title!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: ZadTokens.s2),
        ],
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: ZadTokens.textMuted),
        ),
        if (action != null) ...[const SizedBox(height: ZadTokens.s5), action!],
      ],
    );
    if (big) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ZadTokens.s4,
          vertical: ZadTokens.s6,
        ),
        child: content,
      );
    }
    return ZadCard(padding: const EdgeInsets.all(ZadTokens.s5), child: content);
  }
}
