import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/widgets/mauritanian_phone_field.dart';
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
    _expectPhoneFieldLtr(tester);
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid login stays generic and preserves fields at 320x800', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final service = _PhoneAuthService(
      loginError: const InvalidCredentialsException(),
    );
    await _pump(tester, LoginScreen(authService: service));
    final fields = find.byType(TextField);

    await tester.enterText(fields.at(0), '12-34-56-78');
    await tester.enterText(fields.at(1), '1357');
    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();

    expect(find.text('الرقم أو الرمز السري غير صحيح'), findsOneWidget);
    expect(
      tester.widget<TextField>(fields.at(0)).controller!.text,
      '12 34 56 78',
    );
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, '1357');
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('دخول'), findsOneWidget);
    _expectPhoneFieldLtr(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending login blocks duplicate submission', (tester) async {
    final pending = Completer<void>();
    final service = _PhoneAuthService(loginPending: pending);
    await _pump(tester, LoginScreen(authService: service));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '12-34-56-78');
    await tester.enterText(fields.at(1), '2468');

    await tester.tap(find.text('دخول'));
    await tester.tap(find.text('دخول'));
    await tester.pump();

    expect(service.loginCalls, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('دخول'), findsOneWidget);
  });

  testWidgets('unexpected login failure shows the general error', (
    tester,
  ) async {
    final service = _PhoneAuthService(loginError: Exception('backend down'));
    await _pump(tester, LoginScreen(authService: service));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '12-34-56-78');
    await tester.enterText(fields.at(1), '2468');

    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();

    expect(find.text('حدث خطأ — تحقق من اتصالك بالإنترنت'), findsOneWidget);
    expect(find.text('الرقم أو الرمز السري غير صحيح'), findsNothing);
  });

  testWidgets('registration formats pasted phone and submits digits', (
    tester,
  ) async {
    final service = _PhoneAuthService();
    await _pump(tester, RegisterScreen(authService: service));
    final fields = find.byType(TextField);
    _expectPhoneFieldLtr(tester);
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('forgot PIN validates and submits normalized digits at 320px', (
    tester,
  ) async {
    final service = _PhoneAuthService();
    await _pump(tester, ForgotPinScreen(authService: service));
    _expectPhoneFieldLtr(tester);
    await tester.enterText(find.byType(TextField), '12-34-56-78');
    await tester.tap(find.text('إرسال الطلب'));
    await tester.pump();
    expect(service.resetPhone, '12345678');
    expect(tester.takeException(), isNull);
  });
}

void _expectPhoneFieldLtr(WidgetTester tester) {
  expect(
    tester
        .widget<TextField>(
          find.descendant(
            of: find.byType(MauritanianPhoneField),
            matching: find.byType(TextField),
          ),
        )
        .textDirection,
    TextDirection.ltr,
  );
  expect(
    tester
        .widget<Directionality>(find.byType(Directionality).last)
        .textDirection,
    TextDirection.rtl,
  );
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
  final Object? loginError;
  final Completer<void>? loginPending;
  String? loginPhone;
  String? registerPhone;
  String? resetPhone;
  int loginCalls = 0;

  _PhoneAuthService({this.loginError, this.loginPending});

  @override
  Future<void> login(String phone, String pin) async {
    loginCalls++;
    loginPhone = phone;
    if (loginError != null) throw loginError!;
    await loginPending?.future;
  }

  @override
  Future<void> register(String name, String phone, String pin) async =>
      registerPhone = phone;

  @override
  Future<void> requestPinReset(String phone) async => resetPhone = phone;
}
