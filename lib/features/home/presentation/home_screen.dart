import 'package:flutter/material.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_confirm.dart';
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
              // Green hero welcome banner (Stitch), text-only, white on green.
              ZadAnimatedEntry(
                child: Container(
                  padding: const EdgeInsets.all(ZadTokens.s5),
                  decoration: BoxDecoration(
                    gradient: ZadTokens.heroGradient,
                    borderRadius: BorderRadius.circular(ZadTokens.radiusLg),
                    boxShadow: ZadTokens.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? 'مرحباً، $name' : 'مرحباً بك',
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: ZadTokens.s1 + 2),
                      const Text(
                        'زادك اليومي لتنظيم الميزانية وأدوار المحظرة',
                        style: TextStyle(fontSize: 13.5, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
              // Navigation lives in the bottom bar; these rows are help only:
              // tapping opens an explanation sheet, never navigates.
              const ZadSectionHeader('دليل سريع'),
              ..._tips(context, isAdmin: authService.isAdmin),
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

  List<Widget> _tips(BuildContext context, {required bool isAdmin}) {
    final tips = [
      (
        Icons.account_balance_wallet_outlined,
        ZadTokens.goldDark,
        ZadTokens.gold.withValues(alpha: 0.16),
        'ابدأ من الميزانية',
        'حدّد ميزانيتك لتعرف مصروفك الآمن كل يوم.',
        [
          'حدّد ميزانيتك الشهرية أو الأسبوعية.',
          'سجّل مصاريفك اليومية.',
          'راقب المصروف الآمن لكل يوم.',
          'اللون الأخضر يعني أن وضعك جيد، والأصفر يعني انتبه، '
              'والأحمر يعني أنك تجاوزت الحد.',
        ],
      ),
      (
        Icons.groups_outlined,
        ZadTokens.primary,
        ZadTokens.primary.withValues(alpha: 0.10),
        'نظّم أدوار الفريق',
        'تابع المسؤول اليومي ومن عليه الدور بعده.',
        [
          'أنشئ فريقاً للفطور أو الغداء أو العشاء.',
          'أضف أعضاء الفريق أو طلاباً بدون حساب.',
          'تابع المسؤول اليومي ومن عليه الدور بعده.',
          'يمكن للقائد تعطيل أو إعادة تفعيل الأعضاء عند الحاجة.',
        ],
      ),
      (
        Icons.notifications_outlined,
        ZadTokens.primaryDark,
        ZadTokens.surfaceContainer,
        'تابع التنبيهات',
        'ستظهر هنا التذكيرات المهمة عند توفرها.',
        [
          'ستظهر هنا التذكيرات المهمة مستقبلاً.',
          'يمكن أن تساعدك التنبيهات على متابعة الميزانية والفرق.',
          'حالياً الصفحة في وضع الانتظار حتى تتوفر التنبيهات.',
        ],
      ),
      if (isAdmin)
        (
          Icons.admin_panel_settings_outlined,
          ZadTokens.primary,
          ZadTokens.primary.withValues(alpha: 0.10),
          'لوحة الإدارة',
          'ستتوفر أدوات الإدارة هنا قريباً.',
          [
            'هذه الصفحة مخصصة للمؤسس والمسؤولين فقط.',
            'ستتوفر أدوات الإدارة هنا لاحقاً.',
            'لا تظهر هذه الإرشادات للمستخدمين العاديين إلا إذا كانوا مسؤولين.',
          ],
        ),
    ];
    return [
      for (final (i, (icon, color, tint, title, body, points))
          in tips.indexed) ...[
        if (i > 0) const SizedBox(height: ZadTokens.s2),
        ZadAnimatedEntry(
          delay: Duration(milliseconds: 40 * (i + 1)),
          child: _TipRow(
            icon: icon,
            iconColor: color,
            tint: tint,
            title: title,
            body: body,
            onTap: () => _showGuide(
              context,
              icon: icon,
              iconColor: color,
              tint: tint,
              title: title,
              points: points,
            ),
          ),
        ),
      ],
    ];
  }

  /// Explanation bottom sheet (Stitch-like): icon disk + title, bullet
  /// lines, green "فهمت" button. Informational only — never navigates.
  void _showGuide(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Color tint,
    required String title,
    required List<String> points,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ZadTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ZadTokens.radiusLg),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ZadTokens.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 24, color: iconColor),
                  ),
                  const SizedBox(width: ZadTokens.s3),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZadTokens.s4),
              for (final point in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: ZadTokens.s3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: ZadTokens.gold,
                          ),
                        ),
                      ),
                      const SizedBox(width: ZadTokens.s2 + 2),
                      Expanded(
                        child: Text(
                          point,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.5,
                            color: ZadTokens.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: ZadTokens.s2),
              ElevatedButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('فهمت'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Guidance row (Stitch list-card style): tinted icon tile, title, one-line
/// tip, info affordance. Help content — the bottom nav is the navigation.
class _TipRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color tint;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _TipRow({
    required this.icon,
    required this.iconColor,
    required this.tint,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZadTokens.surface,
      elevation: 1,
      shadowColor: const Color(0x14000000),
      borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
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
                  color: tint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: ZadTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: ZadTokens.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ZadTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Info affordance, not a navigation chevron.
              const Icon(
                Icons.info_outline,
                size: 20,
                color: ZadTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
