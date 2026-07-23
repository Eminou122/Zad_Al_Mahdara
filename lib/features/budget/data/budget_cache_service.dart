import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/budget_models.dart';

class BudgetCachePayload {
  final DateTime cachedAt;
  final BudgetOverview overview;
  final List<TodayRecurringPurchase> todayRecurring;
  final List<RecurringPurchase> recurringItems;
  final RecurringPurchaseOverview recurringStats;

  const BudgetCachePayload({
    required this.cachedAt,
    required this.overview,
    required this.todayRecurring,
    required this.recurringItems,
    required this.recurringStats,
  });

  Map<String, dynamic> toJson() => {
    'cachedAt': cachedAt.toIso8601String(),
    'overview': overview.toJson(),
    'todayRecurring': todayRecurring.map((e) => e.toJson()).toList(),
    'recurringItems': recurringItems.map((e) => e.toJson()).toList(),
    'recurringStats': recurringStats.toJson(),
  };

  factory BudgetCachePayload.fromJson(
    Map<String, dynamic> j,
  ) => BudgetCachePayload(
    cachedAt: DateTime.parse(j['cachedAt'] as String),
    overview: BudgetOverview.fromJson(
      Map<String, dynamic>.from(j['overview'] as Map),
    ),
    todayRecurring: (j['todayRecurring'] as List)
        .map(
          (e) => TodayRecurringPurchase.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList(),
    recurringItems: (j['recurringItems'] as List)
        .map(
          (e) =>
              RecurringPurchase.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    recurringStats: RecurringPurchaseOverview.fromJson(
      Map<String, dynamic>.from(j['recurringStats'] as Map),
    ),
  );
}

class BudgetCacheService {
  static String _key(String profileId) => 'budget_cache_$profileId';

  Future<BudgetCachePayload?> load(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(profileId));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return BudgetCachePayload.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String profileId, BudgetCachePayload payload) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(profileId), jsonEncode(payload.toJson()));
  }

  Future<void> clear(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(profileId));
  }
}
