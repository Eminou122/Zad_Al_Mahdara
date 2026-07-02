import 'package:flutter/material.dart';
import '../theme/zad_tokens.dart';

/// Cream surface card with the Mahdari Oasis radius/shadow.
/// [highlighted] adds a thin gold border for hero cards.
class ZadCard extends StatelessWidget {
  final Widget child;
  final bool highlighted;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const ZadCard({
    super.key,
    required this.child,
    this.highlighted = false,
    this.padding = const EdgeInsets.all(ZadTokens.s4),
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: ZadTokens.surface,
        borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
        boxShadow: ZadTokens.cardShadow,
        border: highlighted ? Border.all(color: ZadTokens.goldSoft) : null,
      ),
      child: child,
    );
  }
}
