import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/budget/data/budget_service.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

Map<String, dynamic> _response(bool removed) => {
  'ok': true,
  'removed': removed,
  'today_items': [
    {
      'recurring_purchase_id': 'purchase-1',
      'occurrence_id': 'occ-1',
      'name': 'Milk',
      'price': 12.5,
      'frequency': 'daily',
      'interval_days': null,
      'reminder_time': null,
      'note': null,
      'occurrence_date': '2026-02-03',
      'status': 'purchased',
      'is_voided': false,
      'expense_id': 'expense-1',
    },
    {
      'recurring_purchase_id': 'purchase-2',
      'occurrence_id': 'occ-2',
      'name': 'Bread',
      'price': 3,
      'frequency': 'daily',
      'interval_days': null,
      'reminder_time': null,
      'note': null,
      'occurrence_date': '2026-02-03',
      'status': 'purchased',
      'is_voided': true,
      'expense_id': null,
    },
  ],
  'budget_overview': {
    'budget_plan': null,
    'summary': null,
    'active_subscriptions': [],
    'recent_expenses': [],
  },
  'recurring_statistics': {
    'active_recurring_count': 1,
    'today_expected_total': 12.5,
    'today_purchased_total': 0,
    'today_skipped_count': 0,
    'planned_total': 12.5,
    'actual_purchased_total': 0,
    'skipped_total': 0,
    'skipped_count': 0,
  },
  'history': {
    'items': [
      {
        'occurrence_id': 'occ-1',
        'recurring_purchase_id': 'purchase-1',
        'name': 'Milk',
        'price': 12.5,
        'occurrence_date': '2026-02-03',
        'status': 'purchased',
        'is_voided': true,
        'void_reason': 'reason text',
        'voided_at': '2026-02-03T00:00:00Z',
        'expense_id': 'expense-1',
        'definition_removed': false,
      },
    ],
  },
};

void main() {
  test(
    'removal RPC uses injected token, exact params, and parses snapshots',
    () async {
      String? name;
      Map<String, dynamic>? capturedParams;
      var tokens = 0;
      final service = BudgetService(
        AuthService(),
        sessionTokenProvider: () {
          tokens++;
          return 'test-session-token';
        },
        rpcCaller: (functionName, {params}) async {
          name = functionName;
          capturedParams = params;
          return _response(true);
        },
      );
      final result = await service.removeRecurringPurchaseOccurrence(
        recurringPurchaseId: 'purchase-1',
        occurrenceDate: DateTime(2026, 2, 3),
        reason: '  reason text  ',
      );
      expect(name, 'remove_recurring_purchase_occurrence');
      expect(capturedParams, {
        'p_session_token': 'test-session-token',
        'p_recurring_purchase_id': 'purchase-1',
        'p_occurrence_date': '2026-02-03',
        'p_reason': 'reason text',
      });
      expect(tokens, 1);
      expect(result.removed, isTrue);
      expect(result.todayItems[0].isVoided, isFalse);
      expect(result.todayItems[1].isVoided, isTrue);
      expect(result.budgetOverview.budgetPlan, isNull);
      expect(result.recurringStatistics.activeRecurringCount, 1);
    },
  );

  test(
    'removed false still parses authoritative snapshots without another RPC',
    () async {
      var calls = 0;
      final service = BudgetService(
        AuthService(),
        sessionTokenProvider: () => 'test-session-token',
        rpcCaller: (_, {params}) async {
          calls++;
          return _response(false);
        },
      );
      final result = await service.removeRecurringPurchaseOccurrence(
        recurringPurchaseId: 'purchase-1',
        occurrenceDate: DateTime(2026, 2, 3),
        reason: 'reason',
      );
      expect(result.removed, isFalse);
      expect(result.todayItems, hasLength(2));
      expect(calls, 1);
    },
  );
}
