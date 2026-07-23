import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zad_al_mahdara/features/budget/data/budget_service.dart';
import 'package:zad_al_mahdara/features/budget/domain/budget_models.dart';
import 'package:zad_al_mahdara/features/budget/presentation/recurring_purchase_form_screen.dart';
import 'package:zad_al_mahdara/features/budget/presentation/recurring_purchases_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

final _stats = RecurringPurchaseOverview(
  activeRecurringCount: 0,
  todayExpectedTotal: 0,
  todayPurchasedTotal: 0,
  todaySkippedCount: 0,
  plannedTotal: 0,
  actualPurchasedTotal: 0,
  skippedTotal: 0,
  skippedCount: 0,
);

RecurringPurchase _item({String? reminderTime}) => RecurringPurchase(
  id: 'r1',
  name: 'حليب',
  price: 25,
  frequency: 'daily',
  startDate: DateTime(2026, 7, 1),
  endDate: DateTime(2026, 7, 31),
  reminderTime: reminderTime,
  isActive: true,
);

class _StubBudgetService extends BudgetService {
  final List<RecurringPurchase> items;
  String? capturedUpdateReminderTime;

  _StubBudgetService(super.auth, this.items);

  @override
  Future<List<RecurringPurchase>> getRecurringPurchases() async => items;

  @override
  Future<RecurringPurchaseOverview> getRecurringPurchaseOverview() async =>
      _stats;

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
    capturedUpdateReminderTime = reminderTime;
    return items;
  }
}

Widget _host(AuthService auth, _StubBudgetService service) {
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

void main() {
  testWidgets('recurring purchase list shows Arabic AM/PM reminder time', (
    tester,
  ) async {
    final auth = AuthService();
    final service = _StubBudgetService(auth, [_item(reminderTime: '08:30')]);
    await tester.pumpWidget(_host(auth, service));
    await tester.pumpAndSettle();

    expect(find.textContaining('8:30 ص'), findsOneWidget);
    expect(find.textContaining('08:30'), findsNothing);
  });

  testWidgets(
    'edit form displays Arabic AM/PM but saves the canonical 24-hour value',
    (tester) async {
      final auth = AuthService();
      final service = _StubBudgetService(auth, [_item(reminderTime: '15:45')]);
      await tester.pumpWidget(_host(auth, service));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('تعديل'));
      await tester.pumpAndSettle();

      expect(find.text('3:45 م'), findsOneWidget);

      await tester.ensureVisible(find.text('تحديث'));
      await tester.tap(find.text('تحديث'));
      await tester.pumpAndSettle();

      expect(service.capturedUpdateReminderTime, '15:45');
    },
  );
}
