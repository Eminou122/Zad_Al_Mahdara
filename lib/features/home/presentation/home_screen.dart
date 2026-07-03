import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_action_card.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_confirm.dart';
import '../../../core/widgets/zad_dotted_background.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../core/widgets/zad_section_header.dart';
import '../../../services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  final AuthService authService;
  const HomeScreen({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: authService,
      builder: (context, _) {
        if (authService.isLoadingSession) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final name = authService.displayName;
        return ZadScaffold(
          title: 'الرئيسية',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ZadAnimatedEntry(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(ZadTokens.radiusLg),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: ZadTokens.heroGradient,
                      boxShadow: ZadTokens.cardShadow,
                    ),
                    child: ZadDottedBackground(
                      color: Colors.white24,
                      child: Padding(
                        padding: const EdgeInsets.all(ZadTokens.s5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isNotEmpty ? 'مرحباً، $name' : 'مرحباً بك',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: ZadTokens.s1 + 2),
                            const Text(
                              'زادك اليومي لتنظيم الميزانية وأدوار المحظرة',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Colors.white70,
                              ),
                            ),
                            if (authService.isAdmin) ...[
                              const SizedBox(height: ZadTokens.s4),
                              Row(
                                children: [
                                  const Text(
                                    '75%',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: ZadTokens.s2),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: const LinearProgressIndicator(
                                        value: 0.75,
                                        minHeight: 6,
                                        color: ZadTokens.gold,
                                        backgroundColor: Colors.white24,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: ZadTokens.s2),
                                  const Text(
                                    'من عدد اليوم',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const ZadSectionHeader('أقسام التطبيق'),
              _sectionGrid(context, isAdmin: authService.isAdmin),
              const SizedBox(height: ZadTokens.s4),
              _ActivityCard(isAdmin: authService.isAdmin),
              const SizedBox(height: ZadTokens.s5),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: ZadTokens.danger,
                  side: const BorderSide(color: ZadTokens.danger),
                ),
                icon: const Icon(Icons.logout, size: 20),
                label: const Text('تسجيل الخروج'),
                onPressed: () async {
                  final ok = await zadConfirm(
                    context,
                    title: 'تأكيد الخروج',
                    body: 'هل تريد الخروج من التطبيق؟',
                    confirmLabel: 'خروج',
                  );
                  if (ok) authService.logout();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Admin: 2x2 grid of 4 subtitled cards (Stitch home_admin).
  /// Normal user: 2 cards + full-width horizontal notifications row
  /// (Stitch home_student), so the grid never shows an empty slot.
  Widget _sectionGrid(BuildContext context, {required bool isAdmin}) {
    // Very small stagger (40ms steps) so the cards settle in calmly.
    final budget = ZadAnimatedEntry(
      delay: const Duration(milliseconds: 40),
      child: ZadActionCard(
        icon: Icons.account_balance_wallet_outlined,
        title: 'ميزانيتي',
        subtitle: 'تتبع مصاريفك اليومية',
        onTap: () => context.push('/budget'),
      ),
    );
    final teams = ZadAnimatedEntry(
      delay: const Duration(milliseconds: 80),
      child: ZadActionCard(
        icon: Icons.group_outlined,
        title: 'الفرق',
        subtitle: 'الفرق وأدوار المطبخ',
        onTap: () => context.push('/teams'),
      ),
    );

    Widget grid(List<Widget> children, {required double ratio}) =>
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: ZadTokens.s3,
          crossAxisSpacing: ZadTokens.s3,
          childAspectRatio: ratio,
          children: children,
        );

    if (isAdmin) {
      // 1.25 fits icon disk + title + subtitle at 320px width.
      return grid(ratio: 1.25, [
        budget,
        teams,
        ZadAnimatedEntry(
          delay: const Duration(milliseconds: 120),
          child: ZadActionCard(
            icon: Icons.notifications_outlined,
            title: 'الإشعارات',
            subtitle: 'كل التنبيهات',
            onTap: () => context.push('/notifications'),
          ),
        ),
        ZadAnimatedEntry(
          delay: const Duration(milliseconds: 160),
          child: ZadActionCard(
            icon: Icons.admin_panel_settings_outlined,
            title: 'الإدارة',
            subtitle: 'إعدادات النظام',
            accent: true,
            onTap: () => context.push('/admin'),
          ),
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        grid(ratio: 1.25, [budget, teams]),
        const SizedBox(height: ZadTokens.s3),
        // Full-width horizontal notifications row (Stitch home_student).
        ZadAnimatedEntry(
          delay: const Duration(milliseconds: 120),
          child: Material(
            color: ZadTokens.surface,
            elevation: 1,
            shadowColor: const Color(0x22000000),
            borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
            child: InkWell(
              onTap: () => context.push('/notifications'),
              borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
              child: Padding(
                padding: const EdgeInsets.all(ZadTokens.s3),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ZadTokens.primary.withValues(alpha: 0.10),
                      ),
                      child: const Icon(
                        Icons.notifications_outlined,
                        size: 22,
                        color: ZadTokens.primary,
                      ),
                    ),
                    const SizedBox(width: ZadTokens.s3),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الإشعارات',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: ZadTokens.text,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'كل تنبيهات الميزانية والفرق',
                            style: TextStyle(
                              fontSize: 12,
                              color: ZadTokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_left, color: ZadTokens.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final bool isAdmin;
  const _ActivityCard({required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final rows = isAdmin
        ? const [
            ('الإدارة', 'إعدادات النظام', Icons.admin_panel_settings_outlined),
            (
              'الإشعارات',
              'تنبيهات الميزانية والفرق',
              Icons.notifications_outlined,
            ),
          ]
        : const [
            ('النوبات اليومية', 'تحقق من جدول الدور المستقر', Icons.history),
            (
              'ميزانية الفريق',
              'راجع حدود الصرف لهذا الأسبوع',
              Icons.wallet_outlined,
            ),
          ];
    return Container(
      decoration: BoxDecoration(
        color: ZadTokens.surface,
        borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
        border: Border.all(color: ZadTokens.goldSoft.withValues(alpha: 0.6)),
        boxShadow: ZadTokens.cardShadow,
      ),
      child: Column(
        children: [
          for (final row in rows) ...[
            ListTile(
              dense: true,
              leading: Icon(row.$3, color: ZadTokens.primary, size: 20),
              title: Text(
                row.$1,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(row.$2, style: const TextStyle(fontSize: 11.5)),
              trailing: const Icon(
                Icons.chevron_left,
                color: ZadTokens.textMuted,
              ),
            ),
            if (row != rows.last) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}
