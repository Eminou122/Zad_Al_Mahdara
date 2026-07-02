import 'package:flutter/material.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_empty_state.dart';
import '../../../core/widgets/zad_scaffold.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Stitch notifications: large centered empty state, no extra chrome.
    return ZadScaffold(
      title: 'الإشعارات',
      body: const Padding(
        padding: EdgeInsets.only(top: ZadTokens.s6),
        child: ZadAnimatedEntry(
          child: ZadEmptyState(
            big: true,
            icon: Icons.notifications_none_outlined,
            title: 'لا توجد تنبيهات حالياً',
            message:
                'ستظهر التنبيهات هنا قريباً — سنقوم بإشعارك عند وجود تحديثات جديدة في ميزانيتك أو فرقك.',
          ),
        ),
      ),
    );
  }
}
