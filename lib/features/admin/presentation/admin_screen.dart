import 'package:flutter/material.dart';
import '../../../core/widgets/tip_card.dart';
import '../../../core/widgets/zad_empty_state.dart';
import '../../../core/widgets/zad_scaffold.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ZadScaffold(
      title: 'لوحة الإدارة',
      body: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TipCard('هذه الصفحة مخصصة للمؤسس والمسؤولين فقط'),
          ZadEmptyState(
            icon: Icons.admin_panel_settings_outlined,
            message: 'لا توجد بيانات إدارية بعد',
          ),
        ],
      ),
    );
  }
}
