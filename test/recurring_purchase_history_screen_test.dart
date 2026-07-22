import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/budget/data/budget_service.dart';
import 'package:zad_al_mahdara/features/budget/presentation/recurring_purchase_history_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

Map<String, dynamic> _item(String id, String status, bool voided) => {
  'occurrence_id': id,
  'recurring_purchase_id': 'purchase-1',
  'name': 'حليب',
  'price': 12.5,
  'occurrence_date': '2026-02-03',
  'status': status,
  'is_voided': voided,
  'void_reason': null,
  'voided_at': null,
  'expense_id': null,
  'definition_removed': false,
};

void main() {
  testWidgets('history shows statuses and only purchased can be removed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = BudgetService(
      AuthService(),
      sessionTokenProvider: () => 'test-token',
      rpcCaller: (name, {params}) async {
        expect(name, 'get_recurring_purchase_history');
        return {
          'items': [
            _item('purchased', 'purchased', false),
            _item('skipped', 'skipped', false),
            _item('voided', 'purchased', true),
          ],
        };
      },
    );
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

    expect(find.text('تم الشراء'), findsOneWidget);
    expect(find.text('تم التخطي'), findsOneWidget);
    expect(find.text('ملغاة'), findsOneWidget);
    expect(find.text('إلغاء عملية الشراء'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
