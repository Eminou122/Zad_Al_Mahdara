import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/auth_service.dart';
import '../domain/budget_models.dart';

class BudgetService {
  final AuthService _auth;
  BudgetService(this._auth);

  SupabaseClient get _client => Supabase.instance.client;

  String get _token {
    final t = _auth.currentToken;
    if (t == null) throw Exception('not authenticated');
    return t;
  }

  static BudgetOverview _overview(dynamic result) =>
      BudgetOverview.fromJson(Map<String, dynamic>.from(result as Map));

  static List<RecurringPurchase> _recurringList(dynamic result) {
    final json = Map<String, dynamic>.from(result as Map);
    return (json['items'] as List)
        .map(
          (e) =>
              RecurringPurchase.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  static List<TodayRecurringPurchase> _todayRecurringList(dynamic result) {
    final json = Map<String, dynamic>.from(result as Map);
    return (json['items'] as List)
        .map(
          (e) => TodayRecurringPurchase.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  Future<BudgetOverview> getOverview() async {
    final r = await _client.rpc(
      'get_budget_overview',
      params: {'p_session_token': _token},
    );
    return _overview(r);
  }

  Future<BudgetOverview> upsertBudgetPlan({
    required double totalMoney,
    required DateTime startDate,
    required DateTime endDate,
    String? note,
  }) async {
    final r = await _client.rpc(
      'upsert_budget_plan',
      params: {
        'p_session_token': _token,
        'p_total_money': totalMoney,
        'p_start_date': _date(startDate),
        'p_end_date': _date(endDate),
        'p_note': note,
      },
    );
    return _overview(r);
  }

  Future<BudgetOverview> addExpense({
    required String itemName,
    required double amount,
    String? category,
    String? note,
    required DateTime expenseDate,
  }) async {
    final r = await _client.rpc(
      'add_expense',
      params: {
        'p_session_token': _token,
        'p_item_name': itemName,
        'p_amount': amount,
        'p_category': category,
        'p_note': note,
        'p_expense_date': _date(expenseDate),
      },
    );
    return _overview(r);
  }

  Future<BudgetOverview> updateExpense({
    required String expenseId,
    required String itemName,
    required double amount,
    String? category,
    String? note,
    required DateTime expenseDate,
  }) async {
    final r = await _client.rpc(
      'update_expense',
      params: {
        'p_session_token': _token,
        'p_expense_id': expenseId,
        'p_item_name': itemName,
        'p_amount': amount,
        'p_category': category,
        'p_note': note,
        'p_expense_date': _date(expenseDate),
      },
    );
    return _overview(r);
  }

  Future<bool> voidExpense(String expenseId, String reason) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty || trimmed.length > 300) {
      throw ArgumentError('invalid void reason');
    }
    final result = Map<String, dynamic>.from(
      await _client.rpc(
            'void_expense',
            params: {
              'p_session_token': _token,
              'p_expense_id': expenseId,
              'p_reason': trimmed,
            },
          )
          as Map,
    );
    if (result['ok'] != true || result['voided'] is! bool) {
      throw StateError('invalid void response');
    }
    return result['voided'] as bool;
  }

  Future<BudgetOverview> addSubscription({
    required String name,
    required double amount,
    required DateTime startDate,
    required DateTime endDate,
    required int notifyDaysBefore,
  }) async {
    final r = await _client.rpc(
      'add_subscription',
      params: {
        'p_session_token': _token,
        'p_name': name,
        'p_amount': amount,
        'p_start_date': _date(startDate),
        'p_end_date': _date(endDate),
        'p_notify_days_before': notifyDaysBefore,
      },
    );
    return _overview(r);
  }

  Future<BudgetOverview> updateSubscription({
    required String subscriptionId,
    required String name,
    required double amount,
    required DateTime startDate,
    required DateTime endDate,
    required int notifyDaysBefore,
    required bool isActive,
  }) async {
    final r = await _client.rpc(
      'update_subscription',
      params: {
        'p_session_token': _token,
        'p_subscription_id': subscriptionId,
        'p_name': name,
        'p_amount': amount,
        'p_start_date': _date(startDate),
        'p_end_date': _date(endDate),
        'p_notify_days_before': notifyDaysBefore,
        'p_is_active': isActive,
      },
    );
    return _overview(r);
  }

  Future<void> deactivateSubscription(String subscriptionId) async {
    await _client.rpc(
      'delete_or_deactivate_subscription',
      params: {'p_session_token': _token, 'p_subscription_id': subscriptionId},
    );
  }

  Future<List<RecurringPurchase>> getRecurringPurchases() async {
    final r = await _client.rpc(
      'get_recurring_purchases',
      params: {'p_session_token': _token},
    );
    return _recurringList(r);
  }

  Future<List<TodayRecurringPurchase>> getTodayRecurringPurchases() async {
    final r = await _client.rpc(
      'get_today_recurring_purchases',
      params: {'p_session_token': _token},
    );
    return _todayRecurringList(r);
  }

  Future<RecurringPurchaseOverview> getRecurringPurchaseOverview() async {
    final r = await _client.rpc(
      'get_recurring_purchase_overview',
      params: {'p_session_token': _token},
    );
    return RecurringPurchaseOverview.fromJson(
      Map<String, dynamic>.from(r as Map),
    );
  }

  Future<List<RecurringPurchase>> createRecurringPurchase({
    required String name,
    required double price,
    required String frequency,
    int? intervalDays,
    required DateTime startDate,
    required DateTime endDate,
    String? reminderTime,
    String? note,
  }) async {
    final r = await _client.rpc(
      'create_recurring_purchase',
      params: {
        'p_session_token': _token,
        'p_name': name,
        'p_price': price,
        'p_frequency': frequency,
        'p_interval_days': intervalDays,
        'p_start_date': _date(startDate),
        'p_end_date': _date(endDate),
        'p_reminder_time': reminderTime,
        'p_note': note,
      },
    );
    return _recurringList(r);
  }

  Future<List<RecurringPurchase>> updateRecurringPurchase({
    required String recurringPurchaseId,
    required String name,
    required double price,
    required String frequency,
    int? intervalDays,
    required DateTime startDate,
    required DateTime endDate,
    String? reminderTime,
    String? note,
  }) async {
    final r = await _client.rpc(
      'update_recurring_purchase',
      params: {
        'p_session_token': _token,
        'p_recurring_purchase_id': recurringPurchaseId,
        'p_name': name,
        'p_price': price,
        'p_frequency': frequency,
        'p_interval_days': intervalDays,
        'p_start_date': _date(startDate),
        'p_end_date': _date(endDate),
        'p_reminder_time': reminderTime,
        'p_note': note,
      },
    );
    return _recurringList(r);
  }

  Future<List<RecurringPurchase>> deactivateRecurringPurchase(
    String recurringPurchaseId,
  ) async {
    final r = await _client.rpc(
      'deactivate_recurring_purchase',
      params: {
        'p_session_token': _token,
        'p_recurring_purchase_id': recurringPurchaseId,
      },
    );
    return _recurringList(r);
  }

  Future<List<TodayRecurringPurchase>> markRecurringPurchaseOccurrence({
    required String recurringPurchaseId,
    required DateTime occurrenceDate,
    required String status,
    String? note,
  }) async {
    final r = await _client.rpc(
      'mark_recurring_purchase_occurrence',
      params: {
        'p_session_token': _token,
        'p_recurring_purchase_id': recurringPurchaseId,
        'p_occurrence_date': _date(occurrenceDate),
        'p_status': status,
        'p_note': note,
      },
    );
    return _todayRecurringList(r);
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
