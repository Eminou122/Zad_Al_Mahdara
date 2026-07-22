import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/budget/presentation/widgets/recurring_removal_dialog.dart';

void main() {
  Future<void> open(
    WidgetTester t,
    Future<void> Function(String) submit, {
    Duration duration = const Duration(seconds: 3),
  }) => t
      .pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => ElevatedButton(
              onPressed: () => showDialog(
                context: c,
                builder: (_) => RecurringRemovalDialog(
                  title: 'إلغاء عملية الشراء',
                  body:
                      'سيتم إلغاء عملية الشراء المحددة وعكس أثرها من المصروفات، مع الاحتفاظ بسجلها المالي.',
                  details: const ['الحليب', '2026-07-22', '25.00 MRU'],
                  actionLabel: 'إلغاء العملية',
                  onSubmit: submit,
                  countdown: duration,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      )
      .then((_) => t.tap(find.text('open')))
      .then((_) => t.pump());

  testWidgets('Arabic details, validation, countdown, and trimmed submit', (
    t,
  ) async {
    String? reason;
    await open(t, (v) async => reason = v);
    expect(find.text('إلغاء عملية الشراء'), findsOneWidget);
    expect(find.text('الحليب'), findsOneWidget);
    expect(find.text('إلغاء العملية (3)'), findsOneWidget);
    await t.tap(find.text('إلغاء العملية (3)'));
    await t.pump();
    expect(find.text('السبب مطلوب ويجب ألا يتجاوز 300 حرف'), findsNothing);
    await t.enterText(find.byType(TextField), '  سبب  ');
    await t.pump(const Duration(seconds: 3));
    expect(find.text('إلغاء العملية'), findsOneWidget);
    await t.tap(find.text('إلغاء العملية'));
    await t.pumpAndSettle();
    expect(reason, 'سبب');
  });
  testWidgets('failure preserves reason and 301 is rejected', (t) async {
    await open(t, (_) async => throw Exception());
    await t.enterText(find.byType(TextField), 'x' * 301);
    await t.pump(const Duration(seconds: 3));
    await t.tap(find.text('إلغاء العملية'));
    await t.pump();
    expect(find.text('السبب مطلوب ويجب ألا يتجاوز 300 حرف'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'سبب');
    await t.tap(find.text('إلغاء العملية'));
    await t.pump();
    expect(find.text('حدث خطأ — حاول مرة أخرى'), findsOneWidget);
    expect(find.text('سبب'), findsOneWidget);
  });

  testWidgets(
    'countdown, cancel, pending submit, retry, and disposal are safe',
    (t) async {
      final pending = Completer<void>();
      var calls = 0;
      await open(t, (_) {
        calls++;
        return pending.future;
      });
      expect(find.text('0/300'), findsOneWidget);
      expect(find.text('إلغاء'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('إلغاء العملية (2)'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('إلغاء العملية (1)'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      await t.enterText(find.byType(TextField), ' سبب ');
      await t.tap(find.text('إلغاء العملية'));
      await t.pump();
      await t.tap(find.byType(FilledButton));
      await t.pump();
      expect(calls, 1);
      pending.complete();
      await t.pumpAndSettle();
      expect(find.byType(RecurringRemovalDialog), findsNothing);
      await open(t, (_) async {});
      await t.tap(find.text('إلغاء'));
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('RTL 320 layout keeps long details and controls visible', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 800);
    t.view.devicePixelRatio = 1;
    await open(t, (_) async {});
    await t.enterText(find.byType(TextField), 'نص متعدد الأسطر للاختبار');
    expect(find.text('إلغاء العملية (3)'), findsOneWidget);
    expect(find.text('0/300'), findsOneWidget);
    expect(t.takeException(), isNull);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  });
}
