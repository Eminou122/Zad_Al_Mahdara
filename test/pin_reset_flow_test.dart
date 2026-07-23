import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/auth/presentation/reset_pin_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

void main() {
  testWidgets(
    'locked phone, masked name, and five minute countdown render at 320px',
    (tester) async {
      final request = PinResetRequest(
        id: 'request-a',
        maskedName: 'م*** ع***',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(320, 800)),
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: ResetPinScreen(
                authService: _FakeAuthService(),
                phone: '49413435',
                request: request,
              ),
            ),
          ),
        ),
      );
      expect(find.text('الحساب: م*** ع***'), findsOneWidget);
      expect(find.textContaining('الوقت المتبقي:'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).readOnly,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeAuthService extends AuthService {
  @override
  Future<bool> completePinReset(
    String id,
    String code,
    String pin,
    String confirmation,
  ) async => false;
}
