import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zad_al_mahdara/features/budget/data/budget_service.dart';
import 'package:zad_al_mahdara/features/budget/domain/budget_models.dart';
import 'package:zad_al_mahdara/features/budget/presentation/expense_form_screen.dart';
import 'package:zad_al_mahdara/features/budget/presentation/subscription_form_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _FormBudgetService extends BudgetService {
  final BudgetOverview result;
  _FormBudgetService(super.auth, this.result);

  @override
  Future<BudgetOverview> addExpense({
    required String itemName,
    required double amount,
    String? category,
    String? note,
    required DateTime expenseDate,
  }) async => result;

  @override
  Future<BudgetOverview> addSubscription({
    required String name,
    required double amount,
    required DateTime startDate,
    required DateTime endDate,
    required int notifyDaysBefore,
  }) async => result;
}

AuthService _auth() => AuthService();

final _result = BudgetOverview(
  activeSubscriptions: const [],
  recentExpenses: const [],
);

Future<Completer<Object?>> _runForm(WidgetTester tester, Widget form) async {
  final result = Completer<Object?>();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: ElevatedButton(
            onPressed: () async => result.complete(await context.push('/form')),
            child: const Text('open'),
          ),
        ),
      ),
      GoRoute(path: '/form', builder: (context, state) => form),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('expense success returns the authoritative overview', (
    tester,
  ) async {
    final service = _FormBudgetService(_auth(), _result);
    final result = await _runForm(
      tester,
      ExpenseFormScreen(authService: _auth(), budgetService: service),
    );
    await tester.enterText(find.byType(TextField).first, 'دفتر');
    await tester.enterText(find.byType(TextField).at(1), '20');
    await tester.tap(find.text('حفظ المصروف'));
    await tester.pumpAndSettle();
    expect(await result.future, same(_result));
  });

  testWidgets('subscription success returns the authoritative overview', (
    tester,
  ) async {
    final service = _FormBudgetService(_auth(), _result);
    final result = await _runForm(
      tester,
      SubscriptionFormScreen(authService: _auth(), budgetService: service),
    );
    await tester.enterText(find.byType(TextField).first, 'ماء');
    await tester.enterText(find.byType(TextField).at(1), '30');
    await tester.tap(find.text('حفظ الاشتراك'));
    await tester.pumpAndSettle();
    expect(await result.future, same(_result));
  });
}
