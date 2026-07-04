import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zad_al_mahdara/features/account/presentation/account_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

void main() {
  testWidgets('account screen renders name and PIN sections', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountScreen(authService: _FakeAuthService()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('الاسم الظاهر'), findsWidgets);
    expect(find.text('تغيير الرمز السري'), findsWidgets);
    expect(find.text('حفظ الاسم'), findsOneWidget);
  });

  testWidgets('name validation: empty name shows error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountScreen(authService: _FakeAuthService()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nameFields = find.byType(TextField);
    await tester.enterText(nameFields.first, '   ');
    await tester.tap(find.text('حفظ الاسم'));
    await tester.pumpAndSettle();

    expect(find.text('الاسم لا يمكن أن يكون فارغًا'), findsOneWidget);
  });

  testWidgets('name validation: too-long name shows error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountScreen(authService: _FakeAuthService()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nameFields = find.byType(TextField);
    await tester.enterText(nameFields.first, 'A' * 81);
    await tester.tap(find.text('حفظ الاسم'));
    await tester.pumpAndSettle();

    expect(find.text('الاسم طويل جدًا (الحد الأقصى 80 حرفًا)'), findsOneWidget);
  });

  testWidgets('PIN validation: non-4-digit current PIN shows error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountScreen(authService: _FakeAuthService()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '12');
    await tester.enterText(fields.at(2), '5678');
    await tester.enterText(fields.at(3), '5678');
    await tester.tap(find.widgetWithText(ElevatedButton, 'تغيير الرمز السري'));
    await tester.pumpAndSettle();

    expect(find.text('الرمز الحالي يجب أن يكون 4 أرقام'), findsOneWidget);
  });

  testWidgets('PIN validation: non-4-digit new PIN shows error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountScreen(authService: _FakeAuthService()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '1234');
    await tester.enterText(fields.at(2), '56');
    await tester.enterText(fields.at(3), '56');
    await tester.tap(find.widgetWithText(ElevatedButton, 'تغيير الرمز السري'));
    await tester.pumpAndSettle();

    expect(find.text('الرمز الجديد يجب أن يكون 4 أرقام'), findsOneWidget);
  });

  testWidgets('PIN validation: mismatch shows error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountScreen(authService: _FakeAuthService()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '1234');
    await tester.enterText(fields.at(2), '5678');
    await tester.enterText(fields.at(3), '9999');
    await tester.tap(find.widgetWithText(ElevatedButton, 'تغيير الرمز السري'));
    await tester.pumpAndSettle();

    expect(find.text('الرمزان السريان لا يتطابقان'), findsOneWidget);
  });

  testWidgets('PIN fields obscure text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountScreen(authService: _FakeAuthService()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pinFields = find.byType(TextField);
    for (int i = 1; i <= 3; i++) {
      final field = tester.widget<TextField>(pinFields.at(i));
      expect(field.obscureText, isTrue, reason: 'PIN field $i should obscure text');
    }
  });

  testWidgets('no pin_hash or full phone shown', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountScreen(authService: _FakeAuthService()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('pin_hash'), findsNothing);
    expect(find.textContaining('pinHash'), findsNothing);
    expect(find.textContaining('phoneNumber'), findsNothing);
    expect(find.textContaining('phone_number'), findsNothing);
  });

  testWidgets('320px width no overflow', (tester) async {
    tester.view.physicalSize = const Size(640, 1200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountScreen(authService: _FakeAuthService()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('successful name update clears error and calls service', (
    tester,
  ) async {
    final service = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountScreen(authService: service),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nameFields = find.byType(TextField);
    await tester.enterText(nameFields.first, 'NewName');
    await tester.tap(find.text('حفظ الاسم'));
    await tester.pumpAndSettle();

    expect(service.updatedName, 'NewName');
    expect(find.text('تم تحديث الاسم'), findsOneWidget);
  });

  testWidgets('PIN change ok:true clears fields and shows success', (
    tester,
  ) async {
    final service = _FakeAuthService(pinOk: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountScreen(authService: service),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '1234');
    await tester.enterText(fields.at(2), '5678');
    await tester.enterText(fields.at(3), '5678');
    await tester.tap(find.widgetWithText(ElevatedButton, 'تغيير الرمز السري'));
    await tester.pumpAndSettle();

    expect(service.changedCurrentPin, '1234');
    expect(service.changedNewPin, '5678');
    expect(find.text('تم تغيير الرمز السري'), findsOneWidget);
  });

  testWidgets('PIN change ok:false shows generic error', (tester) async {
    final service = _FakeAuthService(pinOk: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountScreen(authService: service),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '1234');
    await tester.enterText(fields.at(2), '5678');
    await tester.enterText(fields.at(3), '5678');
    await tester.tap(find.widgetWithText(ElevatedButton, 'تغيير الرمز السري'));
    await tester.pumpAndSettle();

    expect(
      find.text('الرمز الحالي غير صحيح أو الحساب مقفل مؤقتًا.'),
      findsOneWidget,
    );
  });

  testWidgets('PIN change PostgrestException shows generic error', (
    tester,
  ) async {
    final service = _FakeAuthService(pinThrows: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountScreen(authService: service),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '1234');
    await tester.enterText(fields.at(2), '5678');
    await tester.enterText(fields.at(3), '5678');
    await tester.tap(find.widgetWithText(ElevatedButton, 'تغيير الرمز السري'));
    await tester.pumpAndSettle();

    expect(
      find.text('الرمز الحالي غير صحيح أو الحساب مقفل مؤقتًا.'),
      findsOneWidget,
    );
  });

  testWidgets('name update PostgrestException shows generic error', (
    tester,
  ) async {
    final service = _FakeAuthService(nameThrows: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountScreen(authService: service),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nameFields = find.byType(TextField);
    await tester.enterText(nameFields.first, 'NewName');
    await tester.tap(find.text('حفظ الاسم'));
    await tester.pumpAndSettle();

    expect(
      find.text('تعذر تحديث الاسم — الرجاء المحاولة لاحقًا'),
      findsOneWidget,
    );
  });
}

class _FakeAuthService extends AuthService {
  final bool pinOk;
  final bool pinThrows;
  final bool nameThrows;
  String? updatedName;
  String? changedCurrentPin;
  String? changedNewPin;

  UserProfile? _fakeProfile;

  _FakeAuthService({
    this.pinOk = true,
    this.pinThrows = false,
    this.nameThrows = false,
  }) {
    _fakeProfile = const UserProfile(
      id: 'test-id',
      displayName: 'TestUser',
      phoneMasked: '12****34',
      isAdmin: false,
      isActive: true,
    );
  }

  @override
  UserProfile? get profile => _fakeProfile;

  @override
  String get displayName => _fakeProfile?.displayName ?? '';

  @override
  bool get isAuthenticated => _fakeProfile != null;

  @override
  Future<void> updateProfileName(String name) async {
    updatedName = name;
    if (nameThrows) throw PostgrestException(message: 'simulated error');
    _fakeProfile = UserProfile(
      id: _fakeProfile!.id,
      displayName: name,
      phoneMasked: _fakeProfile!.phoneMasked,
      isAdmin: _fakeProfile!.isAdmin,
      isActive: _fakeProfile!.isActive,
    );
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> changePin(
    String currentPin,
    String newPin,
  ) async {
    changedCurrentPin = currentPin;
    changedNewPin = newPin;
    if (pinThrows) throw PostgrestException(message: 'simulated error');
    if (pinOk) {
      return {'ok': true};
    } else {
      return {'ok': false, 'message': 'incorrect pin'};
    }
  }
}
