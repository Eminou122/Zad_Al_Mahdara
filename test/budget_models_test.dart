import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/budget/domain/budget_models.dart';

void main() {
  group('BudgetOverview.fromJson', () {
    test('parses plan + summary correctly', () {
      final json = {
        'budget_plan': {
          'id': 'plan-1',
          'total_money': 1000,
          'start_date': '2026-06-01',
          'end_date': '2026-06-30',
          'note': null,
          'is_active': true,
        },
        'summary': {
          'days_total': 30,
          'days_remaining': 10,
          'total_spent': 200.50,
          'subscription_total': 100,
          'remaining_money': 699.50,
          'safe_daily_limit': 69.95,
          'today_spending': 50,
          'is_over_daily_limit': false,
          'planned_recurring_total': 350,
          'actual_recurring_total': 25,
          'skipped_recurring_total': 50,
          'skipped_recurring_count': 2,
          'today_recurring_expected_total': 25,
          'today_recurring_purchased_total': 25,
          'today_recurring_skipped_count': 0,
        },
        'active_subscriptions': [
          {
            'id': 'sub-1',
            'name': 'عشاء',
            'amount': 100,
            'start_date': '2026-06-01',
            'end_date': '2026-06-30',
            'notify_days_before': 3,
            'is_active': true,
          },
        ],
        'recent_expenses': [
          {
            'id': 'exp-1',
            'item_name': 'كتب',
            'amount': 50,
            'category': null,
            'note': null,
            'expense_date': '2026-06-20',
            'source': 'manual',
          },
        ],
      };

      final ov = BudgetOverview.fromJson(json);

      expect(ov.budgetPlan, isNotNull);
      expect(ov.budgetPlan!.totalMoney, 1000.0);
      expect(ov.budgetPlan!.startDate, DateTime(2026, 6, 1));
      expect(ov.budgetPlan!.note, isNull);

      expect(ov.summary, isNotNull);
      expect(ov.summary!.daysTotal, 30);
      expect(ov.summary!.remainingMoney, closeTo(699.50, 0.001));
      expect(ov.summary!.isOverDailyLimit, isFalse);
      expect(ov.summary!.plannedRecurringTotal, 350);
      expect(ov.summary!.actualRecurringTotal, 25);
      expect(ov.summary!.skippedRecurringCount, 2);

      expect(ov.activeSubscriptions.length, 1);
      expect(ov.activeSubscriptions.first.name, 'عشاء');

      expect(ov.recentExpenses.length, 1);
      expect(ov.recentExpenses.first.itemName, 'كتب');
      expect(ov.recentExpenses.first.category, isNull);
    });

    test('parses no-plan overview correctly', () {
      final json = {
        'budget_plan': null,
        'summary': null,
        'active_subscriptions': <dynamic>[],
        'recent_expenses': <dynamic>[],
      };

      final ov = BudgetOverview.fromJson(json);

      expect(ov.budgetPlan, isNull);
      expect(ov.summary, isNull);
      expect(ov.activeSubscriptions, isEmpty);
      expect(ov.recentExpenses, isEmpty);
    });
  });

  group('recurring purchase models', () {
    test('parse recurring purchase', () {
      final item = RecurringPurchase.fromJson({
        'id': 'rp-1',
        'name': 'حليب',
        'price': 25,
        'frequency': 'every_n_days',
        'interval_days': 2,
        'start_date': '2026-07-01',
        'end_date': '2026-07-14',
        'reminder_time': '08:00',
        'note': null,
        'is_active': true,
      });

      expect(item.name, 'حليب');
      expect(item.price, 25);
      expect(item.intervalDays, 2);
      expect(item.reminderTime, '08:00');
    });

    test('parse today checklist status', () {
      final item = TodayRecurringPurchase.fromJson({
        'recurring_purchase_id': 'rp-1',
        'occurrence_id': null,
        'name': 'خبز',
        'price': 50,
        'frequency': 'daily',
        'interval_days': null,
        'reminder_time': null,
        'note': null,
        'occurrence_date': '2026-07-01',
        'status': 'unmarked',
        'expense_id': null,
      });

      expect(item.status, 'unmarked');
      expect(item.occurrenceDate, DateTime(2026, 7, 1));
    });
  });

  group('toJson roundtrip', () {
    test('BudgetPlan roundtrip', () {
      final original = BudgetPlan(
        id: 'plan-1',
        totalMoney: 1000,
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 30),
        note: 'ملاحظة',
        isActive: true,
      );
      final json = original.toJson();
      final restored = BudgetPlan.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.totalMoney, original.totalMoney);
      expect(restored.startDate, original.startDate);
      expect(restored.endDate, original.endDate);
      expect(restored.note, original.note);
      expect(restored.isActive, original.isActive);
    });

    test('BudgetPlan roundtrip with null note', () {
      final original = BudgetPlan(
        id: 'plan-2',
        totalMoney: 500,
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 15),
        isActive: false,
      );
      final json = original.toJson();
      final restored = BudgetPlan.fromJson(json);
      expect(restored.note, isNull);
      expect(restored.isActive, false);
    });

    test('BudgetSummary roundtrip', () {
      final original = BudgetSummary(
        daysTotal: 30,
        daysRemaining: 10,
        totalSpent: 200.5,
        subscriptionTotal: 100,
        remainingMoney: 699.5,
        safeDailyLimit: 69.95,
        todaySpending: 50,
        isOverDailyLimit: false,
        plannedRecurringTotal: 350,
        actualRecurringTotal: 25,
        skippedRecurringTotal: 50,
        skippedRecurringCount: 2,
        todayRecurringExpectedTotal: 25,
        todayRecurringPurchasedTotal: 25,
        todayRecurringSkippedCount: 0,
      );
      final json = original.toJson();
      final restored = BudgetSummary.fromJson(json);
      expect(restored.daysTotal, original.daysTotal);
      expect(restored.daysRemaining, original.daysRemaining);
      expect(restored.totalSpent, original.totalSpent);
      expect(restored.subscriptionTotal, original.subscriptionTotal);
      expect(restored.remainingMoney, original.remainingMoney);
      expect(restored.safeDailyLimit, original.safeDailyLimit);
      expect(restored.todaySpending, original.todaySpending);
      expect(restored.isOverDailyLimit, original.isOverDailyLimit);
      expect(restored.plannedRecurringTotal, original.plannedRecurringTotal);
      expect(restored.actualRecurringTotal, original.actualRecurringTotal);
      expect(restored.skippedRecurringTotal, original.skippedRecurringTotal);
      expect(restored.skippedRecurringCount, original.skippedRecurringCount);
      expect(
        restored.todayRecurringExpectedTotal,
        original.todayRecurringExpectedTotal,
      );
      expect(
        restored.todayRecurringPurchasedTotal,
        original.todayRecurringPurchasedTotal,
      );
      expect(
        restored.todayRecurringSkippedCount,
        original.todayRecurringSkippedCount,
      );
    });

    test('AppSubscription roundtrip', () {
      final original = AppSubscription(
        id: 'sub-1',
        name: 'عشاء',
        amount: 100,
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 6, 30),
        notifyDaysBefore: 3,
        isActive: true,
      );
      final json = original.toJson();
      final restored = AppSubscription.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.amount, original.amount);
      expect(restored.startDate, original.startDate);
      expect(restored.endDate, original.endDate);
      expect(restored.notifyDaysBefore, original.notifyDaysBefore);
      expect(restored.isActive, original.isActive);
    });

    test('Expense roundtrip', () {
      final original = Expense(
        id: 'exp-1',
        itemName: 'كتب',
        amount: 50,
        category: 'كتب',
        note: 'ملاحظة',
        expenseDate: DateTime(2026, 6, 20),
        source: 'manual',
      );
      final json = original.toJson();
      final restored = Expense.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.itemName, original.itemName);
      expect(restored.amount, original.amount);
      expect(restored.category, original.category);
      expect(restored.note, original.note);
      expect(restored.expenseDate, original.expenseDate);
      expect(restored.source, original.source);
    });

    test('Expense roundtrip with null category and note', () {
      final original = Expense(
        id: 'exp-2',
        itemName: 'خبز',
        amount: 25,
        expenseDate: DateTime(2026, 6, 21),
        source: 'recurring_purchase',
      );
      final json = original.toJson();
      final restored = Expense.fromJson(json);
      expect(restored.category, isNull);
      expect(restored.note, isNull);
      expect(restored.source, 'recurring_purchase');
    });

    test('BudgetOverview roundtrip', () {
      final plan = BudgetPlan(
        id: 'plan-1',
        totalMoney: 1000,
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 30),
        isActive: true,
      );
      final summary = BudgetSummary(
        daysTotal: 30,
        daysRemaining: 10,
        totalSpent: 200.5,
        subscriptionTotal: 100,
        remainingMoney: 699.5,
        safeDailyLimit: 69.95,
        todaySpending: 50,
        isOverDailyLimit: false,
        plannedRecurringTotal: 350,
        actualRecurringTotal: 25,
        skippedRecurringTotal: 50,
        skippedRecurringCount: 2,
        todayRecurringExpectedTotal: 25,
        todayRecurringPurchasedTotal: 25,
        todayRecurringSkippedCount: 0,
      );
      final sub = AppSubscription(
        id: 'sub-1',
        name: 'عشاء',
        amount: 100,
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 6, 30),
        notifyDaysBefore: 3,
        isActive: true,
      );
      final expense = Expense(
        id: 'exp-1',
        itemName: 'كتب',
        amount: 50,
        expenseDate: DateTime(2026, 6, 20),
        source: 'manual',
      );
      final original = BudgetOverview(
        budgetPlan: plan,
        summary: summary,
        activeSubscriptions: [sub],
        recentExpenses: [expense],
      );
      final json = original.toJson();
      final restored = BudgetOverview.fromJson(json);
      expect(restored.budgetPlan, isNotNull);
      expect(restored.budgetPlan!.id, plan.id);
      expect(restored.summary, isNotNull);
      expect(restored.summary!.remainingMoney, summary.remainingMoney);
      expect(restored.activeSubscriptions.length, 1);
      expect(restored.activeSubscriptions.first.name, 'عشاء');
      expect(restored.recentExpenses.length, 1);
      expect(restored.recentExpenses.first.itemName, 'كتب');
    });

    test('BudgetOverview roundtrip with null plan/summary', () {
      final original = BudgetOverview(
        budgetPlan: null,
        summary: null,
        activeSubscriptions: const [],
        recentExpenses: const [],
      );
      final json = original.toJson();
      final restored = BudgetOverview.fromJson(json);
      expect(restored.budgetPlan, isNull);
      expect(restored.summary, isNull);
      expect(restored.activeSubscriptions, isEmpty);
      expect(restored.recentExpenses, isEmpty);
    });

    test('RecurringPurchase roundtrip', () {
      final original = RecurringPurchase(
        id: 'rp-1',
        name: 'حليب',
        price: 25,
        frequency: 'every_n_days',
        intervalDays: 2,
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 14),
        reminderTime: '08:00',
        note: 'ملاحظة',
        isActive: true,
      );
      final json = original.toJson();
      final restored = RecurringPurchase.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.price, original.price);
      expect(restored.frequency, original.frequency);
      expect(restored.intervalDays, original.intervalDays);
      expect(restored.startDate, original.startDate);
      expect(restored.endDate, original.endDate);
      expect(restored.reminderTime, original.reminderTime);
      expect(restored.note, original.note);
      expect(restored.isActive, original.isActive);
    });

    test(
      'RecurringPurchase roundtrip with null intervalDays/reminderTime/note',
      () {
        final original = RecurringPurchase(
          id: 'rp-2',
          name: 'خبز',
          price: 50,
          frequency: 'daily',
          startDate: DateTime(2026, 7, 1),
          endDate: DateTime(2026, 7, 30),
          isActive: true,
        );
        final json = original.toJson();
        final restored = RecurringPurchase.fromJson(json);
        expect(restored.intervalDays, isNull);
        expect(restored.reminderTime, isNull);
        expect(restored.note, isNull);
      },
    );

    test('TodayRecurringPurchase roundtrip', () {
      final original = TodayRecurringPurchase(
        recurringPurchaseId: 'rp-1',
        occurrenceId: 'occ-1',
        name: 'خبز',
        price: 50,
        frequency: 'daily',
        intervalDays: null,
        reminderTime: null,
        note: null,
        occurrenceDate: DateTime(2026, 7, 1),
        status: 'unmarked',
        expenseId: 'exp-1',
      );
      final json = original.toJson();
      final restored = TodayRecurringPurchase.fromJson(json);
      expect(restored.recurringPurchaseId, original.recurringPurchaseId);
      expect(restored.occurrenceId, original.occurrenceId);
      expect(restored.name, original.name);
      expect(restored.price, original.price);
      expect(restored.frequency, original.frequency);
      expect(restored.intervalDays, original.intervalDays);
      expect(restored.reminderTime, original.reminderTime);
      expect(restored.note, original.note);
      expect(restored.occurrenceDate, original.occurrenceDate);
      expect(restored.status, original.status);
      expect(restored.expenseId, original.expenseId);
    });

    test('TodayRecurringPurchase roundtrip with null optional fields', () {
      final original = TodayRecurringPurchase(
        recurringPurchaseId: 'rp-2',
        name: 'حليب',
        price: 25,
        frequency: 'daily',
        occurrenceDate: DateTime(2026, 7, 2),
        status: 'purchased',
      );
      final json = original.toJson();
      final restored = TodayRecurringPurchase.fromJson(json);
      expect(restored.occurrenceId, isNull);
      expect(restored.expenseId, isNull);
      expect(restored.intervalDays, isNull);
      expect(restored.reminderTime, isNull);
      expect(restored.note, isNull);
    });

    test('RecurringPurchaseOverview roundtrip', () {
      final original = RecurringPurchaseOverview(
        activeRecurringCount: 3,
        todayExpectedTotal: 100,
        todayPurchasedTotal: 50,
        todaySkippedCount: 1,
        plannedTotal: 900,
        actualPurchasedTotal: 600,
        skippedTotal: 40,
        skippedCount: 2,
      );
      final json = original.toJson();
      final restored = RecurringPurchaseOverview.fromJson(json);
      expect(restored.activeRecurringCount, original.activeRecurringCount);
      expect(restored.todayExpectedTotal, original.todayExpectedTotal);
      expect(restored.todayPurchasedTotal, original.todayPurchasedTotal);
      expect(restored.todaySkippedCount, original.todaySkippedCount);
      expect(restored.plannedTotal, original.plannedTotal);
      expect(restored.actualPurchasedTotal, original.actualPurchasedTotal);
      expect(restored.skippedTotal, original.skippedTotal);
      expect(restored.skippedCount, original.skippedCount);
    });
  });
}
