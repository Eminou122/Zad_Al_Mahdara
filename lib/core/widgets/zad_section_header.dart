import 'package:flutter/material.dart';
import '../theme/zad_tokens.dart';

/// Section title with a subtle gold ornament divider (Sahrawi diamond).
class ZadSectionHeader extends StatelessWidget {
  final String title;
  const ZadSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: ZadTokens.s4, bottom: ZadTokens.s2),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: ZadTokens.s3),
          Transform.rotate(
            angle: 0.785398, // 45° diamond
            child: Container(width: 6, height: 6, color: ZadTokens.gold),
          ),
          const SizedBox(width: ZadTokens.s3),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
    );
  }
}
