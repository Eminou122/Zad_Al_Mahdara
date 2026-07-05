import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zad_al_mahdara/core/widgets/zad_bottom_nav.dart';
import 'package:zad_al_mahdara/core/widgets/zad_nested_swipe_scope.dart';
import 'package:zad_al_mahdara/core/widgets/zad_swipe_nav.dart';
import 'package:zad_al_mahdara/features/teams/data/team_service.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_models.dart';
import 'package:zad_al_mahdara/features/teams/presentation/teams_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

/// Minimal GoRouter so ZadSwipeNav can call context.go() without crashing.
/// Routes: /home (page 0) and /teams (page 1), both via ZadSwipeNav.
/// The [firstChild] is placed on /home so the drag target is /teams.
GoRouter _testRouter(Widget firstChild) {
  final routes = ['/home', '/teams'];
  return GoRouter(
    initialLocation: '/home',
    routes: [
      for (final path in routes)
        GoRoute(
          path: path,
          pageBuilder: (_, state) {
            final index = routes.indexOf(path);
            return CustomTransitionPage<void>(
              key: ValueKey(path),
              child: ZadSwipeNav(
                routes: routes,
                index: index,
                child: index == 0 ? firstChild : const Placeholder(),
              ),
              transitionsBuilder: (_, animation, _, child) =>
                  FadeTransition(opacity: animation, child: child),
            );
          },
        ),
    ],
  );
}

Offset _childGlobalOffset(GlobalKey key) {
  final box = key.currentContext!.findRenderObject() as RenderBox;
  return box.localToGlobal(Offset.zero);
}

Widget _buildSwipeNav({GlobalKey? childKey}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: ZadSwipeNav(
          routes: const ['/home', '/teams'],
          index: 0,
          child: SizedBox.expand(
            key: childKey,
            child: const Center(child: Text('content')),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ZadBottomNav.routesFor', () {
    test('normal user gets the 4 non-admin routes, no /admin', () {
      final routes = ZadBottomNav.routesFor(false);
      expect(routes, ['/home', '/budget', '/teams', '/notifications']);
      expect(routes, isNot(contains('/admin')));
    });

    test('admin user gets 5 routes including /admin', () {
      final routes = ZadBottomNav.routesFor(true);
      expect(
        routes,
        ['/budget', '/teams', '/home', '/notifications', '/admin'],
      );
      expect(routes, contains('/admin'));
      expect(routes.length, 5);
    });
  });

  group('ZadBottomNav.isRootTab (main-tab route detection)', () {
    test('main sections are root tabs', () {
      for (final loc in [
        '/home',
        '/budget',
        '/teams',
        '/notifications',
        '/admin',
      ]) {
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
    final routes = ZadBottomNav.routesFor(false);

    test('commit distance is max(90px, 22% of screen width)', () {
      expect(ZadSwipeNav.commitDistance(320), 90); // floor wins on tiny phones
      expect(ZadSwipeNav.commitDistance(800), closeTo(176, 0.001));
    });

    test('swipe right (positive signal) moves to next index', () {
      final target = ZadSwipeNav.targetIndex(
        index: 0,
        dragDistance: 200,
        velocity: 0,
        routesLength: routes.length,
        screenWidth: 800,
      );
      expect(target, 1);
    });

    test('swipe left (negative signal) moves to previous index', () {
      final target = ZadSwipeNav.targetIndex(
        index: 1,
        dragDistance: -200,
        velocity: 0,
        routesLength: routes.length,
        screenWidth: 800,
      );
      expect(target, 0);
    });

    test('fast flick under distance threshold still counts via velocity', () {
      final target = ZadSwipeNav.targetIndex(
        index: 0,
        dragDistance: 10,
        velocity: 1000,
        routesLength: routes.length,
        screenWidth: 800,
      );
      expect(target, 1);
    });

    test('drag past the old 60px threshold but below the deliberate '
        'commit distance is now ignored', () {
      final target = ZadSwipeNav.targetIndex(
        index: 0,
        dragDistance: 100, // < max(90, 800*0.22) = 176
        velocity: 0,
        routesLength: routes.length,
        screenWidth: 800,
      );
      expect(target, isNull);
    });

    test('small accidental drag below both thresholds is ignored', () {
      final target = ZadSwipeNav.targetIndex(
        index: 1,
        dragDistance: 5,
        velocity: 20,
        routesLength: routes.length,
        screenWidth: 800,
      );
      expect(target, isNull);
    });

    test('swiping past the last tab is a no-op', () {
      final target = ZadSwipeNav.targetIndex(
        index: routes.length - 1,
        dragDistance: 200,
        velocity: 0,
        routesLength: routes.length,
        screenWidth: 800,
      );
      expect(target, isNull);
    });

    test('swiping past the first tab is a no-op', () {
      final target = ZadSwipeNav.targetIndex(
        index: 0,
        dragDistance: -200,
        velocity: 0,
        routesLength: routes.length,
        screenWidth: 800,
      );
      expect(target, isNull);
    });
  });

  group('PageControllerRegistration notification', () {
    testWidgets('bubbles up through NotificationListener', (tester) async {
      PageController? received;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationListener<PageControllerRegistration>(
            onNotification: (n) {
              received = n.controller;
              return true;
            },
            child: _NotificationDispatcher(),
          ),
        ),
      );
      await tester.pump();
      expect(received, isNotNull);
    });
  });

  group('ZadSwipeNav widget', () {
    testWidgets('does not crash at 320px width', (tester) async {
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

    testWidgets('with unknown index just renders child (no wrapper)', (
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

    testWidgets('registers child PageController via notification', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: ZadSwipeNav(
              routes: const ['/home', '/teams'],
              index: 1,
              child: _PageViewChild(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Page 0 "فرقي" is visible by default
      expect(find.text('فرقي'), findsOneWidget);
    });

    testWidgets('internal PageView animateToPage switches content', (
      tester,
    ) async {
      final pc = PageController();
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: PageView(
              controller: pc,
              children: [
                const Center(child: Text('فرقي')),
                const Center(child: Text('الفرق العامة')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('فرقي'), findsOneWidget);

      pc.animateToPage(1,
          duration: const Duration(milliseconds: 100), curve: Curves.linear);
      await tester.pumpAndSettle();

      expect(find.text('الفرق العامة'), findsOneWidget);
    });

    testWidgets('GoRouter context.go does not crash with ZadSwipeNav', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: _testRouter(const Text('الصفحة الرئيسية'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('الصفحة الرئيسية'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ZadSwipeNav axis lock', () {
    testWidgets('vertical drag does not move the page', (tester) async {
      final childKey = GlobalKey();
      await tester.pumpWidget(_buildSwipeNav(childKey: childKey));
      await tester.pump();

      final initialPos = _childGlobalOffset(childKey);

      // Vertical scroll down: dx=2, dy=200
      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveTo(const Offset(202, 400));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(_childGlobalOffset(childKey), equals(initialPos));
    });

    testWidgets('diagonal vertical drag does not move the page', (tester) async {
      final childKey = GlobalKey();
      await tester.pumpWidget(_buildSwipeNav(childKey: childKey));
      await tester.pump();

      final initialPos = _childGlobalOffset(childKey);

      // Diagonal down-right: dx=30, dy=80 (dy >= dx*1.1)
      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveTo(const Offset(230, 280));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(_childGlobalOffset(childKey), equals(initialPos));
    });

    testWidgets('horizontal drag moves the page', (tester) async {
      final childKey = GlobalKey();
      await tester.pumpWidget(_buildSwipeNav(childKey: childKey));
      await tester.pump();

      final initialPos = _childGlobalOffset(childKey);

      // Horizontal: dx=30, dy=0 (above 24px lock, below commit distance)
      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveTo(const Offset(230, 200));
      await tester.pump();

      final pos = _childGlobalOffset(childKey);
      expect(pos.dx, greaterThan(initialPos.dx + 20));
    });

    testWidgets('horizontal drag releases and returns to origin', (tester) async {
      final childKey = GlobalKey();
      await tester.pumpWidget(_buildSwipeNav(childKey: childKey));
      await tester.pump();

      final initialPos = _childGlobalOffset(childKey);

      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveTo(const Offset(230, 200));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // After release + animation, should be back at origin
      expect(_childGlobalOffset(childKey), equals(initialPos));
    });

    testWidgets('small horizontal jitter during vertical scroll is ignored', (
      tester,
    ) async {
      final childKey = GlobalKey();
      await tester.pumpWidget(_buildSwipeNav(childKey: childKey));
      await tester.pump();

      final initialPos = _childGlobalOffset(childKey);

      // Simulate vertical scroll with slight jitter: 5 consecutive moves
      final gesture = await tester.startGesture(const Offset(200, 600));
      await gesture.moveTo(const Offset(201, 500)); // dx=1, dy=-100
      await tester.pump();
      await gesture.moveTo(const Offset(202, 400)); // dx=1, dy=-100
      await tester.pump();
      await gesture.moveTo(const Offset(201, 300)); // dx=-1, dy=-100
      await tester.pump();
      await gesture.moveTo(const Offset(203, 200)); // dx=2, dy=-100
      await tester.pump();
      await gesture.moveTo(const Offset(202, 100)); // dx=-1, dy=-100
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // Total: dx=2, dy=-500 → vertical lock on first move
      expect(_childGlobalOffset(childKey), equals(initialPos));
    });

    testWidgets('neighbor preview does not appear during vertical drag', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSwipeNav());
      await tester.pump();

      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveTo(const Offset(202, 400)); // dx=2, dy=200
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(
        find.text('الفرق'),
        findsNothing,
        reason: 'neighbor preview must not appear during vertical drag',
      );
    });

    testWidgets('neighbor preview appears during horizontal drag', (tester) async {
      await tester.pumpWidget(_buildSwipeNav());
      await tester.pump();

      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveTo(const Offset(250, 200)); // dx=50, dy=0
      await tester.pump();

      // From index 0 (/home) in routes ['/home', '/teams'] → '/teams' = 'الفرق'
      expect(find.text('الفرق'), findsOneWidget);
    });

    testWidgets('ambiguous small diagonal drag does not move the page', (
      tester,
    ) async {
      final childKey = GlobalKey();
      await tester.pumpWidget(_buildSwipeNav(childKey: childKey));
      await tester.pump();

      final initialPos = _childGlobalOffset(childKey);

      // dx=15, dy=10: neither vertical lock (dy < 12) nor horizontal lock
      // (dx < 24) → gesture stays undecided, root must not move.
      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveTo(const Offset(215, 210));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(_childGlobalOffset(childKey), equals(initialPos));
    });

    testWidgets('small horizontal movement below the 24px lock does not move '
        'the page', (tester) async {
      final childKey = GlobalKey();
      await tester.pumpWidget(_buildSwipeNav(childKey: childKey));
      await tester.pump();

      final initialPos = _childGlobalOffset(childKey);

      // dx=15, dy=0: purely horizontal but below the deliberate 24px lock.
      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveTo(const Offset(215, 200));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(_childGlobalOffset(childKey), equals(initialPos));
    });

    testWidgets('fast horizontal flick under commit distance navigates via '
        'velocity', (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: _testRouter(const Text('الصفحة الرئيسية')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('الصفحة الرئيسية'), findsOneWidget);

      // Fast flick: dx=80 → velocity=80/0.12≈667 px/s (≥500)
      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveTo(const Offset(280, 200));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Should have navigated to /teams (index 1) → Placeholder appears
      expect(find.byType(Placeholder), findsOneWidget);
      expect(find.text('الصفحة الرئيسية'), findsNothing);
    });

    testWidgets('fast vertical flick with tiny horizontal jitter does NOT navigate', (
      tester,
    ) async {
      final childKey = GlobalKey();
      await tester.pumpWidget(_buildSwipeNav(childKey: childKey));
      await tester.pump();

      final initialPos = _childGlobalOffset(childKey);

      // Fast vertical flick: dx=3, dy=-150 → vertical-dominant on first move
      final gesture = await tester.startGesture(const Offset(200, 500));
      await gesture.moveTo(const Offset(203, 350));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // First move is vertical-dominant → rejected → page did not move
      expect(_childGlobalOffset(childKey), equals(initialPos));
    });
  });

  group('ZadSwipeNav nested boundary defer (Teams-style child PageView)', () {
    /// Router with two root tabs; /teams (index 1) embeds a real nested
    /// PageView (like Teams' فرقي/الفرق العامة) that starts on [teamsPage].
    GoRouter buildRouter(int teamsPage) {
      final routes = ['/home', '/teams'];
      return GoRouter(
        initialLocation: '/teams',
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (_, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              child: ZadSwipeNav(
                routes: routes,
                index: 0,
                child: const Center(child: Text('HOME_PAGE')),
              ),
              transitionsBuilder: (_, animation, _, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
          GoRoute(
            path: '/teams',
            pageBuilder: (_, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              child: ZadSwipeNav(
                routes: routes,
                index: 1,
                child: _PageViewChild(initialPage: teamsPage),
              ),
              transitionsBuilder: (_, animation, _, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
        ],
      );
    }

    testWidgets(
      'Teams internal swipe moves its own page first and root does not navigate',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp.router(routerConfig: buildRouter(0)),
        );
        await tester.pumpAndSettle();
        expect(find.text('فرقي'), findsOneWidget);

        // Child (page 0) has room to move forward (dx>0) → root defers.
        final gesture = await tester.startGesture(const Offset(700, 300));
        await gesture.moveBy(const Offset(500, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        // Teams' own internal page moved to "الفرق العامة"...
        expect(find.text('الفرق العامة'), findsOneWidget);
        // ...and root never navigated away from /teams.
        expect(find.text('HOME_PAGE'), findsNothing);
      },
    );

    testWidgets(
      'root navigates when Teams internal PageView is already at that boundary',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp.router(routerConfig: buildRouter(0)),
        );
        await tester.pumpAndSettle();
        expect(find.text('فرقي'), findsOneWidget);

        // Child is on page 0 (first page) — no room backward (dx<0) →
        // root owns the gesture and navigates to the previous root tab.
        final gesture = await tester.startGesture(const Offset(700, 300));
        await gesture.moveBy(const Offset(-500, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.text('HOME_PAGE'), findsOneWidget);
      },
    );

    testWidgets(
      'vertical scroll inside a Teams-like child does not move root',
      (tester) async {
        final childKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: const MediaQueryData(size: Size(800, 600)),
                child: ZadSwipeNav(
                  routes: const ['/home', '/teams'],
                  index: 1,
                  child: SizedBox(
                    key: childKey,
                    width: 800,
                    height: 600,
                    child: _PageViewChild(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final initialPos = _childGlobalOffset(childKey);
        final gesture = await tester.startGesture(const Offset(400, 200));
        await gesture.moveTo(const Offset(402, 400)); // dx=2, dy=200
        await tester.pump();
        await gesture.up();
        await tester.pump();

        expect(_childGlobalOffset(childKey), equals(initialPos));
      },
    );
  });

  group('ZadSwipeNav.screenBuilder (real gallery-style neighbor)', () {
    testWidgets(
      'renders the real neighbor screen during drag, not the icon placeholder',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: const MediaQueryData(size: Size(800, 600)),
                child: ZadSwipeNav(
                  routes: const ['/home', '/budget', '/teams', '/notifications'],
                  index: 0,
                  screenBuilder: (route) => Text('SCREEN:$route'),
                  child: const SizedBox.expand(
                    child: Center(child: Text('content')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final gesture = await tester.startGesture(const Offset(200, 200));
        await gesture.moveTo(const Offset(250, 200)); // dx=50 → next = /budget
        await tester.pump();

        expect(find.text('SCREEN:/budget'), findsOneWidget);
        // The icon+label placeholder (48px centered icon) must be gone.
        // ('الميزانية' itself may legitimately appear in the stable
        // bottom-nav overlay, so check for the placeholder icon instead.)
        expect(
          tester
              .widgetList<Icon>(find.byType(Icon))
              .where((i) => i.size == 48),
          isEmpty,
        );
      },
    );
  });

  group('ZadSwipeNav filmstrip offset (Gate 29.8)', () {
    Offset globalPosOf(GlobalKey key) =>
        (key.currentContext!.findRenderObject() as RenderBox)
            .localToGlobal(Offset.zero);

    testWidgets(
      'neighbor is offset like a real filmstrip on a partial positive drag, not pinned at Offset.zero',
      (tester) async {
        final neighborKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: const MediaQueryData(size: Size(800, 600)),
                child: ZadSwipeNav(
                  routes: const ['/home', '/budget', '/teams', '/notifications'],
                  index: 0,
                  screenBuilder: (route) => route == '/budget'
                      ? SizedBox(key: neighborKey, width: 800, height: 600)
                      : const SizedBox(width: 800, height: 600),
                  child: const SizedBox.expand(
                    child: Center(child: Text('content')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final gesture = await tester.startGesture(const Offset(400, 300));
        await gesture.moveBy(const Offset(200, 0)); // dragOffset ~200
        await tester.pump();

        // Expected: dragOffset - screenWidth = 200 - 800 = -600.
        expect(globalPosOf(neighborKey).dx, closeTo(-600, 0.5));
        expect(globalPosOf(neighborKey), isNot(Offset.zero));
      },
    );

    testWidgets(
      'neighbor is offset like a real filmstrip on a partial negative drag',
      (tester) async {
        final neighborKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: const MediaQueryData(size: Size(800, 600)),
                child: ZadSwipeNav(
                  routes: const ['/home', '/budget', '/teams', '/notifications'],
                  index: 1,
                  screenBuilder: (route) => route == '/home'
                      ? SizedBox(key: neighborKey, width: 800, height: 600)
                      : const SizedBox(width: 800, height: 600),
                  child: const SizedBox.expand(
                    child: Center(child: Text('content')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final gesture = await tester.startGesture(const Offset(400, 300));
        await gesture.moveBy(const Offset(-200, 0)); // dragOffset ~-200
        await tester.pump();

        // Expected: dragOffset + screenWidth = -200 + 800 = 600.
        expect(globalPosOf(neighborKey).dx, closeTo(600, 0.5));
        expect(globalPosOf(neighborKey), isNot(Offset.zero));
      },
    );

    testWidgets(
      'cancel keeps the neighbor mounted throughout the snap-back animation',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: const MediaQueryData(size: Size(800, 600)),
                child: ZadSwipeNav(
                  routes: const ['/home', '/budget', '/teams', '/notifications'],
                  index: 0,
                  screenBuilder: (route) => Text('SCREEN:$route'),
                  child: const SizedBox.expand(
                    child: Center(child: Text('content')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Below the commit distance and velocity → will cancel/snap back.
        final gesture = await tester.startGesture(const Offset(400, 300));
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
        expect(find.text('SCREEN:/budget'), findsOneWidget);

        await gesture.up();
        // Mid-animation frame (settle duration is 250ms): neighbor must
        // still be mounted, not removed at the first frame of snap-back.
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('SCREEN:/budget'), findsOneWidget);

        // Once the snap-back finishes, dragOffset is back to 0 and the
        // neighbor is gone.
        await tester.pumpAndSettle();
        expect(find.text('SCREEN:/budget'), findsNothing);
      },
    );

    testWidgets(
      'commit finishes the filmstrip slide before calling context.go',
      (tester) async {
        final routes = ['/home', '/budget'];
        final router = GoRouter(
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              pageBuilder: (_, state) => CustomTransitionPage<void>(
                key: state.pageKey,
                child: ZadSwipeNav(
                  routes: routes,
                  index: 0,
                  // The shell renders the current tab from this builder too.
                  screenBuilder: (r) =>
                      Text(r == '/home' ? 'HOME_PAGE' : 'SCREEN:$r'),
                  child: const Center(child: Text('HOME_PAGE')),
                ),
                transitionsBuilder: (_, animation, _, child) =>
                    FadeTransition(opacity: animation, child: child),
              ),
            ),
            GoRoute(
              path: '/budget',
              pageBuilder: (_, state) => CustomTransitionPage<void>(
                key: state.pageKey,
                child: ZadSwipeNav(
                  routes: routes,
                  index: 1,
                  child: const Center(child: Text('BUDGET_PAGE')),
                ),
                transitionsBuilder: (_, animation, _, child) =>
                    FadeTransition(opacity: animation, child: child),
              ),
            ),
          ],
        );

        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        expect(find.text('HOME_PAGE'), findsOneWidget);

        // 100px in one frame → horizontal-dominant flick well above the
        // 500 px/s velocity threshold.
        final gesture = await tester.startGesture(const Offset(400, 300));
        await gesture.moveBy(const Offset(100, 0));
        await tester.pump();
        await gesture.up();

        // Immediately after release: still mid-slide, must NOT have
        // navigated yet (settle duration is 250ms).
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.text('HOME_PAGE'), findsOneWidget);
        expect(find.text('BUDGET_PAGE'), findsNothing);

        // Once the filmstrip finishes sliding, navigation has happened.
        await tester.pumpAndSettle();
        expect(find.text('BUDGET_PAGE'), findsOneWidget);
      },
    );
  });

  group('ZadSwipeNav stable bottom nav + seamless commit (Gate 29.10)', () {
    testWidgets(
      'stable bottom-nav overlay stays fixed while the filmstrip slides',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: const MediaQueryData(size: Size(800, 600)),
                child: ZadSwipeNav(
                  routes: const ['/home', '/budget', '/teams', '/notifications'],
                  index: 0,
                  screenBuilder: (route) => Text('SCREEN:$route'),
                  child: const SizedBox.expand(
                    child: Center(child: Text('content')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // No overlay at rest.
        expect(find.byType(ZadBottomNav), findsNothing);

        final gesture = await tester.startGesture(const Offset(400, 300));
        await gesture.moveBy(const Offset(120, 0));
        await tester.pump();

        // Overlay present during drag and horizontally fixed (x == 0)
        // even though the pages are offset by 120.
        expect(find.byType(ZadBottomNav), findsOneWidget);
        final navBox =
            tester.renderObject(find.byType(ZadBottomNav)) as RenderBox;
        expect(navBox.localToGlobal(Offset.zero).dx, 0);

        await gesture.moveBy(const Offset(100, 0));
        await tester.pump();
        expect(navBox.localToGlobal(Offset.zero).dx, 0);
      },
    );

    testWidgets(
      'committed swipe passes swipeCommitExtra so the router can skip its transition',
      (tester) async {
        Object? receivedExtra;
        final routes = ['/home', '/budget'];
        final router = GoRouter(
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              pageBuilder: (_, state) => CustomTransitionPage<void>(
                key: state.pageKey,
                child: ZadSwipeNav(
                  routes: routes,
                  index: 0,
                  child: const Center(child: Text('HOME_PAGE')),
                ),
                transitionsBuilder: (_, animation, _, child) =>
                    FadeTransition(opacity: animation, child: child),
              ),
            ),
            GoRoute(
              path: '/budget',
              pageBuilder: (_, state) {
                receivedExtra = state.extra;
                return CustomTransitionPage<void>(
                  key: state.pageKey,
                  child: const Center(child: Text('BUDGET_PAGE')),
                  transitionsBuilder: (_, animation, _, child) =>
                      FadeTransition(opacity: animation, child: child),
                );
              },
            ),
          ],
        );

        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(const Offset(400, 300));
        await gesture.moveBy(const Offset(100, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.text('BUDGET_PAGE'), findsOneWidget);
        expect(receivedExtra, ZadSwipeNav.swipeCommitExtra);
      },
    );

    testWidgets(
      'commit drives the neighbor to x ≈ 0 before navigating',
      (tester) async {
        final neighborKey = GlobalKey();
        var navigated = false;
        final routes = ['/home', '/budget'];
        final router = GoRouter(
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              pageBuilder: (_, state) => CustomTransitionPage<void>(
                key: state.pageKey,
                child: ZadSwipeNav(
                  routes: routes,
                  index: 0,
                  screenBuilder: (r) => r == '/budget'
                      ? SizedBox(key: neighborKey, width: 800, height: 600)
                      : const SizedBox(width: 800, height: 600),
                  child: const Center(child: Text('HOME_PAGE')),
                ),
                transitionsBuilder: (_, animation, _, child) =>
                    FadeTransition(opacity: animation, child: child),
              ),
            ),
            GoRoute(
              path: '/budget',
              pageBuilder: (_, state) {
                navigated = true;
                return CustomTransitionPage<void>(
                  key: state.pageKey,
                  child: const Center(child: Text('BUDGET_PAGE')),
                  transitionsBuilder: (_, animation, _, child) =>
                      FadeTransition(opacity: animation, child: child),
                );
              },
            ),
          ],
        );

        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(const Offset(400, 300));
        await gesture.moveBy(const Offset(100, 0));
        await tester.pump();
        await gesture.up();
        await tester.pump(); // first frame starts the settle ticker (t = 0)

        // 240ms into the 250ms settle: neighbor nearly at x = 0
        // (linear controller: expected ≈ -28), navigation not yet fired.
        await tester.pump(const Duration(milliseconds: 240));
        final navBox = neighborKey.currentContext!.findRenderObject()
            as RenderBox;
        expect(navBox.localToGlobal(Offset.zero).dx.abs(), lessThan(60));
        expect(navigated, isFalse);

        await tester.pumpAndSettle();
        expect(navigated, isTrue);
        expect(find.text('BUDGET_PAGE'), findsOneWidget);
      },
    );

    testWidgets(
      'browser-style route change (router.go) shows the new section',
      (tester) async {
        final router = _testRouter(const Text('الصفحة الرئيسية'));
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        expect(find.text('الصفحة الرئيسية'), findsOneWidget);

        router.go('/teams');
        await tester.pumpAndSettle();

        expect(find.byType(Placeholder), findsOneWidget);
        expect(find.text('الصفحة الرئيسية'), findsNothing);
      },
    );
  });

  group('ZadSwipeNav edge clamp (Gate 29.12)', () {
    Widget buildAt({
      required List<String> routes,
      required int index,
      GlobalKey? childKey,
    }) {
      return MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(800, 600)),
            child: ZadSwipeNav(
              routes: routes,
              index: index,
              child: SizedBox.expand(
                key: childKey,
                child: const Center(child: Text('content')),
              ),
            ),
          ),
        ),
      );
    }

    const userRoutes = ['/home', '/budget', '/teams', '/notifications'];
    const adminRoutes = ['/budget', '/teams', '/home', '/notifications', '/admin'];

    testWidgets('at the first route, outward drag does not move the page and '
        'shows no neighbor', (tester) async {
      final childKey = GlobalKey();
      await tester.pumpWidget(
        buildAt(routes: userRoutes, index: 0, childKey: childKey),
      );
      await tester.pump();
      final initialPos = _childGlobalOffset(childKey);

      // Negative drag at index 0 points at index -1 → no neighbor.
      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(-200, 0));
      await tester.pump();

      expect(_childGlobalOffset(childKey), equals(initialPos));
      // No fake neighbor placeholder (48px centered icon) either.
      expect(
        tester.widgetList<Icon>(find.byType(Icon)).where((i) => i.size == 48),
        isEmpty,
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_childGlobalOffset(childKey), equals(initialPos));
    });

    testWidgets('at the last route, outward drag does not move the page and '
        'shows no neighbor', (tester) async {
      final childKey = GlobalKey();
      await tester.pumpWidget(
        buildAt(
          routes: userRoutes,
          index: userRoutes.length - 1,
          childKey: childKey,
        ),
      );
      await tester.pump();
      final initialPos = _childGlobalOffset(childKey);

      // Positive drag at the last index points past the end → no neighbor.
      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();

      expect(_childGlobalOffset(childKey), equals(initialPos));
      expect(
        tester.widgetList<Icon>(find.byType(Icon)).where((i) => i.size == 48),
        isEmpty,
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_childGlobalOffset(childKey), equals(initialPos));
    });

    testWidgets('valid inward drag still works from the first and last route',
        (tester) async {
      final childKey = GlobalKey();

      // First route, inward (positive → index 1).
      await tester.pumpWidget(
        buildAt(routes: userRoutes, index: 0, childKey: childKey),
      );
      await tester.pump();
      var initialPos = _childGlobalOffset(childKey);
      var gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(_childGlobalOffset(childKey).dx, greaterThan(initialPos.dx + 100));
      // Cancel instead of releasing: a 200px one-frame drag would commit,
      // and there is no GoRouter in this harness.
      await gesture.cancel();
      await tester.pumpAndSettle();

      // Last route, inward (negative → index length-2).
      await tester.pumpWidget(
        buildAt(
          routes: userRoutes,
          index: userRoutes.length - 1,
          childKey: childKey,
        ),
      );
      await tester.pump();
      initialPos = _childGlobalOffset(childKey);
      gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(-200, 0));
      await tester.pump();
      expect(_childGlobalOffset(childKey).dx, lessThan(initialPos.dx - 100));
      await gesture.cancel();
      await tester.pumpAndSettle();
    });

    testWidgets('admin 5-route strip clamps at both ends too', (tester) async {
      final childKey = GlobalKey();

      // Last admin route (index 4), outward.
      await tester.pumpWidget(
        buildAt(routes: adminRoutes, index: 4, childKey: childKey),
      );
      await tester.pump();
      var initialPos = _childGlobalOffset(childKey);
      var gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(_childGlobalOffset(childKey), equals(initialPos));
      await gesture.up();
      await tester.pumpAndSettle();

      // Same position, inward is allowed. Cancel (not up): a 200px
      // one-frame drag would commit and there is no GoRouter here.
      gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(-200, 0));
      await tester.pump();
      expect(_childGlobalOffset(childKey).dx, lessThan(initialPos.dx - 100));
      await gesture.cancel();
      await tester.pumpAndSettle();

      // First admin route (index 0), outward.
      await tester.pumpWidget(
        buildAt(routes: adminRoutes, index: 0, childKey: childKey),
      );
      await tester.pump();
      initialPos = _childGlobalOffset(childKey);
      gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(-200, 0));
      await tester.pump();
      expect(_childGlobalOffset(childKey), equals(initialPos));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('outward flick at the boundary does not navigate', (
      tester,
    ) async {
      // /home is index 0 in _testRouter's ['/home', '/teams'].
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: _testRouter(const Text('الصفحة الرئيسية')),
        ),
      );
      await tester.pumpAndSettle();

      // Fast outward flick (negative at index 0).
      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(-200, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('الصفحة الرئيسية'), findsOneWidget);
      expect(find.byType(Placeholder), findsNothing);
    });
  });

  group('ZadSwipeNav persistent shell — no re-fetch (Gate 29.12)', () {
    setUp(_ProbeScreen.reset);

    testWidgets('screenBuilder builds each route once across repeated drags '
        'and never rebuilds the cached current section', (tester) async {
      final calls = <String, int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(800, 600)),
              child: ZadSwipeNav(
                routes: const ['/home', '/budget', '/teams', '/notifications'],
                index: 0,
                screenBuilder: (r) {
                  calls[r] = (calls[r] ?? 0) + 1;
                  return _ProbeScreen(r);
                },
                child: const SizedBox(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(calls, {'/home': 1});

      // Partial drag below both commit thresholds (35px total, ≈292 px/s
      // even with the test harness's zero-delta timestamps) → snaps back,
      // no navigation attempted.
      Future<void> slowCancelledDrag() async {
        final gesture = await tester.startGesture(const Offset(400, 300));
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(5, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await slowCancelledDrag();
      expect(calls, {'/home': 1, '/budget': 1});

      // Second drag toward the same neighbor: nothing is built again and
      // nothing is re-mounted (no initState → no re-fetch).
      await slowCancelledDrag();
      expect(calls, {'/home': 1, '/budget': 1});
      expect(_ProbeScreen.mounts, {'/home': 1, '/budget': 1});
      // The cached current section is not even rebuilt by the drag frames.
      expect(_ProbeScreen.builds['/home'], 1);
    });

    testWidgets('committed swipe keeps both sections mounted exactly once', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final router = _shellRouter(const ['/home', '/budget']);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('LIVE:/home'), findsOneWidget);

      // Deliberate commit: 200px ≥ commit distance (176 at 800px width).
      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('LIVE:/budget'), findsOneWidget);
      // Neither section was mounted twice: the neighbor previewed during
      // the drag IS the arriving section (no second initState/fetch), and
      // the departing section stays alive offstage.
      expect(_ProbeScreen.mounts, {'/home': 1, '/budget': 1});
      expect(find.text('LIVE:/home', skipOffstage: false), findsOneWidget);
    });

    testWidgets('router.go tab changes (bottom-nav style) keep cached tabs '
        'alive and sync the visible section', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final router = _shellRouter(const ['/home', '/budget']);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.go('/budget');
      await tester.pumpAndSettle();
      expect(find.text('LIVE:/budget'), findsOneWidget);

      router.go('/home');
      await tester.pumpAndSettle();
      expect(find.text('LIVE:/home'), findsOneWidget);

      // Round trip re-mounted nothing.
      expect(_ProbeScreen.mounts, {'/home': 1, '/budget': 1});
    });
  });

  group('ZadSwipeNav shell + Teams boundary clamp (Gate 29.12)', () {
    testWidgets('at the last root route, an outward drag at the Teams '
        'internal boundary moves nothing and never builds a fake neighbor', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final routes = ['/home', '/teams'];
      final router = GoRouter(
        initialLocation: '/teams',
        routes: [
          for (final path in routes)
            GoRoute(
              path: path,
              pageBuilder: (_, state) => CustomTransitionPage<void>(
                key: const ValueKey('zad-root-shell-test'),
                child: ZadSwipeNav(
                  routes: routes,
                  index: routes.indexOf(path),
                  screenBuilder: (r) => r == '/teams'
                      ? const _PageViewChild(initialPage: 1)
                      : const Center(child: Text('HOME_SCREEN')),
                  child: const SizedBox(),
                ),
                transitionsBuilder: (_, animation, _, child) =>
                    FadeTransition(opacity: animation, child: child),
              ),
            ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      // Teams internal PageView starts at its last page.
      expect(find.text('الفرق العامة'), findsOneWidget);
      final initialPos = tester.getTopLeft(find.text('الفرق العامة'));

      // Positive drag: Teams has no further internal page AND root has no
      // higher route → clamped, nothing moves, no neighbor is built.
      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      // Root must not move. A couple of px of drift is the Teams
      // PageView's own Material 3 stretch-overscroll, not a root swipe.
      expect(
        (tester.getTopLeft(find.text('الفرق العامة')).dx - initialPos.dx).abs(),
        lessThan(8),
      );
      expect(find.text('HOME_SCREEN', skipOffstage: false), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('الفرق العامة'), findsOneWidget);

      // Inward drag still belongs to the Teams PageView first.
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('فرقي'), findsOneWidget);
    });
  });

  group('TeamsScreen real-widget behavior', () {
    testWidgets('FAB appears only on "فرقي" and segmented control switches',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: TeamsScreen(
              authService: AuthService(),
              service: _FakeTeamService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Page 0 "فرقي": team visible, FAB present.
      expect(find.text('فريق الغداء'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Tap "الفرق العامة" segment → page 1, FAB gone, empty state.
      await tester.tap(find.text('الفرق العامة'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('لا توجد فرق عامة'), findsOneWidget);

      // Tap back to "فرقي" → FAB returns.
      await tester.tap(find.text('فرقي'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('internal swipe changes the Teams page first', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: TeamsScreen(
              authService: AuthService(),
              service: _FakeTeamService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Positive dx (drag right) → higher page index in this RTL app.
      // 500px (past halfway on the 800px surface) so the settle direction
      // is unambiguous.
      await tester.drag(find.byType(PageView), const Offset(500, 0));
      await tester.pumpAndSettle();

      // Now on "الفرق العامة": FAB gone, public empty state shown.
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('لا توجد فرق عامة'), findsOneWidget);
    });
  });

  group('ZadBottomNav navigation', () {
    testWidgets('tapping a tab navigates to its route', (tester) async {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(
              body: Center(child: Text('HOME')),
              bottomNavigationBar: ZadBottomNav(current: ZadTab.home),
            ),
          ),
          GoRoute(
            path: '/budget',
            builder: (_, _) => const Scaffold(
              body: Center(child: Text('BUDGET')),
              bottomNavigationBar: ZadBottomNav(current: ZadTab.budget),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);

      await tester.tap(find.text('الميزانية'));
      await tester.pumpAndSettle();

      expect(find.text('BUDGET'), findsOneWidget);
    });
  });
}

/// Root-tab probe: counts mounts (initState) and builds per route, so tests
/// can prove the persistent shell never re-mounts (→ never re-fetches) and
/// never needlessly rebuilds a cached section.
class _ProbeScreen extends StatefulWidget {
  final String route;
  const _ProbeScreen(this.route);

  static final mounts = <String, int>{};
  static final builds = <String, int>{};
  static void reset() {
    mounts.clear();
    builds.clear();
  }

  @override
  State<_ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<_ProbeScreen> {
  @override
  void initState() {
    super.initState();
    _ProbeScreen.mounts.update(widget.route, (v) => v + 1, ifAbsent: () => 1);
  }

  @override
  Widget build(BuildContext context) {
    _ProbeScreen.builds.update(widget.route, (v) => v + 1, ifAbsent: () => 1);
    return Center(child: Text('LIVE:${widget.route}'));
  }
}

/// Mimics AppRouter._mainPage: every root route shares ONE page key, so
/// switching tabs updates the page in place and the ZadSwipeNav shell (and
/// its cached screens) survives the change.
GoRouter _shellRouter(List<String> routes) {
  return GoRouter(
    initialLocation: routes.first,
    routes: [
      for (final path in routes)
        GoRoute(
          path: path,
          pageBuilder: (_, state) => CustomTransitionPage<void>(
            key: const ValueKey('zad-root-shell-test'),
            child: ZadSwipeNav(
              routes: routes,
              index: routes.indexOf(path),
              screenBuilder: (r) => _ProbeScreen(r),
              child: const SizedBox(),
            ),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        ),
    ],
  );
}

/// Dispatches [PageControllerRegistration] after the first frame.
class _NotificationDispatcher extends StatefulWidget {
  @override
  State<_NotificationDispatcher> createState() =>
      _NotificationDispatcherState();
}

class _NotificationDispatcherState extends State<_NotificationDispatcher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PageControllerRegistration(PageController()).dispatch(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// A widget that wraps a two-page PageView inside a
/// [PageControllerRegistration]-dispatching shell.
class _PageViewChild extends StatefulWidget {
  final int initialPage;
  const _PageViewChild({this.initialPage = 0});

  @override
  State<_PageViewChild> createState() => _PageViewChildState();
}

class _PageViewChildState extends State<_PageViewChild> {
  late final _pc = PageController(initialPage: widget.initialPage);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PageControllerRegistration(_pc).dispatch(context);
      }
    });
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PageView(
        controller: _pc,
        children: [
          const Center(child: Text('فرقي')),
          const Center(child: Text('الفرق العامة')),
        ],
      ),
    );
  }
}

/// In-memory TeamService: one team on "فرقي", none on "الفرق العامة".
class _FakeTeamService extends TeamService {
  _FakeTeamService() : super(AuthService());

  @override
  Future<List<TeamSummary>> getMyTeams() async => const [
        TeamSummary(
          id: 't1',
          name: 'فريق الغداء',
          teamType: 'lunch',
          isPublic: false,
          status: 'open',
          leaderName: 'قائد',
          memberCount: 3,
          activeMemberCount: 3,
          inactiveMemberCount: 0,
          myRole: 'leader',
          isLeader: true,
        ),
      ];

  @override
  Future<List<TeamSummary>> getPublicTeams() async => const [];
}
