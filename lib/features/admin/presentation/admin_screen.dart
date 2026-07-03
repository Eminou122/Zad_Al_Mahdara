import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_empty_state.dart';
import '../../../core/widgets/zad_scaffold.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Stitch admin_panel style (big shield circle + title + body + button),
    // with placeholder semantics: this screen is shown TO admins.
    return ZadScaffold(
      title: 'لوحة الإدارة',
      body: Padding(
        padding: const EdgeInsets.only(top: ZadTokens.s6),
        child: ZadAnimatedEntry(
          child: ZadEmptyState(
            big: true,
            icon: Icons.admin_panel_settings_outlined,
            title: 'لوحة الإدارة قيد الإعداد',
            message:
                'هذه الصفحة مخصصة للمؤسس والمسؤولين فقط. ستتوفر أدوات الإدارة هنا قريباً.',
            action: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.home_outlined),
                label: const Text('العودة للرئيسية'),
                onPressed: () => context.pop(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
