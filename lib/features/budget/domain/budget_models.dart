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
    id: j['id'] as String,
    totalMoney: (j['total_money'] as num).toDouble(),
    startDate: DateTime.parse(j['start_date'] as String),
    endDate: DateTime.parse(j['end_date'] as String),
    note: j['note'] as String?,
    isActive: j['is_active'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'total_money': totalMoney,
    'start_date': startDate.toIso8601String(),
    'end_date': endDate.toIso8601String(),
    'note': note,
    'is_active': isActive,
  };
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
  final double plannedRecurringTotal;
  final double actualRecurringTotal;
  final double skippedRecurringTotal;
  final int skippedRecurringCount;
  final double todayRecurringExpectedTotal;
  final double todayRecurringPurchasedTotal;
  final int todayRecurringSkippedCount;

  const BudgetSummary({
    required this.daysTotal,
    required this.daysRemaining,
    required this.totalSpent,
    required this.subscriptionTotal,
    required this.remainingMoney,
    required this.safeDailyLimit,
    required this.todaySpending,
    required this.isOverDailyLimit,
    required this.plannedRecurringTotal,
    required this.actualRecurringTotal,
    required this.skippedRecurringTotal,
    required this.skippedRecurringCount,
    required this.todayRecurringExpectedTotal,
    required this.todayRecurringPurchasedTotal,
    required this.todayRecurringSkippedCount,
  });

  factory BudgetSummary.fromJson(Map<String, dynamic> j) => BudgetSummary(
    daysTotal: (j['days_total'] as num).toInt(),
    daysRemaining: (j['days_remaining'] as num).toInt(),
    totalSpent: (j['total_spent'] as num).toDouble(),
    subscriptionTotal: (j['subscription_total'] as num).toDouble(),
    remainingMoney: (j['remaining_money'] as num).toDouble(),
    safeDailyLimit: (j['safe_daily_limit'] as num).toDouble(),
    todaySpending: (j['today_spending'] as num).toDouble(),
    isOverDailyLimit: j['is_over_daily_limit'] as bool,
    plannedRecurringTotal: ((j['planned_recurring_total'] ?? 0) as num)
        .toDouble(),
    actualRecurringTotal: ((j['actual_recurring_total'] ?? 0) as num)
        .toDouble(),
    skippedRecurringTotal: ((j['skipped_recurring_total'] ?? 0) as num)
        .toDouble(),
    skippedRecurringCount: ((j['skipped_recurring_count'] ?? 0) as num).toInt(),
    todayRecurringExpectedTotal:
        ((j['today_recurring_expected_total'] ?? 0) as num).toDouble(),
    todayRecurringPurchasedTotal:
        ((j['today_recurring_purchased_total'] ?? 0) as num).toDouble(),
    todayRecurringSkippedCount:
        ((j['today_recurring_skipped_count'] ?? 0) as num).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'days_total': daysTotal,
    'days_remaining': daysRemaining,
    'total_spent': totalSpent,
    'subscription_total': subscriptionTotal,
    'remaining_money': remainingMoney,
    'safe_daily_limit': safeDailyLimit,
    'today_spending': todaySpending,
    'is_over_daily_limit': isOverDailyLimit,
    'planned_recurring_total': plannedRecurringTotal,
    'actual_recurring_total': actualRecurringTotal,
    'skipped_recurring_total': skippedRecurringTotal,
    'skipped_recurring_count': skippedRecurringCount,
    'today_recurring_expected_total': todayRecurringExpectedTotal,
    'today_recurring_purchased_total': todayRecurringPurchasedTotal,
    'today_recurring_skipped_count': todayRecurringSkippedCount,
  };
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
    id: j['id'] as String,
    name: j['name'] as String,
    amount: (j['amount'] as num).toDouble(),
    startDate: DateTime.parse(j['start_date'] as String),
    endDate: DateTime.parse(j['end_date'] as String),
    notifyDaysBefore: (j['notify_days_before'] as num).toInt(),
    isActive: j['is_active'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amount': amount,
    'start_date': startDate.toIso8601String(),
    'end_date': endDate.toIso8601String(),
    'notify_days_before': notifyDaysBefore,
    'is_active': isActive,
  };
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
    id: j['id'] as String,
    itemName: j['item_name'] as String,
    amount: (j['amount'] as num).toDouble(),
    category: j['category'] as String?,
    note: j['note'] as String?,
    expenseDate: DateTime.parse(j['expense_date'] as String),
    source: j['source'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'item_name': itemName,
    'amount': amount,
    'category': category,
    'note': note,
    'expense_date': expenseDate.toIso8601String(),
    'source': source,
  };
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
        ? BudgetPlan.fromJson(
            Map<String, dynamic>.from(j['budget_plan'] as Map),
          )
        : null,
    summary: j['summary'] != null
        ? BudgetSummary.fromJson(Map<String, dynamic>.from(j['summary'] as Map))
        : null,
    activeSubscriptions: (j['active_subscriptions'] as List)
        .map(
          (e) => AppSubscription.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    recentExpenses: (j['recent_expenses'] as List)
        .map((e) => Expense.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'budget_plan': budgetPlan?.toJson(),
    'summary': summary?.toJson(),
    'active_subscriptions': activeSubscriptions.map((e) => e.toJson()).toList(),
    'recent_expenses': recentExpenses.map((e) => e.toJson()).toList(),
  };
}

class RecurringPurchase {
  final String id;
  final String name;
  final double price;
  final String frequency;
  final int? intervalDays;
  final DateTime startDate;
  final DateTime endDate;
  final String? reminderTime;
  final String? note;
  final bool isActive;

  const RecurringPurchase({
    required this.id,
    required this.name,
    required this.price,
    required this.frequency,
    this.intervalDays,
    required this.startDate,
    required this.endDate,
    this.reminderTime,
    this.note,
    required this.isActive,
  });

  factory RecurringPurchase.fromJson(Map<String, dynamic> j) =>
      RecurringPurchase(
        id: j['id'] as String,
        name: j['name'] as String,
        price: (j['price'] as num).toDouble(),
        frequency: j['frequency'] as String,
        intervalDays: (j['interval_days'] as num?)?.toInt(),
        startDate: DateTime.parse(j['start_date'] as String),
        endDate: DateTime.parse(j['end_date'] as String),
        reminderTime: j['reminder_time'] as String?,
        note: j['note'] as String?,
        isActive: j['is_active'] as bool,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'frequency': frequency,
    'interval_days': intervalDays,
    'start_date': startDate.toIso8601String(),
    'end_date': endDate.toIso8601String(),
    'reminder_time': reminderTime,
    'note': note,
    'is_active': isActive,
  };
}

class TodayRecurringPurchase {
  final String recurringPurchaseId;
  final String? occurrenceId;
  final String name;
  final double price;
  final String frequency;
  final int? intervalDays;
  final String? reminderTime;
  final String? note;
  final DateTime occurrenceDate;
  final String status;
  final String? expenseId;

  const TodayRecurringPurchase({
    required this.recurringPurchaseId,
    this.occurrenceId,
    required this.name,
    required this.price,
    required this.frequency,
    this.intervalDays,
    this.reminderTime,
    this.note,
    required this.occurrenceDate,
    required this.status,
    this.expenseId,
  });

  factory TodayRecurringPurchase.fromJson(Map<String, dynamic> j) =>
      TodayRecurringPurchase(
        recurringPurchaseId: j['recurring_purchase_id'] as String,
        occurrenceId: j['occurrence_id'] as String?,
        name: j['name'] as String,
        price: (j['price'] as num).toDouble(),
        frequency: j['frequency'] as String,
        intervalDays: (j['interval_days'] as num?)?.toInt(),
        reminderTime: j['reminder_time'] as String?,
        note: j['note'] as String?,
        occurrenceDate: DateTime.parse(j['occurrence_date'] as String),
        status: j['status'] as String,
        expenseId: j['expense_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'recurring_purchase_id': recurringPurchaseId,
    'occurrence_id': occurrenceId,
    'name': name,
    'price': price,
    'frequency': frequency,
    'interval_days': intervalDays,
    'reminder_time': reminderTime,
    'note': note,
    'occurrence_date': occurrenceDate.toIso8601String(),
    'status': status,
    'expense_id': expenseId,
  };
}

class RecurringPurchaseOverview {
  final int activeRecurringCount;
  final double todayExpectedTotal;
  final double todayPurchasedTotal;
  final int todaySkippedCount;
  final double plannedTotal;
  final double actualPurchasedTotal;
  final double skippedTotal;
  final int skippedCount;

  const RecurringPurchaseOverview({
    required this.activeRecurringCount,
    required this.todayExpectedTotal,
    required this.todayPurchasedTotal,
    required this.todaySkippedCount,
    required this.plannedTotal,
    required this.actualPurchasedTotal,
    required this.skippedTotal,
    required this.skippedCount,
  });

  factory RecurringPurchaseOverview.fromJson(
    Map<String, dynamic> j,
  ) => RecurringPurchaseOverview(
    activeRecurringCount: ((j['active_recurring_count'] ?? 0) as num).toInt(),
    todayExpectedTotal: ((j['today_expected_total'] ?? 0) as num).toDouble(),
    todayPurchasedTotal: ((j['today_purchased_total'] ?? 0) as num).toDouble(),
    todaySkippedCount: ((j['today_skipped_count'] ?? 0) as num).toInt(),
    plannedTotal: ((j['planned_total'] ?? 0) as num).toDouble(),
    actualPurchasedTotal: ((j['actual_purchased_total'] ?? 0) as num)
        .toDouble(),
    skippedTotal: ((j['skipped_total'] ?? 0) as num).toDouble(),
    skippedCount: ((j['skipped_count'] ?? 0) as num).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'active_recurring_count': activeRecurringCount,
    'today_expected_total': todayExpectedTotal,
    'today_purchased_total': todayPurchasedTotal,
    'today_skipped_count': todaySkippedCount,
    'planned_total': plannedTotal,
    'actual_purchased_total': actualPurchasedTotal,
    'skipped_total': skippedTotal,
    'skipped_count': skippedCount,
  };
}
