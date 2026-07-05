import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/notifications/presentation/notifications_screen.dart';

void main() {
  testWidgets(
    'clearly reads as a planned/coming-soon feature, not an ambiguous '
    'empty inbox',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: NotificationsScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('التنبيهات قادمة قريبًا'), findsOneWidget);
      expect(
        find.text(
          'نعمل على إضافة التنبيهات لمساعدتك في متابعة ميزانيتك وفرقك. '
          'لا حاجة لأي إجراء منك الآن.',
        ),
        findsOneWidget,
      );

      // The old ambiguous "empty inbox" wording must be gone.
      expect(find.text('لا توجد تنبيهات حالياً'), findsNothing);
      expect(
        find.text(
          'ستظهر التنبيهات هنا قريباً. سنقوم بإشعارك عند وجود تحديثات '
          'جديدة في ميزانيتك أو فرقك الدراسية.',
        ),
        findsNothing,
      );
    },
  );
}
