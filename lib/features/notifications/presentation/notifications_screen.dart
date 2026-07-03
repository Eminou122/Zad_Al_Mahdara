import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_scaffold.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ZadScaffold(
      title: 'الإشعارات',
      body: Padding(
        padding: const EdgeInsets.only(top: 260),
        child: ZadAnimatedEntry(
          child: Column(
            children: [
              Container(
                width: 134,
                height: 134,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZadTokens.surfaceContainer,
                  border: Border.all(color: ZadTokens.goldSoft),
                  boxShadow: ZadTokens.cardShadow,
                ),
                child: const Icon(
                  Icons.notifications_none_outlined,
                  size: 58,
                  color: ZadTokens.primaryDark,
                ),
              ),
              const SizedBox(height: ZadTokens.s5),
              Text(
                'لا توجد تنبيهات حالياً',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: ZadTokens.s2),
              const Text(
                'ستظهر التنبيهات هنا قريباً عند وجود تحديثات جديدة في ميزانيتك أو فرقك.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ZadTokens.textMuted),
              ),
              const SizedBox(height: ZadTokens.s5),
              SizedBox(
                width: 150,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('تحديث الصفحة'),
                  onPressed: () => context.go('/notifications'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
