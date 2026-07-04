import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/auth/presentation/forgot_pin_screen.dart';
import 'package:zad_al_mahdara/features/auth/presentation/reset_pin_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

void main() {
  testWidgets('forgot PIN always shows generic success', (tester) async {
    final service = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ForgotPinScreen(authService: service),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '49413435');
    await tester.tap(find.text('إرسال الطلب'));
    await tester.pumpAndSettle();

    expect(service.requestedPhone, '49413435');
    expect(
      find.text('إذا كان هذا الرقم موجودًا، فقد تم إرسال طلبك إلى الإدارة.'),
      findsOneWidget,
    );
  });

  testWidgets('reset PIN validates inputs locally', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ResetPinScreen(authService: _FakeAuthService()),
        ),
      ),
    );

    await tester.tap(find.text('تغيير الرمز السري'));
    await tester.pumpAndSettle();

    expect(find.text('رقم الهاتف يجب أن يكون 8 أرقام'), findsOneWidget);
  });

  testWidgets('reset PIN shows generic failure and keeps code LTR', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ResetPinScreen(authService: _FakeAuthService(completeOk: false)),
        ),
      ),
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '49413435');
    await tester.enterText(fields.at(1), '12345678');
    await tester.enterText(fields.at(2), '2468');
    await tester.enterText(fields.at(3), '2468');
    await tester.tap(find.text('تغيير الرمز السري'));
    await tester.pumpAndSettle();

    expect(find.text('رمز إعادة التعيين غير صحيح أو منتهي الصلاحية.'), findsOneWidget);
    _expectNearestTextDirection(
      tester,
      find.text('12345678'),
      TextDirection.ltr,
    );
  });
}

void _expectNearestTextDirection(
  WidgetTester tester,
  Finder finder,
  TextDirection direction,
) {
  for (final element in finder.evaluate()) {
    final widget = element.findAncestorWidgetOfExactType<Directionality>();
    expect(widget?.textDirection, direction);
  }
}

class _FakeAuthService extends AuthService {
  final bool completeOk;
  String? requestedPhone;

  _FakeAuthService({this.completeOk = true});

  @override
  Future<void> requestPinReset(String phone) async {
    requestedPhone = phone;
  }

  @override
  Future<bool> completePinReset(String phone, String code, String newPin) async {
    return completeOk;
  }
}
