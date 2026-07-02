import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_action_card.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_confirm.dart';
import '../../../core/widgets/zad_logo_badge.dart';
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
              ZadCard(
                highlighted: true,
                child: Row(
                  children: [
                    const ZadLogoBadge(size: 56),
                    const SizedBox(width: ZadTokens.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isNotEmpty ? 'مرحباً، $name' : 'مرحباً بك',
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: ZadTokens.s1),
                          const Text(
                            'زادك اليومي لتنظيم الميزانية وأدوار المحظرة',
                            style: TextStyle(
                              fontSize: 13,
                              color: ZadTokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const ZadSectionHeader('أقسام التطبيق'),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: ZadTokens.s3,
                crossAxisSpacing: ZadTokens.s3,
                // 1.75 leaves room for two-line Arabic labels at 320px width.
                childAspectRatio: 1.75,
                children: [
                  ZadActionCard(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'ميزانيتي',
                    onTap: () => context.push('/budget'),
                  ),
                  ZadActionCard(
                    icon: Icons.group_outlined,
                    title: 'الفرق',
                    onTap: () => context.push('/teams'),
                  ),
                  ZadActionCard(
                    icon: Icons.notifications_outlined,
                    title: 'الإشعارات',
                    onTap: () => context.push('/notifications'),
                  ),
                  if (authService.isAdmin)
                    ZadActionCard(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'الإدارة',
                      accent: true,
                      onTap: () => context.push('/admin'),
                    ),
                ],
              ),
              const SizedBox(height: ZadTokens.s5),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: ZadTokens.danger,
                  side: const BorderSide(color: ZadTokens.danger),
                ),
                icon: const Icon(Icons.logout, size: 20),
                label: const Text('خروج'),
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
}
