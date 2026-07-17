import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/auth/presentation/forgot_pin_screen.dart';
import 'package:zad_al_mahdara/features/auth/presentation/login_screen.dart';
import 'package:zad_al_mahdara/features/auth/presentation/register_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

void main() {
  testWidgets('login formats phone, keeps PIN unchanged, and submits digits', (
    tester,
  ) async {
    final service = _PhoneAuthService();
    await _pump(tester, LoginScreen(authService: service));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '1234567');
    await tester.tap(find.text('دخول'));
    await tester.pump();
    expect(service.loginPhone, isNull);
    await tester.enterText(fields.at(0), '12-34-56-78');
    await tester.enterText(fields.at(1), '1234');
    expect(
      (tester.widget<TextField>(fields.at(0)).controller!.text),
      '12 34 56 78',
    );
    expect((tester.widget<TextField>(fields.at(1)).controller!.text), '1234');
    await tester.tap(find.text('دخول'));
    await tester.pump();
    expect(service.loginPhone, '12345678');
  });

  testWidgets('registration formats pasted phone and submits digits', (
    tester,
  ) async {
    final service = _PhoneAuthService();
    await _pump(tester, RegisterScreen(authService: service));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Name');
    await tester.enterText(fields.at(1), '12 34 56 78');
    await tester.enterText(fields.at(2), '1234');
    await tester.enterText(fields.at(3), '1234');
    expect(
      (tester.widget<TextField>(fields.at(1)).controller!.text),
      '12 34 56 78',
    );
    await tester.tap(find.text('إنشاء الحساب'));
    await tester.pump();
    expect(service.registerPhone, '12345678');
  });

  testWidgets('forgot PIN validates and submits normalized digits at 320px', (
    tester,
  ) async {
    final service = _PhoneAuthService();
    await _pump(tester, ForgotPinScreen(authService: service));
    await tester.enterText(find.byType(TextField), '12-34-56-78');
    await tester.tap(find.text('إرسال الطلب'));
    await tester.pump();
    expect(service.resetPhone, '12345678');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, Widget screen) => tester
    .pumpWidget(
      const Directionality(textDirection: TextDirection.rtl, child: SizedBox()),
    )
    .then(
      (_) => tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(320, 640)),
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: screen,
            ),
          ),
        ),
      ),
    );

class _PhoneAuthService extends AuthService {
  String? loginPhone;
  String? registerPhone;
  String? resetPhone;

  @override
  Future<void> login(String phone, String pin) async => loginPhone = phone;

  @override
  Future<void> register(String name, String phone, String pin) async =>
      registerPhone = phone;

  @override
  Future<void> requestPinReset(String phone) async => resetPhone = phone;
}
