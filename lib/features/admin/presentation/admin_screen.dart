import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_dotted_background.dart';
import '../../../core/widgets/zad_scaffold.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ZadScaffold(
      title: 'لوحة الإدارة',
      body: ZadDottedBackground(
        color: ZadTokens.gold.withValues(alpha: 0.12),
        child: ZadAnimatedEntry(
          child: Padding(
            padding: const EdgeInsets.only(top: 260),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 132,
                      height: 132,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ZadTokens.surfaceContainer,
                        border: Border.all(color: ZadTokens.goldSoft),
                        boxShadow: ZadTokens.cardShadow,
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 56,
                        color: ZadTokens.primaryDark,
                      ),
                    ),
                    PositionedDirectional(
                      top: -6,
                      end: -2,
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: ZadTokens.gold,
                        ),
                        child: const Icon(
                          Icons.lock,
                          size: 20,
                          color: ZadTokens.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZadTokens.s5),
                Text(
                  'منطقة محظورة',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: ZadTokens.s2),
                const Text(
                  'هذه الصفحة مخصصة للمؤسس والمسؤولين فقط. يرجى العودة إلى الصفحة الرئيسية.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ZadTokens.textMuted),
                ),
                const SizedBox(height: ZadTokens.s5),
                ElevatedButton.icon(
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('العودة للرئيسية'),
                  onPressed: () => context.pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
