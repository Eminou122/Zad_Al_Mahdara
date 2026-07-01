import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../core/widgets/tip_card.dart';
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
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
            ),
          );
        }
        final name = authService.displayName;
        return ZadScaffold(
          title: 'الرئيسية',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TipCard(
                name.isNotEmpty
                    ? 'مرحباً $name في زاد المحظرة'
                    : 'مرحباً بك في زاد المحظرة',
              ),
              _tile(context, 'ميزانيتي', Icons.account_balance_wallet, '/budget'),
              _tile(context, 'الفرق', Icons.group, '/teams'),
              _tile(context, 'الإشعارات', Icons.notifications_outlined, '/notifications'),
              if (authService.isAdmin)
                _tile(
                  context,
                  'لوحة الإدارة',
                  Icons.admin_panel_settings_outlined,
                  '/admin',
                ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('تأكيد الخروج'),
                      content: const Text('هل تريد الخروج من التطبيق؟'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('إلغاء'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('خروج'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) authService.logout();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6D4C41),
                ),
                child: const Text('خروج'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext ctx, String label, IconData icon, String route) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: Icon(icon, color: const Color(0xFF2E7D32)),
          title: Text(label),
          onTap: () => ctx.push(route),
        ),
      );
}
