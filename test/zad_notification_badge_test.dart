import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/widgets/zad_bottom_nav.dart';
import 'package:zad_al_mahdara/core/widgets/zad_notification_badge_scope.dart';
import 'package:zad_al_mahdara/features/notifications/data/notification_badge_controller.dart';
import 'package:zad_al_mahdara/features/notifications/data/notification_service.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

Widget _wrap(NotificationBadgeController controller) => MaterialApp(
  home: ZadNotificationBadgeScope(
    controller: controller,
    child: const Scaffold(
      bottomNavigationBar: ZadBottomNav(current: ZadTab.home),
    ),
  ),
);

void main() {
  testWidgets('no badge shown when unread count is zero', (tester) async {
    final controller = NotificationBadgeController(
      NotificationService(AuthService()),
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    expect(find.text('0'), findsNothing);
  });

  testWidgets('badge shows the exact count for 1-99', (tester) async {
    final controller = NotificationBadgeController(
      NotificationService(AuthService()),
    );
    controller.setCount(7);
    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('badge shows 99+ beyond 99', (tester) async {
    final controller = NotificationBadgeController(
      NotificationService(AuthService()),
    );
    controller.setCount(140);
    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('badge updates live when the controller changes', (tester) async {
    final controller = NotificationBadgeController(
      NotificationService(AuthService()),
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pump();
    expect(find.text('3'), findsNothing);

    controller.setCount(3);
    await tester.pump();
    expect(find.text('3'), findsOneWidget);

    controller.setCount(0);
    await tester.pump();
    expect(find.text('3'), findsNothing);
  });

  test('setCount only notifies listeners when the value actually changes', () {
    final controller = NotificationBadgeController(
      NotificationService(AuthService()),
    );
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    controller.setCount(5);
    controller.setCount(5);
    expect(notifyCount, 1);

    controller.reset();
    expect(controller.unreadCount, 0);
    expect(notifyCount, 2);
  });
}
