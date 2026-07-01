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

  Future<BudgetOverview> getOverview() async {
    final r = await _client.rpc('get_budget_overview', params: {'p_session_token': _token});
    return _overview(r);
  }

  Future<BudgetOverview> upsertBudgetPlan({
    required double totalMoney,
    required DateTime startDate,
    required DateTime endDate,
    String? note,
  }) async {
    final r = await _client.rpc('upsert_budget_plan', params: {
      'p_session_token': _token,
      'p_total_money':   totalMoney,
      'p_start_date':    _date(startDate),
      'p_end_date':      _date(endDate),
      'p_note':          note,
    });
    return _overview(r);
  }

  Future<BudgetOverview> addExpense({
    required String itemName,
    required double amount,
    String? category,
    String? note,
    required DateTime expenseDate,
  }) async {
    final r = await _client.rpc('add_expense', params: {
      'p_session_token': _token,
      'p_item_name':     itemName,
      'p_amount':        amount,
      'p_category':      category,
      'p_note':          note,
      'p_expense_date':  _date(expenseDate),
    });
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
    final r = await _client.rpc('update_expense', params: {
      'p_session_token': _token,
      'p_expense_id':    expenseId,
      'p_item_name':     itemName,
      'p_amount':        amount,
      'p_category':      category,
      'p_note':          note,
      'p_expense_date':  _date(expenseDate),
    });
    return _overview(r);
  }

  Future<void> deleteExpense(String expenseId) async {
    await _client.rpc('delete_expense', params: {
      'p_session_token': _token,
      'p_expense_id':    expenseId,
    });
  }

  Future<BudgetOverview> addSubscription({
    required String name,
    required double amount,
    required DateTime startDate,
    required DateTime endDate,
    required int notifyDaysBefore,
  }) async {
    final r = await _client.rpc('add_subscription', params: {
      'p_session_token':       _token,
      'p_name':                name,
      'p_amount':              amount,
      'p_start_date':          _date(startDate),
      'p_end_date':            _date(endDate),
      'p_notify_days_before':  notifyDaysBefore,
    });
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
    final r = await _client.rpc('update_subscription', params: {
      'p_session_token':       _token,
      'p_subscription_id':     subscriptionId,
      'p_name':                name,
      'p_amount':              amount,
      'p_start_date':          _date(startDate),
      'p_end_date':            _date(endDate),
      'p_notify_days_before':  notifyDaysBefore,
      'p_is_active':           isActive,
    });
    return _overview(r);
  }

  Future<void> deactivateSubscription(String subscriptionId) async {
    await _client.rpc('delete_or_deactivate_subscription', params: {
      'p_session_token':   _token,
      'p_subscription_id': subscriptionId,
    });
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
