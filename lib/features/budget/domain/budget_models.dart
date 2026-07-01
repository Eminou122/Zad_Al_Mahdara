class BudgetPlan {
  final String id;
  final double totalMoney;
  final DateTime startDate;
  final DateTime endDate;
  final String? note;
  final bool isActive;

  const BudgetPlan({
    required this.id,
    required this.totalMoney,
    required this.startDate,
    required this.endDate,
    this.note,
    required this.isActive,
  });

  factory BudgetPlan.fromJson(Map<String, dynamic> j) => BudgetPlan(
        id:         j['id'] as String,
        totalMoney: (j['total_money'] as num).toDouble(),
        startDate:  DateTime.parse(j['start_date'] as String),
        endDate:    DateTime.parse(j['end_date'] as String),
        note:       j['note'] as String?,
        isActive:   j['is_active'] as bool,
      );
}

class BudgetSummary {
  final int daysTotal;
  final int daysRemaining;
  final double totalSpent;
  final double subscriptionTotal;
  final double remainingMoney;
  final double safeDailyLimit;
  final double todaySpending;
  final bool isOverDailyLimit;

  const BudgetSummary({
    required this.daysTotal,
    required this.daysRemaining,
    required this.totalSpent,
    required this.subscriptionTotal,
    required this.remainingMoney,
    required this.safeDailyLimit,
    required this.todaySpending,
    required this.isOverDailyLimit,
  });

  factory BudgetSummary.fromJson(Map<String, dynamic> j) => BudgetSummary(
        daysTotal:         (j['days_total'] as num).toInt(),
        daysRemaining:     (j['days_remaining'] as num).toInt(),
        totalSpent:        (j['total_spent'] as num).toDouble(),
        subscriptionTotal: (j['subscription_total'] as num).toDouble(),
        remainingMoney:    (j['remaining_money'] as num).toDouble(),
        safeDailyLimit:    (j['safe_daily_limit'] as num).toDouble(),
        todaySpending:     (j['today_spending'] as num).toDouble(),
        isOverDailyLimit:  j['is_over_daily_limit'] as bool,
      );
}

class AppSubscription {
  final String id;
  final String name;
  final double amount;
  final DateTime startDate;
  final DateTime endDate;
  final int notifyDaysBefore;
  final bool isActive;

  const AppSubscription({
    required this.id,
    required this.name,
    required this.amount,
    required this.startDate,
    required this.endDate,
    required this.notifyDaysBefore,
    required this.isActive,
  });

  factory AppSubscription.fromJson(Map<String, dynamic> j) => AppSubscription(
        id:               j['id'] as String,
        name:             j['name'] as String,
        amount:           (j['amount'] as num).toDouble(),
        startDate:        DateTime.parse(j['start_date'] as String),
        endDate:          DateTime.parse(j['end_date'] as String),
        notifyDaysBefore: (j['notify_days_before'] as num).toInt(),
        isActive:         j['is_active'] as bool,
      );
}

class Expense {
  final String id;
  final String itemName;
  final double amount;
  final String? category;
  final String? note;
  final DateTime expenseDate;
  final String source;

  const Expense({
    required this.id,
    required this.itemName,
    required this.amount,
    this.category,
    this.note,
    required this.expenseDate,
    required this.source,
  });

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id:          j['id'] as String,
        itemName:    j['item_name'] as String,
        amount:      (j['amount'] as num).toDouble(),
        category:    j['category'] as String?,
        note:        j['note'] as String?,
        expenseDate: DateTime.parse(j['expense_date'] as String),
        source:      j['source'] as String,
      );
}

class BudgetOverview {
  final BudgetPlan? budgetPlan;
  final BudgetSummary? summary;
  final List<AppSubscription> activeSubscriptions;
  final List<Expense> recentExpenses;

  const BudgetOverview({
    this.budgetPlan,
    this.summary,
    required this.activeSubscriptions,
    required this.recentExpenses,
  });

  factory BudgetOverview.fromJson(Map<String, dynamic> j) => BudgetOverview(
        budgetPlan: j['budget_plan'] != null
            ? BudgetPlan.fromJson(Map<String, dynamic>.from(j['budget_plan'] as Map))
            : null,
        summary: j['summary'] != null
            ? BudgetSummary.fromJson(Map<String, dynamic>.from(j['summary'] as Map))
            : null,
        activeSubscriptions: (j['active_subscriptions'] as List)
            .map((e) => AppSubscription.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        recentExpenses: (j['recent_expenses'] as List)
            .map((e) => Expense.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
