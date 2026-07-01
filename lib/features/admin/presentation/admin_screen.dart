import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../core/widgets/tip_card.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ZadScaffold(
      title: 'لوحة الإدارة',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TipCard('هذه اللوحة خاصة بالمؤسس والمسؤولين — رقم المؤسس: 49413435'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'لا توجد بيانات إدارية بعد',
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
