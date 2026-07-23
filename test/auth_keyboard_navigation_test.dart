import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/theme/app_theme.dart';
import 'package:zad_al_mahdara/features/auth/presentation/login_screen.dart';
import 'package:zad_al_mahdara/features/auth/presentation/register_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _AuthStub extends AuthService {
  final Completer<void>? loginPending;
  final Completer<void>? registerPending;
  int loginCalls = 0;
  int registerCalls = 0;

  _AuthStub({this.loginPending, this.registerPending});

  @override
  Future<void> login(String phone, String pin) async {
    loginCalls++;
    await loginPending?.future;
  }

  @override
  Future<void> register(String name, String phone, String pin) async {
    registerCalls++;
    await registerPending?.future;
  }
}

Future<void> _pump(WidgetTester tester, Widget screen, {Size? size}) async {
  tester.view.physicalSize = size ?? const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Directionality(textDirection: TextDirection.rtl, child: screen),
    ),
  );
  await tester.pumpAndSettle();
}

FocusNode _editableFocusOf(WidgetTester tester, Finder textFieldFinder) =>
    tester
        .widget<EditableText>(
          find.descendant(
            of: textFieldFinder,
            matching: find.byType(EditableText),
          ),
        )
        .focusNode;

Future<void> _shiftTab(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

void main() {
  testWidgets('login fields follow correct keyboard order (Tab / Shift+Tab)', (
    tester,
  ) async {
    await _pump(tester, LoginScreen(authService: _AuthStub()));
    final fields = find.byType(TextField);
    final phoneFocus = _editableFocusOf(tester, fields.at(0));
    final pinFocus = _editableFocusOf(tester, fields.at(1));

    phoneFocus.requestFocus();
    await tester.pump();
    expect(phoneFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(pinFocus.hasFocus, isTrue);

    await _shiftTab(tester);
    expect(phoneFocus.hasFocus, isTrue);
  });

  testWidgets('Enter moves between login fields', (tester) async {
    await _pump(tester, LoginScreen(authService: _AuthStub()));
    final fields = find.byType(TextField);
    final phoneFocus = _editableFocusOf(tester, fields.at(0));
    final pinFocus = _editableFocusOf(tester, fields.at(1));

    phoneFocus.requestFocus();
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(pinFocus.hasFocus, isTrue);
  });

  testWidgets('Enter on final login field submits once', (tester) async {
    final pending = Completer<void>();
    final service = _AuthStub(loginPending: pending);
    await _pump(tester, LoginScreen(authService: service));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '12345678');
    await tester.enterText(fields.at(1), '1234');

    _editableFocusOf(tester, fields.at(1)).requestFocus();
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(service.loginCalls, 1);
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('registration fields follow correct keyboard order', (
    tester,
  ) async {
    await _pump(tester, RegisterScreen(authService: _AuthStub()));
    final fields = find.byType(TextField);
    final nameFocus = _editableFocusOf(tester, fields.at(0));
    final phoneFocus = _editableFocusOf(tester, fields.at(1));
    final pinFocus = _editableFocusOf(tester, fields.at(2));
    final confirmFocus = _editableFocusOf(tester, fields.at(3));

    nameFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(phoneFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(pinFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(confirmFocus.hasFocus, isTrue);

    await _shiftTab(tester);
    expect(pinFocus.hasFocus, isTrue);
  });

  testWidgets('Enter on final registration field submits once', (tester) async {
    final pending = Completer<void>();
    final service = _AuthStub(registerPending: pending);
    await _pump(tester, RegisterScreen(authService: service));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'اسم');
    await tester.enterText(fields.at(1), '12345678');
    await tester.enterText(fields.at(2), '1234');
    await tester.enterText(fields.at(3), '1234');

    _editableFocusOf(tester, fields.at(3)).requestFocus();
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(service.registerCalls, 1);
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('password visibility control is keyboard-accessible', (
    tester,
  ) async {
    await _pump(tester, LoginScreen(authService: _AuthStub()));
    final fields = find.byType(TextField);
    final pinFocus = _editableFocusOf(tester, fields.at(1));
    final toggle = tester.widget<IconButton>(find.byType(IconButton));
    final toggleFocus = toggle.focusNode!;

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    pinFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(toggleFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('login and registration fit at 320px RTL without overflow', (
    tester,
  ) async {
    await _pump(
      tester,
      LoginScreen(authService: _AuthStub()),
      size: const Size(320, 800),
    );
    expect(tester.takeException(), isNull);

    await _pump(
      tester,
      RegisterScreen(authService: _AuthStub()),
      size: const Size(320, 800),
    );
    expect(tester.takeException(), isNull);
  });
}
