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
      color: accent
          ? ZadTokens.gold.withValues(alpha: 0.10)
          : ZadTokens.surfaceContainer.withValues(alpha: 0.72),
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
          padding: const EdgeInsets.symmetric(
            horizontal: ZadTokens.s3,
            vertical: ZadTokens.s4,
          ),
          child: Column(
            // min: sizes to content when used full-width outside a grid cell;
            // grid cells impose tight constraints, so they render unchanged.
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.12),
                ),
                child: Icon(icon, size: 25, color: color),
              ),
              const SizedBox(height: ZadTokens.s2),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
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
                    fontSize: 11.5,
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
