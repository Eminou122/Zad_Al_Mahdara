import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/routing/app_router.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';
import 'package:zad_al_mahdara/services/session_storage.dart';

Map<String, dynamic> _profileJson() => {
  'id': 'u1',
  'display_name': 'سارة',
  'phone_masked': '12****78',
  'is_admin': false,
  'is_active': true,
};

class _FakeAuthService extends AuthService {
  Map<String, dynamic>? Function(String token)? onFetch;
  Object? throwing;

  @override
  Future<Map<String, dynamic>?> fetchProfileBySessionToken(String token) async {
    if (throwing != null) throw throwing!;
    return onFetch?.call(token);
  }
}

void main() {
  setUp(SessionStorage.clear);

  testWidgets(
    'router guard sends an unverified (network-failed) session to login, '
    'not into a protected screen, and shows the retry banner',
    (tester) async {
      SessionStorage.write('tok-network');
      final auth = _FakeAuthService()..throwing = Exception('offline');
      await auth.retrySessionRestore();
      expect(auth.sessionRestoreFailed, isTrue);
      expect(auth.isAuthenticated, isFalse);

      final router = AppRouter(auth).router;
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      // Flush SplashScreen's 2s navigation timer before leaving it, so no
      // pending timer remains when the test ends (same pattern as
      // widget_test.dart).
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      router.go('/home');
      await tester.pumpAndSettle();

      // Blocked from the protected screen — landed on login instead.
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(find.text('الرئيسية'), findsNothing);
      // Safe retry UX, not a silent logout: the token is still there and
      // the reason is explained.
      expect(SessionStorage.read(), 'tok-network');
      expect(
        find.text('تعذر التحقق من الجلسة، تحقق من اتصالك بالإنترنت'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'retrying from the login screen after connectivity returns enters the '
    'app normally',
    (tester) async {
      SessionStorage.write('tok-network');
      final auth = _FakeAuthService()..throwing = Exception('offline');
      await auth.retrySessionRestore();

      final router = AppRouter(auth).router;
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      // Flush SplashScreen's 2s navigation timer before leaving it, so no
      // pending timer remains when the test ends (same pattern as
      // widget_test.dart).
      await tester.pump(const Duration(seconds: 3));
      router.go('/home');
      await tester.pumpAndSettle();
      expect(find.text('تسجيل الدخول'), findsOneWidget);

      // Connectivity returns.
      auth.throwing = null;
      auth.onFetch = (_) => _profileJson();

      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();

      expect(auth.isAuthenticated, isTrue);
      expect(find.text('مرحباً، سارة'), findsOneWidget);
      expect(find.text('تسجيل الدخول'), findsNothing);
    },
  );
}
