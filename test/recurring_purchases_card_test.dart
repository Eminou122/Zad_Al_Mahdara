import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/budget/domain/budget_models.dart';
import 'package:zad_al_mahdara/features/budget/presentation/widgets/recurring_purchases_card.dart';

void main() {
  final purchase = RecurringPurchase(
    id: 'rp-1',
    name: 'خبز',
    price: 20,
    frequency: 'daily',
    startDate: DateTime(2026, 7, 1),
    endDate: DateTime(2026, 7, 30),
    isActive: true,
  );

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows empty state with manage button when no items', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        RecurringPurchasesCard(
          stats: null,
          items: const [],
          todayItems: const [],
          onManage: () {},
        ),
      ),
    );

    expect(find.text('لا توجد مشتريات يومية متكررة بعد'), findsOneWidget);
    expect(find.text('إدارة المشتريات المتكررة'), findsOneWidget);
  });

  testWidgets('shows planned, actual and saved totals from stats', (
    tester,
  ) async {
    const stats = RecurringPurchaseOverview(
      activeRecurringCount: 1,
      todayExpectedTotal: 20,
      todayPurchasedTotal: 0,
      todaySkippedCount: 0,
      plannedTotal: 600,
      actualPurchasedTotal: 400,
      skippedTotal: 40,
      skippedCount: 2,
    );

    await tester.pumpWidget(
      host(
        RecurringPurchasesCard(
          stats: stats,
          items: [purchase],
          todayItems: const [],
          onManage: () {},
        ),
      ),
    );

    expect(find.text('600.00 MRU'), findsOneWidget);
    expect(find.text('400.00 MRU'), findsOneWidget);
    // saved = planned - actual = 200.00, distinct from skippedTotal (40.00)
    expect(find.text('200.00 MRU'), findsOneWidget);
    expect(find.text('خبز'), findsOneWidget);
    expect(find.text('20.00 MRU'), findsOneWidget);
  });

  testWidgets('shows today status for a scheduled item when available', (
    tester,
  ) async {
    final today = TodayRecurringPurchase(
      recurringPurchaseId: 'rp-1',
      name: 'خبز',
      price: 20,
      frequency: 'daily',
      occurrenceDate: DateTime(2026, 7, 3),
      status: 'purchased',
    );

    await tester.pumpWidget(
      host(
        RecurringPurchasesCard(
          stats: null,
          items: [purchase],
          todayItems: [today],
          onManage: () {},
        ),
      ),
    );

    expect(find.textContaining('تم الشراء اليوم'), findsOneWidget);
  });

  testWidgets('does not overflow at a 320px-wide viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const stats = RecurringPurchaseOverview(
      activeRecurringCount: 1,
      todayExpectedTotal: 20,
      todayPurchasedTotal: 0,
      todaySkippedCount: 0,
      plannedTotal: 600,
      actualPurchasedTotal: 400,
      skippedTotal: 40,
      skippedCount: 2,
    );
    final longName = RecurringPurchase(
      id: 'rp-2',
      name: 'اسم طويل جداً لعنصر شراء متكرر يومي في الأسواق المحلية',
      price: 1234.5,
      frequency: 'every_n_days',
      intervalDays: 3,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 30),
      isActive: true,
    );

    await tester.pumpWidget(
      host(
        RecurringPurchasesCard(
          stats: stats,
          items: [purchase, longName],
          todayItems: const [],
          onManage: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
