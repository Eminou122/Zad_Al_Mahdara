import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/widgets/zad_bottom_nav.dart';
import 'package:zad_al_mahdara/core/widgets/zad_swipe_nav.dart';

void main() {
  group('ZadBottomNav.routesFor', () {
    test('normal user gets the 4 non-admin routes, no /admin', () {
      final routes = ZadBottomNav.routesFor(false);
      expect(routes, ['/home', '/budget', '/teams', '/notifications']);
      expect(routes, isNot(contains('/admin')));
    });

    test('admin user gets 5 routes including /admin', () {
      final routes = ZadBottomNav.routesFor(true);
      expect(routes, ['/budget', '/teams', '/home', '/notifications', '/admin']);
      expect(routes, contains('/admin'));
      expect(routes.length, 5);
    });
  });

  group('ZadBottomNav.isRootTab (main-tab route detection)', () {
    test('main sections are root tabs', () {
      for (final loc in ['/home', '/budget', '/teams', '/notifications', '/admin']) {
        expect(ZadBottomNav.isRootTab(loc), isTrue, reason: loc);
      }
    });

    test('detail/form routes are not root tabs (no swipe wrapper)', () {
      for (final loc in [
        '/budget/setup',
        '/budget/expense/new',
        '/budget/subscription/new',
        '/budget/recurring',
        '/budget/recurring/new',
        '/teams/new',
        '/teams/abc-123',
        '/teams/abc-123/add-member',
        '/login',
        '/register',
        '/forgot-pin',
      ]) {
        expect(ZadBottomNav.isRootTab(loc), isFalse, reason: loc);
      }
    });
  });

  group('ZadSwipeNavState.targetIndex (swipe next/previous logic)', () {
    final routes = ZadBottomNav.routesFor(false); // 4 routes, indices 0..3

    test('swipe right (positive signal) moves to next index', () {
      final target = ZadSwipeNav.targetIndex(
        index: 0,
        dragDistance: 100,
        velocity: 0,
        routesLength: routes.length,
      );
      expect(target, 1);
    });

    test('swipe left (negative signal) moves to previous index', () {
      final target = ZadSwipeNav.targetIndex(
        index: 1,
        dragDistance: -100,
        velocity: 0,
        routesLength: routes.length,
      );
      expect(target, 0);
    });

    test('fast flick under distance threshold still counts via velocity', () {
      final target = ZadSwipeNav.targetIndex(
        index: 0,
        dragDistance: 10,
        velocity: 1000,
        routesLength: routes.length,
      );
      expect(target, 1);
    });

    test('small accidental drag below both thresholds is ignored', () {
      final target = ZadSwipeNav.targetIndex(
        index: 1,
        dragDistance: 5,
        velocity: 20,
        routesLength: routes.length,
      );
      expect(target, isNull);
    });

    test('swiping past the last tab is a no-op', () {
      final target = ZadSwipeNav.targetIndex(
        index: routes.length - 1,
        dragDistance: 100,
        velocity: 0,
        routesLength: routes.length,
      );
      expect(target, isNull);
    });

    test('swiping past the first tab is a no-op', () {
      final target = ZadSwipeNav.targetIndex(
        index: 0,
        dragDistance: -100,
        velocity: 0,
        routesLength: routes.length,
      );
      expect(target, isNull);
    });
  });

  testWidgets('ZadSwipeNav does not crash at 320px width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ZadSwipeNav(
            routes: const ['/home', '/budget', '/teams', '/notifications'],
            index: 0,
            child: const Scaffold(body: Center(child: Text('محتوى'))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('محتوى'), findsOneWidget);
  });

  testWidgets('ZadSwipeNav with unknown index just renders child (no wrapper)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ZadSwipeNav(
          routes: const ['/home', '/budget'],
          index: -1,
          child: const Text('plain'),
        ),
      ),
    );
    expect(find.text('plain'), findsOneWidget);
  });
}
