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
