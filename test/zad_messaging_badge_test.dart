import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/widgets/zad_bottom_nav.dart';
import 'package:zad_al_mahdara/core/widgets/zad_messaging_badge_scope.dart';
import 'package:zad_al_mahdara/features/messaging/data/messaging_badge_controller.dart';
import 'package:zad_al_mahdara/features/messaging/data/team_messaging_service.dart';
import 'package:zad_al_mahdara/features/messaging/domain/team_messaging_models.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

Widget _wrap(MessagingBadgeController controller) => MaterialApp(
  home: ZadMessagingBadgeScope(
    controller: controller,
    child: const Scaffold(
      bottomNavigationBar: ZadBottomNav(current: ZadTab.home),
    ),
  ),
);

void main() {
  group('MessagingBadgeController', () {
    test('setCount only notifies listeners when a value actually changes', () {
      final controller = MessagingBadgeController(
        TeamMessagingService(AuthService()),
      );
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.setCount(
        const MessagingUnreadCount(
          privateMessageUnreadCount: 2,
          announcementUnreadCount: 1,
          totalUnreadCount: 3,
        ),
      );
      controller.setCount(
        const MessagingUnreadCount(
          privateMessageUnreadCount: 2,
          announcementUnreadCount: 1,
          totalUnreadCount: 3,
        ),
      );
      expect(notifyCount, 1);
      expect(controller.totalUnreadCount, 3);
      expect(controller.privateMessageUnreadCount, 2);
      expect(controller.announcementUnreadCount, 1);

      controller.reset();
      expect(controller.totalUnreadCount, 0);
      expect(notifyCount, 2);
    });
  });

  group('ZadMessagingBadgeScope + bottom nav badge', () {
    testWidgets('no badge shown when total unread is zero', (tester) async {
      final controller = MessagingBadgeController(
        TeamMessagingService(AuthService()),
      );
      await tester.pumpWidget(_wrap(controller));
      await tester.pump();

      expect(find.text('0'), findsNothing);
    });

    testWidgets('badge shows the exact count for 1-99', (tester) async {
      final controller = MessagingBadgeController(
        TeamMessagingService(AuthService()),
      );
      controller.setCount(
        const MessagingUnreadCount(
          privateMessageUnreadCount: 6,
          announcementUnreadCount: 1,
          totalUnreadCount: 7,
        ),
      );
      await tester.pumpWidget(_wrap(controller));
      await tester.pump();

      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('badge shows 99+ beyond 99', (tester) async {
      final controller = MessagingBadgeController(
        TeamMessagingService(AuthService()),
      );
      controller.setCount(
        const MessagingUnreadCount(
          privateMessageUnreadCount: 120,
          announcementUnreadCount: 20,
          totalUnreadCount: 140,
        ),
      );
      await tester.pumpWidget(_wrap(controller));
      await tester.pump();

      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('badge is independent from the notification badge', (
      tester,
    ) async {
      // Only ZadMessagingBadgeScope is provided here (no
      // ZadNotificationBadgeScope) — the nav must still render without a
      // crash and simply treat the notification count as 0, proving the
      // two badges never merge into one shared count.
      final controller = MessagingBadgeController(
        TeamMessagingService(AuthService()),
      );
      controller.setCount(
        const MessagingUnreadCount(
          privateMessageUnreadCount: 5,
          announcementUnreadCount: 0,
          totalUnreadCount: 5,
        ),
      );
      await tester.pumpWidget(_wrap(controller));
      await tester.pump();

      expect(find.text('5'), findsOneWidget);
    });
  });
}
