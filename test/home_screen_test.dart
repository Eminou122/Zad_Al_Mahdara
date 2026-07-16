import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zad_al_mahdara/features/home/presentation/home_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _Auth extends AuthService {
  @override
  bool get isLoadingSession => false;

  @override
  bool get isAuthenticated => true;

  @override
  String get displayName => 'أحمد';

  @override
  String? get currentToken => 'token-1';
}

Widget _wrap() {
  final auth = _Auth();
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => HomeScreen(authService: auth),
      ),
      GoRoute(
        path: '/directory',
        builder: (_, _) => const Scaffold(body: Text('دليل الطلاب route')),
      ),
      GoRoute(
        path: '/account',
        builder: (_, _) => const Scaffold(body: Text('account')),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  testWidgets('Home shows directory shortcut and navigates', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.text('دليل الطلاب'), findsOneWidget);
    expect(find.text('تصفح الطلاب والفرق العامة'), findsOneWidget);
    await tester.tap(find.text('دليل الطلاب'));
    await tester.pumpAndSettle();

    expect(find.text('دليل الطلاب route'), findsOneWidget);
  });
}
