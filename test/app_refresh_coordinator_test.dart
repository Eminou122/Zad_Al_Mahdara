import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/refresh/app_refresh_coordinator.dart';
import 'package:zad_al_mahdara/core/widgets/zad_bottom_nav.dart';
import 'package:zad_al_mahdara/core/widgets/zad_swipe_nav.dart';

Future<void> _flushCoordinator() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(AppRefreshCoordinator.instance.resetForTesting);
  tearDown(AppRefreshCoordinator.instance.resetForTesting);

  test('scope listener receives matching invalidation', () async {
    var calls = 0;
    AppRefreshCoordinator.instance.subscribe(
      AppRefreshScope.notifications,
      (_) => calls++,
    );

    AppRefreshCoordinator.instance.invalidate(AppRefreshScope.notifications);
    await _flushCoordinator();

    expect(calls, 1);
  });

  test('unrelated scope listener is not called', () async {
    var calls = 0;
    AppRefreshCoordinator.instance.subscribe(
      AppRefreshScope.messages,
      (_) => calls++,
    );

    AppRefreshCoordinator.instance.invalidate(AppRefreshScope.notifications);
    await _flushCoordinator();

    expect(calls, 0);
  });

  test('multiple scopes can be invalidated together', () async {
    var notifications = 0;
    var badge = 0;
    AppRefreshCoordinator.instance.subscribe(
      AppRefreshScope.notifications,
      (_) => notifications++,
    );
    AppRefreshCoordinator.instance.subscribe(
      AppRefreshScope.notificationBadge,
      (_) => badge++,
    );

    AppRefreshCoordinator.instance.invalidateMany({
      AppRefreshScope.notifications,
      AppRefreshScope.notificationBadge,
    });
    await _flushCoordinator();

    expect(notifications, 1);
    expect(badge, 1);
  });

  test('disposed listener is not called', () async {
    var calls = 0;
    final unsubscribe = AppRefreshCoordinator.instance.subscribe(
      AppRefreshScope.messages,
      (_) => calls++,
    );
    unsubscribe();

    AppRefreshCoordinator.instance.invalidate(AppRefreshScope.messages);
    await _flushCoordinator();

    expect(calls, 0);
  });

  test('rapid duplicate events are coalesced', () async {
    var calls = 0;
    AppRefreshCoordinator.instance.subscribe(
      AppRefreshScope.notifications,
      (_) => calls++,
    );

    AppRefreshCoordinator.instance
      ..invalidate(AppRefreshScope.notifications)
      ..invalidate(AppRefreshScope.notifications)
      ..invalidate(AppRefreshScope.notifications);
    await _flushCoordinator();

    expect(calls, 1);
  });

  test('dirty scope remains dirty until synchronization succeeds', () async {
    AppRefreshCoordinator.instance.markDirty(
      AppRefreshScope.notifications,
      notify: false,
    );

    expect(
      AppRefreshCoordinator.instance.isDirty(AppRefreshScope.notifications),
      isTrue,
    );

    AppRefreshCoordinator.instance.markSynchronized(
      AppRefreshScope.notifications,
    );

    expect(
      AppRefreshCoordinator.instance.isDirty(AppRefreshScope.notifications),
      isFalse,
    );
  });

  test('root route is authoritative before listeners flush', () async {
    AppRefreshCoordinator.instance.notifyRootRouteVisible('/notifications');

    expect(AppRefreshCoordinator.instance.currentRootRoute, '/notifications');
    await _flushCoordinator();
  });

  test('app resume emits notification and message scopes', () async {
    final seen = <AppRefreshScope>[];
    final foreground = <bool>[];
    for (final scope in AppRefreshScope.values) {
      AppRefreshCoordinator.instance.subscribe(scope, seen.add);
    }
    AppRefreshCoordinator.instance.subscribeAppForeground(foreground.add);

    AppRefreshCoordinator.instance.notifyAppBackgrounded();
    await _flushCoordinator();
    AppRefreshCoordinator.instance.notifyAppResumed();
    await _flushCoordinator();

    expect(foreground, [false, true]);
    expect(
      seen.toSet(),
      containsAll({
        AppRefreshScope.notifications,
        AppRefreshScope.notificationBadge,
        AppRefreshScope.messages,
        AppRefreshScope.messagingBadge,
        AppRefreshScope.announcements,
      }),
    );
  });

  test('root route visibility emits correct scopes', () async {
    final seen = <AppRefreshScope>[];
    final routes = <String>[];
    for (final scope in AppRefreshScope.values) {
      AppRefreshCoordinator.instance.subscribe(scope, seen.add);
    }
    AppRefreshCoordinator.instance.subscribeRootRouteVisible(routes.add);

    AppRefreshCoordinator.instance.notifyRootRouteVisible('/messages');
    await _flushCoordinator();

    expect(routes, ['/messages']);
    expect(
      seen.toSet(),
      containsAll({
        AppRefreshScope.messages,
        AppRefreshScope.messagingBadge,
        AppRefreshScope.announcements,
      }),
    );
    expect(seen, isNot(contains(AppRefreshScope.notifications)));
  });

  testWidgets('active bottom-nav tap emits root visibility', (tester) async {
    final routes = <String>[];
    AppRefreshCoordinator.instance.subscribeRootRouteVisible(routes.add);

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            bottomNavigationBar: ZadBottomNav(current: ZadTab.notifications),
          ),
        ),
      ),
    );
    await tester.tap(find.text('التنبيهات'));
    await tester.pump();

    expect(routes, ['/notifications']);
  });

  testWidgets('swipe shell route update emits root visibility', (tester) async {
    final routes = <String>[];
    AppRefreshCoordinator.instance.subscribeRootRouteVisible(routes.add);

    Widget build(int index) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ZadSwipeNav(
          routes: const ['/messages', '/notifications'],
          index: index,
          child: Text('route-$index'),
        ),
      ),
    );

    await tester.pumpWidget(build(0));
    await tester.pump();
    await tester.pumpWidget(build(1));
    await tester.pump();

    expect(routes, contains('/messages'));
    expect(routes, contains('/notifications'));
  });
}
