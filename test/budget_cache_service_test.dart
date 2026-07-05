import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad_al_mahdara/features/budget/data/budget_cache_service.dart';
import 'package:zad_al_mahdara/features/budget/domain/budget_models.dart';

void main() {
  group('BudgetCacheService', () {
    late BudgetCacheService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = BudgetCacheService();
    });

    test('load returns null on cache miss', () async {
      final result = await service.load('profile-1');
      expect(result, isNull);
    });

    test('save then load returns same data', () async {
      final payload = BudgetCachePayload(
        cachedAt: DateTime(2026, 7, 4, 12, 30),
        overview: BudgetOverview(
          budgetPlan: BudgetPlan(
            id: 'plan-1',
            totalMoney: 1000,
            startDate: DateTime(2026, 7, 1),
            endDate: DateTime(2026, 7, 30),
            isActive: true,
          ),
          summary: BudgetSummary(
            daysTotal: 30,
            daysRemaining: 10,
            totalSpent: 200,
            subscriptionTotal: 100,
            remainingMoney: 700,
            safeDailyLimit: 70,
            todaySpending: 0,
            isOverDailyLimit: false,
            plannedRecurringTotal: 350,
            actualRecurringTotal: 25,
            skippedRecurringTotal: 50,
            skippedRecurringCount: 2,
            todayRecurringExpectedTotal: 25,
            todayRecurringPurchasedTotal: 25,
            todayRecurringSkippedCount: 0,
          ),
          activeSubscriptions: const [],
          recentExpenses: const [],
        ),
        todayRecurring: const [],
        recurringItems: const [],
        recurringStats: RecurringPurchaseOverview(
          activeRecurringCount: 3,
          todayExpectedTotal: 100,
          todayPurchasedTotal: 50,
          todaySkippedCount: 1,
          plannedTotal: 900,
          actualPurchasedTotal: 600,
          skippedTotal: 40,
          skippedCount: 2,
        ),
      );

      await service.save('profile-1', payload);
      final loaded = await service.load('profile-1');

      expect(loaded, isNotNull);
      expect(loaded!.cachedAt, payload.cachedAt);
      expect(loaded.overview.budgetPlan!.id, 'plan-1');
      expect(loaded.overview.budgetPlan!.totalMoney, 1000);
      expect(loaded.overview.summary!.remainingMoney, 700);
      expect(loaded.overview.activeSubscriptions, isEmpty);
      expect(loaded.overview.recentExpenses, isEmpty);
      expect(loaded.todayRecurring, isEmpty);
      expect(loaded.recurringItems, isEmpty);
      expect(loaded.recurringStats.activeRecurringCount, 3);
      expect(loaded.recurringStats.plannedTotal, 900);
    });

    test('different profileId uses different cache key', () async {
      final payload = BudgetCachePayload(
        cachedAt: DateTime(2026, 7, 4),
        overview: BudgetOverview(
          budgetPlan: BudgetPlan(
            id: 'plan-1',
            totalMoney: 1000,
            startDate: DateTime(2026, 7, 1),
            endDate: DateTime(2026, 7, 30),
            isActive: true,
          ),
          summary: BudgetSummary(
            daysTotal: 30,
            daysRemaining: 10,
            totalSpent: 200,
            subscriptionTotal: 100,
            remainingMoney: 700,
            safeDailyLimit: 70,
            todaySpending: 0,
            isOverDailyLimit: false,
            plannedRecurringTotal: 350,
            actualRecurringTotal: 25,
            skippedRecurringTotal: 50,
            skippedRecurringCount: 2,
            todayRecurringExpectedTotal: 25,
            todayRecurringPurchasedTotal: 25,
            todayRecurringSkippedCount: 0,
          ),
          activeSubscriptions: const [],
          recentExpenses: const [],
        ),
        todayRecurring: const [],
        recurringItems: const [],
        recurringStats: RecurringPurchaseOverview(
          activeRecurringCount: 0,
          todayExpectedTotal: 0,
          todayPurchasedTotal: 0,
          todaySkippedCount: 0,
          plannedTotal: 0,
          actualPurchasedTotal: 0,
          skippedTotal: 0,
          skippedCount: 0,
        ),
      );

      await service.save('profile-1', payload);

      final resultA = await service.load('profile-1');
      final resultB = await service.load('profile-2');

      expect(resultA, isNotNull);
      expect(resultB, isNull);
    });

    test('clear removes cache for given profileId', () async {
      final payload = BudgetCachePayload(
        cachedAt: DateTime(2026, 7, 4),
        overview: BudgetOverview(
          budgetPlan: null,
          summary: null,
          activeSubscriptions: const [],
          recentExpenses: const [],
        ),
        todayRecurring: const [],
        recurringItems: const [],
        recurringStats: RecurringPurchaseOverview(
          activeRecurringCount: 0,
          todayExpectedTotal: 0,
          todayPurchasedTotal: 0,
          todaySkippedCount: 0,
          plannedTotal: 0,
          actualPurchasedTotal: 0,
          skippedTotal: 0,
          skippedCount: 0,
        ),
      );

      await service.save('profile-1', payload);
      await service.clear('profile-1');

      final loaded = await service.load('profile-1');
      expect(loaded, isNull);
    });
  });
}
