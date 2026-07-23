import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/budget/data/budget_service.dart';
import 'package:zad_al_mahdara/features/budget/domain/budget_models.dart';
import 'package:zad_al_mahdara/features/budget/presentation/recurring_purchase_history_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _HistoryBudgetService extends BudgetService {
  final List<RecurringPurchaseHistoryItem> items;
  Object? deleteError;
  List<String>? deletedIds;

  _HistoryBudgetService(this.items) : super(AuthService());

  @override
  Future<List<RecurringPurchaseHistoryItem>> getRecurringPurchaseHistory({
    String? recurringPurchaseId,
    int limit = 50,
    int offset = 0,
  }) async => items;

  @override
  Future<BudgetOverview> deleteRecurringPurchaseOccurrences(
    List<String> ids,
  ) async {
    deletedIds = ids;
    if (deleteError != null) throw deleteError!;
    return const BudgetOverview(activeSubscriptions: [], recentExpenses: []);
  }
}

RecurringPurchaseHistoryItem _item(String id, String name) =>
    RecurringPurchaseHistoryItem(
      occurrenceId: id,
      recurringPurchaseId: 'purchase-1',
      name: name,
      price: 12.5,
      occurrenceDate: DateTime(2026, 2, 3),
      status: 'purchased',
      isVoided: false,
      definitionRemoved: false,
    );

Future<void> _pump(WidgetTester tester, _HistoryBudgetService service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: RecurringPurchaseHistoryScreen(
          authService: AuthService(),
          budgetService: service,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _confirmDelete(WidgetTester tester) async {
  final confirm = find.widgetWithText(FilledButton, 'حذف نهائياً');
  expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
  await tester.pump(const Duration(seconds: 3));
  await tester.tap(confirm);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('permanently deletes a purchase from history', (tester) async {
    final service = _HistoryBudgetService([_item('purchase-1', 'حليب')]);
    await _pump(tester, service);

    await tester.tap(find.text('حذف نهائياً'));
    await tester.pump();
    await _confirmDelete(tester);

    expect(service.deletedIds, ['purchase-1']);
    expect(find.text('حليب'), findsNothing);
  });

  testWidgets('selects all purchases and deletes them together', (
    tester,
  ) async {
    final service = _HistoryBudgetService([
      _item('purchase-1', 'حليب'),
      _item('purchase-2', 'خبز'),
    ]);
    await _pump(tester, service);

    await tester.tap(find.text('تحديد'));
    await tester.pump();
    await tester.tap(find.text('تحديد الكل'));
    await tester.pump();
    expect(find.text('تم تحديد 2'), findsOneWidget);
    await tester.tap(find.text('حذف المحدد'));
    await tester.pump();
    await _confirmDelete(tester);

    expect(service.deletedIds, ['purchase-1', 'purchase-2']);
    expect(find.text('حليب'), findsNothing);
    expect(find.text('خبز'), findsNothing);
  });

  testWidgets('cancels purchase selection without deleting records', (
    tester,
  ) async {
    final service = _HistoryBudgetService([_item('purchase-1', 'حليب')]);
    await _pump(tester, service);

    await tester.tap(find.text('تحديد'));
    await tester.pump();
    await tester.tap(find.text('تحديد الكل'));
    await tester.pump();
    await tester.tap(find.text('إلغاء التحديد'));
    await tester.pump();

    expect(service.deletedIds, isNull);
    expect(find.text('حليب'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('failed deletion preserves selection and shows a safe error', (
    tester,
  ) async {
    final service = _HistoryBudgetService([_item('purchase-1', 'حليب')])
      ..deleteError = Exception('network');
    await _pump(tester, service);

    await tester.tap(find.text('تحديد'));
    await tester.pump();
    await tester.tap(find.text('تحديد الكل'));
    await tester.pump();
    await tester.tap(find.text('حذف المحدد'));
    await tester.pump();
    await _confirmDelete(tester);

    expect(service.deletedIds, ['purchase-1']);
    expect(find.text('تم تحديد 1'), findsOneWidget);
    expect(find.textContaining('حدث خطأ'), findsOneWidget);
  });

  testWidgets('purchase deletion UI fits at 320px RTL', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester, _HistoryBudgetService([_item('purchase-1', 'حليب')]));

    await tester.tap(find.text('حذف نهائياً'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
