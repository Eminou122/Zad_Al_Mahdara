import 'package:flutter/material.dart';
import '../theme/zad_tokens.dart';

enum ZadBannerKind { info, success, warning, danger }

/// Tinted message banner — replaces the per-screen _ErrorBox/_WarningBox copies.
class ZadInfoBanner extends StatelessWidget {
  final String message;
  final ZadBannerKind kind;

  const ZadInfoBanner(
    this.message, {
    super.key,
    this.kind = ZadBannerKind.info,
  });

  static const _colors = {
    ZadBannerKind.info: ZadTokens.primary,
    ZadBannerKind.success: ZadTokens.primary,
    ZadBannerKind.warning: ZadTokens.warning,
    ZadBannerKind.danger: ZadTokens.danger,
  };

  static const _icons = {
    ZadBannerKind.info: Icons.lightbulb_outline,
    ZadBannerKind.success: Icons.check_circle_outline,
    ZadBannerKind.warning: Icons.warning_amber_outlined,
    ZadBannerKind.danger: Icons.error_outline,
  };

  @override
  Widget build(BuildContext context) {
    final c = _colors[kind]!;
    return Container(
      margin: const EdgeInsets.only(bottom: ZadTokens.s3),
      padding: const EdgeInsets.all(ZadTokens.s3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ZadTokens.radiusSm),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(_icons[kind], color: c, size: 20),
          const SizedBox(width: ZadTokens.s2 + 2),
          Expanded(
            child: Text(message, style: TextStyle(color: c)),
          ),
        ],
      ),
    );
  }
}
