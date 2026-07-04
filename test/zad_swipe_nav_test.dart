import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zad_al_mahdara/core/widgets/zad_bottom_nav.dart';
import 'package:zad_al_mahdara/core/widgets/zad_nested_swipe_scope.dart';
import 'package:zad_al_mahdara/core/widgets/zad_swipe_nav.dart';

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
      child: ZadSwipeNav(
        routes: const ['/home', '/teams'],
        index: 0,
        child: SizedBox(
          key: childKey,
          width: 400,
          height: 800,
          child: const Text('content'),
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

      // Horizontal: dx=30, dy=0 (above 18px lock, below 60px nav threshold)
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

      // From index 0 (/home) with 4 routes, allRoutes[1] = /budget → 'الميزانية'
      expect(find.text('الميزانية'), findsOneWidget);
    });
  });
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
  @override
  State<_PageViewChild> createState() => _PageViewChildState();
}

class _PageViewChildState extends State<_PageViewChild> {
  final _pc = PageController();

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
