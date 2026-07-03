import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_scaffold.dart';

const _warmBorder = Color(0xFFF2E0CC);
const _warmDisk = Color(0xFFFEEDDC);

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ZadScaffold(
      title: 'الإدارة',
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, ZadTokens.s6, 20, 96),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 128).clamp(380.0, 640.0),
              ),
              child: Center(
                child: ZadAnimatedEntry(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
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
                                color: _warmDisk,
                                border: Border.all(
                                  color: ZadTokens.gold.withValues(alpha: 0.4),
                                  width: 1.5,
                                ),
                                boxShadow: ZadTokens.cardShadow,
                              ),
                              child: const Icon(
                                Icons.admin_panel_settings_outlined,
                                size: 64,
                                color: ZadTokens.primaryDark,
                              ),
                            ),
                            PositionedDirectional(
                              top: -4,
                              end: -4,
                              child: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: ZadTokens.gold,
                                ),
                                child: const Icon(
                                  Icons.lock_outline,
                                  size: 20,
                                  color: ZadTokens.primaryDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: ZadTokens.s5),
                        Text(
                          'منطقة إدارية',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: ZadTokens.text,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: ZadTokens.s3),
                        const Text(
                          'هذه الصفحة مخصصة للمؤسس والمسؤولين فقط. ستتوفر أدوات الإدارة هنا قريباً.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: ZadTokens.textMuted,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: ZadTokens.s5),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.home_outlined),
                            label: const Text('العودة للرئيسية'),
                            onPressed: () => context.go('/home'),
                          ),
                        ),
                        const SizedBox(height: ZadTokens.s4),
                        Container(
                          width: 116,
                          height: 4,
                          decoration: BoxDecoration(
                            color: _warmBorder,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          alignment: AlignmentDirectional.centerStart,
                          child: FractionallySizedBox(
                            widthFactor: 0.34,
                            child: Container(
                              decoration: BoxDecoration(
                                color: ZadTokens.gold.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
