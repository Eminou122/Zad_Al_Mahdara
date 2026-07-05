import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/budget/domain/budget_models.dart';
import 'package:zad_al_mahdara/features/budget/presentation/widgets/spending_progress_card.dart';

void main() {
  final start = DateTime(2026, 7);
  final end = DateTime(2026, 7, 30);

  testWidgets('shows consumption from remaining amount', (tester) async {
    final plan = BudgetPlan(
      id: 'plan-1',
      totalMoney: 1000,
      startDate: start,
      endDate: end,
      isActive: true,
    );
    const summary = BudgetSummary(
      daysTotal: 30,
      daysRemaining: 10,
      totalSpent: 200,
      subscriptionTotal: 100,
      remainingMoney: 700,
      safeDailyLimit: 70,
      todaySpending: 0,
      isOverDailyLimit: false,
      plannedRecurringTotal: 0,
      actualRecurringTotal: 0,
      skippedRecurringTotal: 0,
      skippedRecurringCount: 0,
      todayRecurringExpectedTotal: 0,
      todayRecurringPurchasedTotal: 0,
      todayRecurringSkippedCount: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpendingProgressCard(plan: plan, summary: summary),
        ),
      ),
    );

    expect(find.text('30%'), findsOneWidget);
    expect(find.text('300.00 / 1000.00 MRU'), findsOneWidget);
  });

  testWidgets('does not overflow at 320px viewport with large numbers', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final plan = BudgetPlan(
      id: 'plan-1',
      totalMoney: 999999.99,
      startDate: start,
      endDate: end,
      isActive: true,
    );
    const summary = BudgetSummary(
      daysTotal: 30,
      daysRemaining: 5,
      totalSpent: 500000,
      subscriptionTotal: 100000,
      remainingMoney: 399999.99,
      safeDailyLimit: 70000,
      todaySpending: 25000.50,
      isOverDailyLimit: false,
      plannedRecurringTotal: 0,
      actualRecurringTotal: 0,
      skippedRecurringTotal: 0,
      skippedRecurringCount: 0,
      todayRecurringExpectedTotal: 0,
      todayRecurringPurchasedTotal: 0,
      todayRecurringSkippedCount: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpendingProgressCard(plan: plan, summary: summary),
        ),
      ),
    );

    expect(find.textContaining('%'), findsOneWidget);
    expect(find.textContaining('MRU'), findsAtLeast(2));
    expect(find.textContaining('الوضع جيد'), findsOneWidget);
  });

}
