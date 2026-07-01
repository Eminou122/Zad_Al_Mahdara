import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../core/widgets/tip_card.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ZadScaffold(
      title: 'الإشعارات',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TipCard('ستصلك هنا إشعارات الميزانية والفريق وموافقات القائد'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'لا توجد إشعارات',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.pop(),
            child: const Text('رجوع'),
          ),
        ],
      ),
    );
  }
}
