import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad_al_mahdara/features/budget/data/budget_cache_service.dart';
import 'package:zad_al_mahdara/features/budget/data/budget_service.dart';
import 'package:zad_al_mahdara/features/budget/domain/budget_models.dart';
import 'package:zad_al_mahdara/features/budget/presentation/budget_screen.dart';
import 'package:zad_al_mahdara/features/budget/presentation/recurring_purchase_form_screen.dart';
import 'package:zad_al_mahdara/features/budget/presentation/recurring_purchases_screen.dart';
import 'package:zad_al_mahdara/features/budget/presentation/widgets/recurring_removal_dialog.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

/// Stub service that returns the given data or throws.
class _StubBudgetService extends BudgetService {
  BudgetOverview? overview;
  List<TodayRecurringPurchase> todayRecurring;
  List<RecurringPurchase> recurringItems;
  RecurringPurchaseOverview? recurringStats;
  Object? error;
  Object? markError;
  Object? voidError;
  bool voidResult;
  Completer<bool>? voidCompleter;
  String? voidReason;
  int voidCalls = 0;
  int overviewCalls = 0;
  int deactivateSubscriptionCalls = 0;
  Object? deactivateSubscriptionError;
  Completer<void>? deactivateSubscriptionCompleter;
  List<TodayRecurringPurchase>? markResult;
  final List<List<TodayRecurringPurchase>> markResults = [];
  Completer<List<TodayRecurringPurchase>>? markCompleter;
  final List<Completer<List<TodayRecurringPurchase>>> todayCompleters = [];
  int markCalls = 0;
  int todayCalls = 0;
  int recurringStatsCalls = 0;
  int recurringCalls = 0;
  int createCalls = 0;
  int updateCalls = 0;
  int deactivateRecurringCalls = 0;
  int removeRecurringCalls = 0;
  List<RecurringPurchase>? createResult;
  List<RecurringPurchase>? updateResult;
  List<RecurringPurchase>? deactivateRecurringResult;
  Object? deactivateRecurringError;
  Completer<RecurringPurchaseOverview>? recurringStatsCompleter;
  final List<Completer<RecurringPurchaseOverview>> recurringStatsCompleters =
      [];
  final List<Completer<BudgetOverview>> overviewCompleters = [];

  _StubBudgetService({
    required AuthService authService,
    this.overview,
    this.todayRecurring = const [],
    this.recurringItems = const [],
    this.recurringStats,
    this.error,
    this.markError,
    this.voidError,
    this.voidResult = true,
    this.voidCompleter,
    this.deactivateSubscriptionCompleter,
    this.markResult,
    this.markCompleter,
  }) : super(authService);

  @override
  Future<BudgetOverview> getOverview() async {
    if (error != null) throw error!;
    overviewCalls++;
    if (overviewCompleters.isNotEmpty) {
      return overviewCompleters.removeAt(0).future;
    }
    return overview!;
  }

  @override
  Future<bool> voidExpense(String expenseId, String reason) async {
    voidCalls++;
    voidReason = reason;
    if (voidError != null) throw voidError!;
    if (voidCompleter != null) return voidCompleter!.future;
    return voidResult;
  }

  @override
  Future<void> deactivateSubscription(String subscriptionId) async {
    deactivateSubscriptionCalls++;
    if (deactivateSubscriptionError != null) {
      throw deactivateSubscriptionError!;
    }
    if (deactivateSubscriptionCompleter != null) {
      return deactivateSubscriptionCompleter!.future;
    }
  }

  @override
  Future<List<TodayRecurringPurchase>> getTodayRecurringPurchases() async {
    if (error != null) throw error!;
    todayCalls++;
    if (todayCompleters.isNotEmpty) {
      return todayCompleters.removeAt(0).future;
    }
    return todayRecurring;
  }

  @override
  Future<List<RecurringPurchase>> getRecurringPurchases() async {
    if (error != null) throw error!;
    recurringCalls++;
    return recurringItems;
  }

  @override
  Future<RecurringPurchaseOverview> getRecurringPurchaseOverview() async {
    if (error != null) throw error!;
    recurringStatsCalls++;
    if (recurringStatsCompleters.isNotEmpty) {
      return recurringStatsCompleters.removeAt(0).future;
    }
    if (recurringStatsCompleter != null) return recurringStatsCompleter!.future;
    return recurringStats!;
  }

  @override
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
    createCalls++;
    return createResult!;
  }

  @override
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
    updateCalls++;
    return updateResult!;
  }

  @override
  Future<List<RecurringPurchase>> deactivateRecurringPurchase(
    String recurringPurchaseId,
  ) async {
    deactivateRecurringCalls++;
    if (deactivateRecurringError != null) throw deactivateRecurringError!;
    return deactivateRecurringResult!;
  }

  @override
  Future<RecurringPurchaseRemovalResult> removeRecurringPurchase({
    required String recurringPurchaseId,
    required String reason,
  }) async {
    removeRecurringCalls++;
    return RecurringPurchaseRemovalResult(
      removed: true,
      recurringPurchases: deactivateRecurringResult!,
      recurringStatistics: _recurringStats,
    );
  }

  @override
  Future<List<TodayRecurringPurchase>> markRecurringPurchaseOccurrence({
    required String recurringPurchaseId,
    required DateTime occurrenceDate,
    required String status,
    String? note,
  }) async {
    markCalls++;
    if (markError != null) throw markError!;
    if (markCompleter != null) return markCompleter!.future;
    if (markResults.isNotEmpty) return markResults.removeAt(0);
    return markResult ?? todayRecurring;
  }
}

AuthService _authWithProfile(String profileId) {
  final auth = AuthService();
  auth.setTestProfile(
    UserProfile(
      id: profileId,
      displayName: 'Test User',
      phoneMasked: '******00',
      isAdmin: false,
      isActive: true,
    ),
  );
  return auth;
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Some tests need extra height because the budget screen has many sections.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final _overview = BudgetOverview(
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
);

final _recurringStats = RecurringPurchaseOverview(
  activeRecurringCount: 0,
  todayExpectedTotal: 0,
  todayPurchasedTotal: 0,
  todaySkippedCount: 0,
  plannedTotal: 0,
  actualPurchasedTotal: 0,
  skippedTotal: 0,
  skippedCount: 0,
);

TodayRecurringPurchase _todayPurchase({
  required String id,
  required String name,
  String status = 'unmarked',
}) => TodayRecurringPurchase(
  recurringPurchaseId: id,
  name: name,
  price: 25,
  frequency: 'daily',
  occurrenceDate: DateTime(2026, 7, 4),
  status: status,
);

RecurringPurchase _recurringPurchase(String id, String name) =>
    RecurringPurchase(
      id: id,
      name: name,
      price: 25,
      frequency: 'daily',
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 31),
      isActive: true,
    );

Widget _recurringHost(AuthService auth, _StubBudgetService service) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            RecurringPurchasesScreen(authService: auth, budgetService: service),
      ),
      GoRoute(
        path: '/budget/recurring/new',
        builder: (_, state) => RecurringPurchaseFormScreen(
          authService: auth,
          budgetService: service,
          existing: state.extra as RecurringPurchase?,
        ),
      ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    builder: (_, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
  );
}

Future<void> _pumpBudget(
  WidgetTester tester,
  AuthService auth,
  _StubBudgetService service,
) async {
  _tallViewport(tester);
  await tester.pumpWidget(
    _host(BudgetScreen(authService: auth, budgetService: service)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('online success', () {
    testWidgets('saves cache on successful load', (tester) async {
      final auth = _authWithProfile('profile-1');
      final service = _StubBudgetService(
        authService: auth,
        overview: _overview,
        recurringStats: _recurringStats,
      );

      await tester.pumpWidget(
        _host(BudgetScreen(authService: auth, budgetService: service)),
      );
      await tester.pumpAndSettle();

      // Verify cache was saved
      final cacheService = BudgetCacheService();
      final cached = await cacheService.load('profile-1');
      expect(cached, isNotNull);
      expect(cached!.overview.budgetPlan!.id, 'plan-1');
    });

    testWidgets('renders live data without offline banner', (tester) async {
      final auth = _authWithProfile('profile-1');
      final service = _StubBudgetService(
        authService: auth,
        overview: _overview,
        recurringStats: _recurringStats,
      );

      await tester.pumpWidget(
        _host(BudgetScreen(authService: auth, budgetService: service)),
      );
      await tester.pumpAndSettle();

      expect(find.text('ميزانيتي'), findsOneWidget);
      expect(find.text('أنت تشاهد آخر نسخة محفوظة'), findsNothing);
      expect(find.text('المبلغ المتبقي'), findsOneWidget);
    });
  });

  group('offline with cache', () {
    testWidgets(
      'shows offline banner and cached data when load fails and cache exists',
      (tester) async {
        _tallViewport(tester);
        final auth = _authWithProfile('profile-1');

        // Pre-seed cache
        final cacheService = BudgetCacheService();
        await cacheService.save(
          'profile-1',
          BudgetCachePayload(
            cachedAt: DateTime(2026, 7, 4, 12, 30),
            overview: _overview,
            todayRecurring: const [],
            recurringItems: const [],
            recurringStats: _recurringStats,
          ),
        );

        final service = _StubBudgetService(
          authService: auth,
          overview: _overview,
          recurringStats: _recurringStats,
          error: Exception('network error'),
        );

        await tester.pumpWidget(
          _host(BudgetScreen(authService: auth, budgetService: service)),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('أنت تشاهد آخر نسخة محفوظة'),
          findsOneWidget,
        );
        expect(find.text('المبلغ المتبقي'), findsOneWidget);
        expect(find.text('700.00'), findsOneWidget);
      },
    );

    testWidgets('shows cachedAt timestamp in banner', (tester) async {
      _tallViewport(tester);
      final auth = _authWithProfile('profile-1');

      final cacheService = BudgetCacheService();
      final cachedAt = DateTime(2026, 7, 4, 12, 30);
      await cacheService.save(
        'profile-1',
        BudgetCachePayload(
          cachedAt: cachedAt,
          overview: _overview,
          todayRecurring: const [],
          recurringItems: const [],
          recurringStats: _recurringStats,
        ),
      );

      final service = _StubBudgetService(
        authService: auth,
        overview: _overview,
        recurringStats: _recurringStats,
        error: Exception('network error'),
      );

      await tester.pumpWidget(
        _host(BudgetScreen(authService: auth, budgetService: service)),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('آخر تحديث: 2026-07-04 12:30'),
        findsOneWidget,
      );
    });

    testWidgets('quick actions are disabled in offline mode', (tester) async {
      _tallViewport(tester);
      final auth = _authWithProfile('profile-1');

      final cacheService = BudgetCacheService();
      await cacheService.save(
        'profile-1',
        BudgetCachePayload(
          cachedAt: DateTime(2026, 7, 4),
          overview: _overview,
          todayRecurring: const [],
          recurringItems: const [],
          recurringStats: _recurringStats,
        ),
      );

      final service = _StubBudgetService(
        authService: auth,
        overview: _overview,
        recurringStats: _recurringStats,
        error: Exception('network error'),
      );

      await tester.pumpWidget(
        _host(BudgetScreen(authService: auth, budgetService: service)),
      );
      await tester.pumpAndSettle();

      // Tap the quick action icon (InkWell is on the icon circle, not the text label)
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text('هذه العملية تحتاج إلى اتصال بالإنترنت'),
        findsOneWidget,
      );
    });

    testWidgets(
      'mark recurring buttons call _onOfflineAction when offline cached',
      (tester) async {
        _tallViewport(tester);
        final auth = _authWithProfile('profile-1');
        final today = TodayRecurringPurchase(
          recurringPurchaseId: 'rp-1',
          name: 'خبز',
          price: 25,
          frequency: 'daily',
          occurrenceDate: DateTime(2026, 7, 4),
          status: 'unmarked',
        );

        final cacheService = BudgetCacheService();
        await cacheService.save(
          'profile-1',
          BudgetCachePayload(
            cachedAt: DateTime(2026, 7, 4),
            overview: _overview,
            todayRecurring: [today],
            recurringItems: const [],
            recurringStats: _recurringStats,
          ),
        );

        final service = _StubBudgetService(
          authService: auth,
          overview: _overview,
          todayRecurring: [today],
          recurringItems: const [],
          recurringStats: _recurringStats,
          error: Exception('network error'),
        );

        await tester.pumpWidget(
          _host(BudgetScreen(authService: auth, budgetService: service)),
        );
        await tester.pumpAndSettle();

        // Tap "تم الشراء" button
        await tester.tap(find.text('تم الشراء'));
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          find.text('هذه العملية تحتاج إلى اتصال بالإنترنت'),
          findsOneWidget,
        );
      },
    );
  });

  group('offline without cache', () {
    testWidgets('shows error when load fails and no cache exists', (
      tester,
    ) async {
      final auth = _authWithProfile('profile-1');

      final service = _StubBudgetService(
        authService: auth,
        overview: _overview,
        recurringStats: _recurringStats,
        error: Exception('network error'),
      );

      await tester.pumpWidget(
        _host(BudgetScreen(authService: auth, budgetService: service)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('حدث خطأ'), findsOneWidget);
      expect(find.text('أنت تشاهد آخر نسخة محفوظة'), findsNothing);
    });

    testWidgets('different profileId does not leak cached data', (
      tester,
    ) async {
      final auth2 = _authWithProfile('profile-2');

      // Pre-seed cache for profile-1
      final cacheService = BudgetCacheService();
      await cacheService.save(
        'profile-1',
        BudgetCachePayload(
          cachedAt: DateTime(2026, 7, 4),
          overview: _overview,
          todayRecurring: const [],
          recurringItems: const [],
          recurringStats: _recurringStats,
        ),
      );

      final service = _StubBudgetService(
        authService: auth2,
        overview: _overview,
        recurringStats: _recurringStats,
        error: Exception('network error'),
      );

      await tester.pumpWidget(
        _host(BudgetScreen(authService: auth2, budgetService: service)),
      );
      await tester.pumpAndSettle();

      // profile-2 should NOT see profile-1's cached data
      expect(find.text('أنت تشاهد آخر نسخة محفوظة'), findsNothing);
      expect(find.textContaining('حدث خطأ'), findsOneWidget);
    });
  });

  group('refresh after offline', () {
    testWidgets('fresh load clears offline banner', (tester) async {
      _tallViewport(tester);
      // First load fails -> show cache
      // Second load (simulating refresh) succeeds -> clear offline state

      final auth = _authWithProfile('profile-1');
      final cacheService = BudgetCacheService();
      await cacheService.save(
        'profile-1',
        BudgetCachePayload(
          cachedAt: DateTime(2026, 7, 4),
          overview: _overview,
          todayRecurring: const [],
          recurringItems: const [],
          recurringStats: _recurringStats,
        ),
      );

      // Start with error
      final service = _StubBudgetService(
        authService: auth,
        overview: _overview,
        recurringStats: _recurringStats,
        error: Exception('network error'),
      );

      await tester.pumpWidget(
        _host(BudgetScreen(authService: auth, budgetService: service)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('أنت تشاهد آخر نسخة محفوظة'), findsOneWidget);

      // Simulate refresh by rebuilding widget without error
      await tester.pumpWidget(
        _host(
          BudgetScreen(
            authService: auth,
            budgetService: _StubBudgetService(
              authService: auth,
              overview: _overview,
              todayRecurring: const [],
              recurringItems: const [],
              recurringStats: _recurringStats,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('أنت تشاهد آخر نسخة محفوظة'), findsNothing);
      expect(find.text('المبلغ المتبقي'), findsOneWidget);
    });
  });

  group('recurring occurrence mutations', () {
    testWidgets(
      'bought updates one row locally, guards duplicates, and revalidates',
      (tester) async {
        final auth = _authWithProfile('profile-1');
        final bread = _todayPurchase(id: 'rp-1', name: 'خبز');
        final milk = _todayPurchase(id: 'rp-2', name: 'حليب');
        final completion = Completer<List<TodayRecurringPurchase>>();
        final service = _StubBudgetService(
          authService: auth,
          overview: _overview,
          todayRecurring: [bread, milk],
          recurringStats: _recurringStats,
          markCompleter: completion,
        );

        await _pumpBudget(tester, auth, service);
        expect(find.text('700.00'), findsOneWidget);
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'تم الشراء').first,
        );
        await tester.pump();

        expect(service.markCalls, 1);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'تم الشراء').last,
              )
              .onPressed,
          isNotNull,
        );
        expect(find.text('700.00'), findsOneWidget);

        await tester.tap(find.widgetWithText(OutlinedButton, 'لم أشترِ').first);
        await tester.pump();
        expect(service.markCalls, 1);

        final purchased = _todayPurchase(
          id: 'rp-1',
          name: 'خبز',
          status: 'purchased',
        );
        service.todayRecurring = [purchased, milk];
        completion.complete([purchased, milk]);
        await tester.pump();
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'تم الشراء').first,
              )
              .onPressed,
          isNull,
        );
        expect(service.todayCalls, 1);
        expect(service.overviewCalls, 2);
        expect(service.recurringStatsCalls, 2);
        expect(find.text('700.00'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('skipped updates only the matching occurrence locally', (
      tester,
    ) async {
      final auth = _authWithProfile('profile-1');
      final bread = _todayPurchase(id: 'rp-1', name: 'خبز');
      final milk = _todayPurchase(id: 'rp-2', name: 'حليب');
      final service = _StubBudgetService(
        authService: auth,
        overview: _overview,
        todayRecurring: [bread, milk],
        recurringStats: _recurringStats,
        markResult: [
          _todayPurchase(id: 'rp-1', name: 'خبز', status: 'skipped'),
          milk,
        ],
      );

      await _pumpBudget(tester, auth, service);
      service.todayRecurring = [
        _todayPurchase(id: 'rp-1', name: 'خبز', status: 'skipped'),
        milk,
      ];
      await tester.tap(find.widgetWithText(OutlinedButton, 'لم أشترِ').first);
      await tester.pump();

      expect(service.markCalls, 1);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'لم أشترِ').first,
            )
            .onPressed,
        isNull,
      );
      expect(find.text('حليب'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
      'failed mutation preserves the row, clears busy state, and skips revalidation',
      (tester) async {
        final auth = _authWithProfile('profile-1');
        final service = _StubBudgetService(
          authService: auth,
          overview: _overview,
          todayRecurring: [_todayPurchase(id: 'rp-1', name: 'خبز')],
          recurringStats: _recurringStats,
          markError: Exception('failed'),
        );

        await _pumpBudget(tester, auth, service);
        final initialTodayCalls = service.todayCalls;
        await tester.tap(find.widgetWithText(ElevatedButton, 'تم الشراء'));
        await tester.pump();

        expect(service.markCalls, 1);
        expect(find.text('تم الشراء'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(service.todayCalls, initialTodayCalls);
        expect(service.overviewCalls, 1);
        expect(service.recurringStatsCalls, 1);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('تعذر حفظ التغيير. حاول مرة أخرى.'), findsOneWidget);
      },
    );

    testWidgets('an older refresh cannot restore the pre-mutation occurrence', (
      tester,
    ) async {
      final auth = _authWithProfile('profile-1');
      final pending = _todayPurchase(id: 'rp-1', name: 'خبز');
      final purchased = _todayPurchase(
        id: 'rp-1',
        name: 'خبز',
        status: 'purchased',
      );
      final olderRefresh = Completer<List<TodayRecurringPurchase>>();
      final confirmationRefresh = Completer<List<TodayRecurringPurchase>>();
      final service = _StubBudgetService(
        authService: auth,
        overview: _overview,
        todayRecurring: [pending],
        recurringStats: _recurringStats,
        markResult: [purchased],
      );

      await _pumpBudget(tester, auth, service);
      service.todayCompleters.addAll([olderRefresh, confirmationRefresh]);
      final refresh = tester.state<RefreshIndicatorState>(
        find.byType(RefreshIndicator),
      );
      final refreshFuture = refresh.show();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(service.todayCalls, 2);

      await tester.tap(find.widgetWithText(ElevatedButton, 'تم الشراء'));
      await tester.pump();
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'تم الشراء'),
            )
            .onPressed,
        isNull,
      );
      expect(service.todayCalls, 2);

      confirmationRefresh.complete([purchased]);
      await tester.pump();
      olderRefresh.complete([pending]);
      await refreshFuture;
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'تم الشراء'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets(
      'stale overview cannot replace newer occurrence reconciliation',
      (tester) async {
        final auth = _authWithProfile('profile-1');
        final bread = _todayPurchase(id: 'rp-1', name: 'خبز');
        final milk = _todayPurchase(id: 'rp-2', name: 'حليب');
        final purchased = [
          _todayPurchase(id: 'rp-1', name: 'خبز', status: 'purchased'),
          _todayPurchase(id: 'rp-2', name: 'حليب', status: 'purchased'),
        ];
        final service = _StubBudgetService(
          authService: auth,
          overview: _overview,
          todayRecurring: [bread, milk],
          recurringStats: _recurringStats,
        );
        service.markResults.addAll([
          [purchased.first, milk],
          purchased,
        ]);
        await _pumpBudget(tester, auth, service);
        final oldOverview = Completer<BudgetOverview>();
        final newOverview = Completer<BudgetOverview>();
        service.overviewCompleters.addAll([oldOverview, newOverview]);

        final purchases = find.widgetWithText(ElevatedButton, 'تم الشراء');
        final firstEnabled =
            List.generate(
              purchases.evaluate().length,
              (index) => index,
            ).firstWhere(
              (index) =>
                  tester
                      .widget<ElevatedButton>(purchases.at(index))
                      .onPressed !=
                  null,
            );
        await tester.tap(purchases.at(firstEnabled));
        await tester.pump();
        final secondEnabled =
            List.generate(
              purchases.evaluate().length,
              (index) => index,
            ).firstWhere(
              (index) =>
                  tester
                      .widget<ElevatedButton>(purchases.at(index))
                      .onPressed !=
                  null,
            );
        await tester.tap(purchases.at(secondEnabled));
        await tester.pump();
        expect(service.overviewCalls, 3);
        expect(service.todayCalls, 1);

        newOverview.complete(
          BudgetOverview(
            budgetPlan: _overview.budgetPlan,
            summary: const BudgetSummary(
              daysTotal: 30,
              daysRemaining: 10,
              totalSpent: 112,
              subscriptionTotal: 0,
              remainingMoney: 888,
              safeDailyLimit: 88,
              todaySpending: 50,
              isOverDailyLimit: false,
              plannedRecurringTotal: 0,
              actualRecurringTotal: 50,
              skippedRecurringTotal: 0,
              skippedRecurringCount: 0,
              todayRecurringExpectedTotal: 50,
              todayRecurringPurchasedTotal: 50,
              todayRecurringSkippedCount: 0,
            ),
            activeSubscriptions: const [],
            recentExpenses: const [],
          ),
        );
        await tester.pump();
        expect(find.text('888.00'), findsOneWidget);

        oldOverview.complete(_overview);
        await tester.pump();
        expect(find.text('888.00'), findsOneWidget);
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'تم الشراء').first,
              )
              .onPressed,
          isNull,
        );
      },
    );
  });

  group('expense void', () {
    final expense = Expense(
      id: 'expense-1',
      itemName: 'دفتر',
      amount: 20,
      expenseDate: DateTime(2026, 7, 4),
      source: 'manual',
    );

    BudgetOverview overviewWithExpenses(List<Expense> expenses) =>
        BudgetOverview(
          budgetPlan: _overview.budgetPlan,
          summary: _overview.summary,
          activeSubscriptions: const [],
          recentExpenses: expenses,
        );

    Future<_StubBudgetService> pumpExpense(
      WidgetTester tester, {
      Object? voidError,
      Completer<bool>? voidCompleter,
      bool voidResult = true,
    }) async {
      final auth = _authWithProfile('profile-1');
      final service = _StubBudgetService(
        authService: auth,
        overview: overviewWithExpenses([expense]),
        recurringStats: _recurringStats,
        voidError: voidError,
        voidCompleter: voidCompleter,
        voidResult: voidResult,
      );
      await _pumpBudget(tester, auth, service);
      await tester.tap(find.byTooltip('إلغاء المصروف'));
      await tester.pump();
      return service;
    }

    testWidgets('uses retained-history void wording in an RTL dialog', (
      tester,
    ) async {
      await pumpExpense(tester);

      expect(find.text('إلغاء المصروف'), findsNWidgets(2));
      expect(find.text('دفتر'), findsNWidgets(2));
      expect(
        find.text(
          'سيتم إلغاء هذا المصروف واستبعاده من الحسابات، مع الاحتفاظ بسجله المالي.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('حذف المصروف'), findsNothing);
      expect(
        Directionality.of(tester.element(find.byType(AlertDialog))),
        TextDirection.rtl,
      );
    });

    testWidgets('rejects blank and overlong reasons and trims 300 characters', (
      tester,
    ) async {
      final service = await pumpExpense(tester);
      final confirm = find.widgetWithText(FilledButton, 'إلغاء المصروف');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      final maxReason = List.filled(300, 'a').join();
      await tester.enterText(
        find.byKey(const Key('void-expense-reason')),
        ' $maxReason ',
      );
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      expect(service.voidReason, maxReason);

      final second = await pumpExpense(tester);
      await tester.enterText(
        find.byKey(const Key('void-expense-reason')),
        List.filled(301, 'a').join(),
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(second.voidCalls, 0);
    });

    testWidgets('blocks duplicates and preserves the reason after failure', (
      tester,
    ) async {
      final pending = Completer<bool>();
      final service = await pumpExpense(tester, voidCompleter: pending);
      final reason = find.byKey(const Key('void-expense-reason'));
      final confirm = find.widgetWithText(FilledButton, 'إلغاء المصروف');
      await tester.enterText(reason, 'سبب واضح');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      expect(service.voidCalls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.completeError(Exception('network'));
      await tester.pumpAndSettle();
      expect(find.text('تعذر إلغاء المصروف. حاول مرة أخرى.'), findsOneWidget);
      expect(tester.widget<TextField>(reason).controller!.text, 'سبب واضح');
    });

    testWidgets(
      'refreshes active expenses and totals after a successful void',
      (tester) async {
        final service = await pumpExpense(tester);
        await tester.enterText(
          find.byKey(const Key('void-expense-reason')),
          'مكرر',
        );
        await tester.pump();
        service.overview = BudgetOverview(
          budgetPlan: _overview.budgetPlan,
          summary: const BudgetSummary(
            daysTotal: 30,
            daysRemaining: 10,
            totalSpent: 180,
            subscriptionTotal: 100,
            remainingMoney: 720,
            safeDailyLimit: 72,
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
        );
        await tester.tap(find.widgetWithText(FilledButton, 'إلغاء المصروف'));
        await tester.pumpAndSettle();

        expect(service.voidCalls, 1);
        expect(service.overviewCalls, 2);
        expect(find.text('دفتر'), findsNothing);
        expect(
          find.text('تم إلغاء المصروف مع الاحتفاظ بسجله المالي'),
          findsOneWidget,
        );
      },
    );

    testWidgets('voided false leaves the expense and overview unchanged', (
      tester,
    ) async {
      final service = await pumpExpense(tester, voidResult: false);
      await tester.enterText(
        find.byKey(const Key('void-expense-reason')),
        'already voided',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'إلغاء المصروف'));
      await tester.pumpAndSettle();

      expect(service.voidCalls, 1);
      expect(service.overviewCalls, 1);
      expect(find.text('دفتر'), findsOneWidget);
    });

    testWidgets('void dialog fits at 320px without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpExpense(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('subscription deactivation', () {
    testWidgets('is row-busy, blocks duplicates, and targets overview once', (
      tester,
    ) async {
      final auth = _authWithProfile('profile-1');
      final pending = Completer<void>();
      final sub = AppSubscription(
        id: 'sub-1',
        name: 'ماء',
        amount: 30,
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 30),
        notifyDaysBefore: 3,
        isActive: true,
      );
      final service = _StubBudgetService(
        authService: auth,
        overview: BudgetOverview(
          budgetPlan: _overview.budgetPlan,
          summary: _overview.summary,
          activeSubscriptions: [sub],
          recentExpenses: const [],
        ),
        recurringStats: _recurringStats,
        deactivateSubscriptionCompleter: pending,
      );
      await _pumpBudget(tester, auth, service);
      final initialOverviewCalls = service.overviewCalls;

      await tester.tap(find.byTooltip('إلغاء'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تأكيد'));
      await tester.pump();
      expect(service.deactivateSubscriptionCalls, 1);

      await tester.tap(find.byTooltip('إلغاء'));
      expect(service.deactivateSubscriptionCalls, 1);

      service.overview = BudgetOverview(
        budgetPlan: _overview.budgetPlan,
        summary: _overview.summary,
        activeSubscriptions: const [],
        recentExpenses: const [],
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(service.overviewCalls, initialOverviewCalls + 1);
      expect(find.text('ماء'), findsNothing);
    });
  });

  group('recurring purchase reconciliation', () {
    Future<_StubBudgetService> pumpRecurring(WidgetTester tester) async {
      final auth = _authWithProfile('profile-1');
      final old = _recurringPurchase('old', 'قديم');
      final service = _StubBudgetService(
        authService: auth,
        recurringItems: [old],
        recurringStats: _recurringStats,
      );
      await tester.pumpWidget(_recurringHost(auth, service));
      await tester.pumpAndSettle();
      return service;
    }

    testWidgets('create applies its authoritative list without broad refresh', (
      tester,
    ) async {
      final service = await pumpRecurring(tester);
      service.createResult = [
        _recurringPurchase('old', 'قديم'),
        _recurringPurchase('new', 'جديد'),
      ];
      await tester.tap(find.text('إضافة شراء متكرر'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'جديد');
      await tester.enterText(find.byType(TextField).at(1), '25');
      await tester.ensureVisible(find.text('حفظ'));
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(service.createCalls, 1);
      expect(find.text('جديد'), findsOneWidget);
      expect(service.recurringCalls, 1);
      expect(service.todayCalls, 0);
      expect(service.overviewCalls, 0);
      expect(service.recurringStatsCalls, 2);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
      'update replaces the stable item and cancellation changes nothing',
      (tester) async {
        final service = await pumpRecurring(tester);
        service.updateResult = [_recurringPurchase('old', 'محدّث')];
        await tester.tap(find.byTooltip('تعديل'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(0), 'محدّث');
        await tester.ensureVisible(find.text('تحديث'));
        await tester.tap(find.text('تحديث'));
        await tester.pumpAndSettle();

        expect(service.updateCalls, 1);
        expect(find.text('محدّث'), findsOneWidget);
        expect(find.text('قديم'), findsNothing);
        expect(service.recurringCalls, 1);
        expect(service.todayCalls, 0);
        expect(service.overviewCalls, 0);
        expect(service.recurringStatsCalls, 2);
      },
    );

    testWidgets('removal replaces the active list', (tester) async {
      final service = await pumpRecurring(tester);
      service.deactivateRecurringResult = const [];
      await tester.tap(find.byTooltip('إزالة الشراء المتكرر'));
      await tester.pump();
      expect(find.byType(RecurringRemovalDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'سبب');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('إزالة الشراء المتكرر').last);
      await tester.pumpAndSettle();
      expect(find.text('قديم'), findsNothing);
      expect(service.removeRecurringCalls, 1);
      expect(service.recurringCalls, 1);
      expect(service.todayCalls, 0);
      expect(service.overviewCalls, 0);
      expect(service.recurringStatsCalls, 1);
    });

    testWidgets('recurring management fits at 320px in RTL', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpRecurring(tester);

      expect(
        Directionality.of(tester.element(find.text('قديم'))),
        TextDirection.rtl,
      );
      expect(find.byTooltip('تعديل'), findsOneWidget);
      expect(find.byTooltip('إزالة الشراء المتكرر'), findsOneWidget);
      await tester.ensureVisible(find.text('إضافة شراء متكرر'));
      await tester.tap(find.text('إضافة شراء متكرر'));
      await tester.pumpAndSettle();
      expect(find.text('حفظ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stale recurring statistics cannot replace newer statistics', (
      tester,
    ) async {
      final service = await pumpRecurring(tester);
      final oldStats = Completer<RecurringPurchaseOverview>();
      service.recurringStatsCompleters.add(oldStats);
      service.deactivateRecurringResult = const [];

      final refresh = tester.state<RefreshIndicatorState>(
        find.byType(RefreshIndicator),
      );
      final oldRefresh = refresh.show();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(service.recurringStatsCalls, 2);

      // Removal now receives authoritative statistics in its RPC response.
      oldStats.complete(_recurringStats);
      await oldRefresh;
      expect(service.recurringStatsCalls, 2);
    });
  });

  group('viewport', () {
    testWidgets('recurring purchase actions fit at 320px', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final auth = _authWithProfile('profile-1');
      final service = _StubBudgetService(
        authService: auth,
        overview: _overview,
        todayRecurring: [_todayPurchase(id: 'rp-1', name: 'خبز')],
        recurringStats: _recurringStats,
      );

      await tester.pumpWidget(
        _host(BudgetScreen(authService: auth, budgetService: service)),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ElevatedButton, 'تم الشراء'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'لم أشترِ'), findsOneWidget);
    });

    testWidgets('renders key elements at 320px without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Large figures on purpose: this is the width/data combination that
      // previously triggered a RenderFlex overflow in SpendingProgressCard.
      final stressOverview = BudgetOverview(
        budgetPlan: BudgetPlan(
          id: 'plan-1',
          totalMoney: 999999.99,
          startDate: DateTime(2026, 7, 1),
          endDate: DateTime(2026, 7, 30),
          isActive: true,
        ),
        summary: const BudgetSummary(
          daysTotal: 30,
          daysRemaining: 10,
          totalSpent: 200,
          subscriptionTotal: 100,
          remainingMoney: 700000.5,
          safeDailyLimit: 70,
          todaySpending: 88888.88,
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
      );

      final auth = _authWithProfile('profile-1');
      final service = _StubBudgetService(
        authService: auth,
        overview: stressOverview,
        recurringStats: _recurringStats,
      );

      await tester.pumpWidget(
        _host(BudgetScreen(authService: auth, budgetService: service)),
      );
      await tester.pumpAndSettle();
      // No manual exception handling: an uncaught RenderFlex overflow
      // fails this test automatically via flutter_test's teardown.

      expect(find.text('ميزانيتي'), findsOneWidget);
      expect(find.text('إجراءات سريعة'), findsOneWidget);
    });
  });
}
