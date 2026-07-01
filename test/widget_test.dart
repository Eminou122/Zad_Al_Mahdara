import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/app.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

void main() {
  testWidgets('app smoke test — renders without crashing', (tester) async {
    // AuthService with no Supabase URL is inert (returns early from constructor)
    await tester.pumpWidget(ZadApp(authService: AuthService()));
    // Advance past SplashScreen's 2-second timer so no pending timers remain
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
