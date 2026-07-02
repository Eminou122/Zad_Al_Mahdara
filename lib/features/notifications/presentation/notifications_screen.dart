import 'package:flutter/material.dart';
import '../../../core/widgets/tip_card.dart';
import '../../../core/widgets/zad_empty_state.dart';
import '../../../core/widgets/zad_scaffold.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ZadScaffold(
      title: 'الإشعارات',
      body: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TipCard('ستصلك هنا إشعارات الميزانية والفريق وموافقات القائد'),
          ZadEmptyState(
            icon: Icons.notifications_none_outlined,
            message: 'لا توجد إشعارات',
          ),
        ],
      ),
    );
  }
}
