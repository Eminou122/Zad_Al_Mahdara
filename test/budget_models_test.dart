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
}
