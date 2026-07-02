import 'package:flutter/material.dart';
import '../theme/zad_tokens.dart';

/// Tappable navigation/action card (icon, title, optional subtitle).
/// [accent] applies the gold treatment for special tiles (e.g. admin).
class ZadActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool accent;
  final VoidCallback onTap;

  const ZadActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ? ZadTokens.gold : ZadTokens.primary;
    return Material(
      color: ZadTokens.surface,
      elevation: 1,
      shadowColor: const Color(0x22000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
        side: accent
            ? const BorderSide(color: ZadTokens.goldSoft)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(ZadTokens.s3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: ZadTokens.s1 + 2),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: ZadTokens.text,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: ZadTokens.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
