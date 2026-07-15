import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zad_al_mahdara/core/widgets/zad_bottom_nav.dart';
import 'package:zad_al_mahdara/core/widgets/zad_messaging_badge_scope.dart';
import 'package:zad_al_mahdara/core/widgets/zad_session_scope.dart';
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

class _AdminAuthService extends AuthService {
  @override
  bool get isAdmin => true;
}

Widget _wrapNav({required bool isAdmin}) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: ZadSessionScope(
      authService: isAdmin ? _AdminAuthService() : AuthService(),
      child: const Scaffold(
        bottomNavigationBar: ZadBottomNav(current: ZadTab.home),
      ),
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

  group('ZadBottomNav visual order (Gate 52.3)', () {
    // In RTL, the first-declared item lands at the right edge, so a
    // decreasing x from one label to the next means "further left" —
    // i.e. exactly the requested right→left reading order.
    void expectRightToLeft(WidgetTester tester, List<String> labels) {
      final xs = [for (final l in labels) tester.getTopLeft(find.text(l)).dx];
      for (var i = 0; i < xs.length - 1; i++) {
        expect(
          xs[i],
          greaterThan(xs[i + 1]),
          reason:
              '"${labels[i]}" should sit to the right of "${labels[i + 1]}"',
        );
      }
    }

    testWidgets('normal-user visual order right→left: '
        'الرئيسية، الميزانية، الفرق، الرسائل، التنبيهات', (tester) async {
      await tester.pumpWidget(_wrapNav(isAdmin: false));
      await tester.pump();

      expectRightToLeft(tester, [
        'الرئيسية',
        'الميزانية',
        'الفرق',
        'الرسائل',
        'التنبيهات',
      ]);
      expect(find.text('لوحة الإدارة'), findsNothing);
    });

    testWidgets('admin visual order right→left: '
        'الرئيسية، الميزانية، الفرق، الرسائل، التنبيهات، لوحة الإدارة', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapNav(isAdmin: true));
      await tester.pump();

      expectRightToLeft(tester, [
        'الرئيسية',
        'الميزانية',
        'الفرق',
        'الرسائل',
        'التنبيهات',
        'لوحة الإدارة',
      ]);
    });

    testWidgets('admin six-tab layout has no overflow at 320px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrapNav(isAdmin: true));
      await tester.pump();

      expect(tester.takeException(), isNull);
      for (final label in [
        'الرئيسية',
        'الميزانية',
        'الفرق',
        'الرسائل',
        'التنبيهات',
        'لوحة الإدارة',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('tapping each admin item navigates to its own route', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          for (final path in ZadBottomNav.routesFor(true))
            GoRoute(
              path: path,
              builder: (_, _) => Directionality(
                textDirection: TextDirection.rtl,
                child: ZadSessionScope(
                  authService: _AdminAuthService(),
                  child: Scaffold(
                    body: Center(child: Text('SCREEN:$path')),
                    bottomNavigationBar: ZadBottomNav(
                      current: ZadBottomNav.forLocation(path)?.current,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      for (final entry in const {
        'الميزانية': '/budget',
        'الفرق': '/teams',
        'الرسائل': '/messages',
        'التنبيهات': '/notifications',
        'لوحة الإدارة': '/admin',
      }.entries) {
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(find.text('SCREEN:${entry.value}'), findsOneWidget);
      }
    });
  });
}
