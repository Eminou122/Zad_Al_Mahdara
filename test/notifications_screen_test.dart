import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zad_al_mahdara/core/refresh/app_refresh_coordinator.dart';
import 'package:zad_al_mahdara/core/widgets/zad_bottom_nav.dart';
import 'package:zad_al_mahdara/core/widgets/zad_notification_badge_scope.dart';
import 'package:zad_al_mahdara/core/widgets/zad_swipe_nav.dart';
import 'package:zad_al_mahdara/features/notifications/data/notification_badge_controller.dart';
import 'package:zad_al_mahdara/features/notifications/data/notification_service.dart';
import 'package:zad_al_mahdara/features/notifications/domain/notification_models.dart';
import 'package:zad_al_mahdara/features/notifications/presentation/notifications_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _FakeAuthService extends AuthService {
  @override
  String? get currentToken => 'test-token';
}

NotificationItem _item({
  required String id,
  String type = 'team_turn_today',
  bool isRead = false,
  String? actionType,
  String? teamId,
  Map<String, dynamic>? actionPayload,
  DateTime? createdAt,
}) => NotificationItem(
  id: id,
  type: type,
  title: 'عنوان $id',
  body: 'نص $id',
  teamId: teamId,
  actionType: actionType,
  actionPayload: actionPayload,
  isRead: isRead,
  createdAt: createdAt ?? DateTime(2026, 7, 13, 10),
);

class _FakeNotificationService extends NotificationService {
  List<NotificationItem> firstPageItems = [];
  int unreadCount = 0;
  bool hasMore = false;
  NotificationCursor? nextCursor;

  List<NotificationItem> secondPageItems = [];
  int secondPageUnreadCount = 0;
  bool secondPageHasMore = false;

  Object? getNotificationsError;
  Object? markReadError;

  /// When set, getNotifications() waits on this instead of resolving
  /// immediately — lets a test deterministically observe the loading
  /// state before "data arrives", instead of racing a same-microtask
  /// fake response.
  Completer<NotificationsPage>? gate;

  int getNotificationsCallCount = 0;
  int markReadCallCount = 0;
  int markAllReadCallCount = 0;
  int archiveCallCount = 0;
  String? lastArchivedId;
  String? lastMarkedReadId;
  DateTime? lastBefore;
  String? lastBeforeId;
  final List<List<String>> firstPageCallSnapshots = [];
  final List<Completer<NotificationsPage>> queuedGates = [];

  _FakeNotificationService() : super(AuthService());

  @override
  Future<NotificationsPage> getNotifications({
    int limit = 30,
    DateTime? before,
    String? beforeId,
    bool unreadOnly = false,
  }) async {
    getNotificationsCallCount++;
    lastBefore = before;
    lastBeforeId = beforeId;
    if (getNotificationsError != null) throw getNotificationsError!;
    if (before == null && beforeId == null) {
      firstPageCallSnapshots.add(
        firstPageItems.map((item) => item.id).toList(),
      );
    }
    if (queuedGates.isNotEmpty) {
      return queuedGates.removeAt(0).future;
    }
    if (gate != null) return gate!.future;
    if (before != null || beforeId != null) {
      return NotificationsPage(
        items: secondPageItems,
        unreadCount: secondPageUnreadCount,
        hasMore: secondPageHasMore,
      );
    }
    return NotificationsPage(
      items: firstPageItems,
      unreadCount: unreadCount,
      hasMore: hasMore,
      nextCursor: nextCursor,
    );
  }

  @override
  Future<int> getUnreadCount() async => unreadCount;

  @override
  Future<void> markRead(String notificationId) async {
    markReadCallCount++;
    lastMarkedReadId = notificationId;
    if (markReadError != null) throw markReadError!;
    firstPageItems = [
      for (final item in firstPageItems)
        item.id == notificationId
            ? NotificationItem(
                id: item.id,
                type: item.type,
                title: item.title,
                body: item.body,
                teamId: item.teamId,
                actionType: item.actionType,
                actionPayload: item.actionPayload,
                isRead: true,
                createdAt: item.createdAt,
              )
            : item,
    ];
    unreadCount = firstPageItems.where((item) => !item.isRead).length;
  }

  @override
  Future<void> markAllRead() async {
    markAllReadCallCount++;
    firstPageItems = [
      for (final item in firstPageItems)
        NotificationItem(
          id: item.id,
          type: item.type,
          title: item.title,
          body: item.body,
          teamId: item.teamId,
          actionType: item.actionType,
          actionPayload: item.actionPayload,
          isRead: true,
          createdAt: item.createdAt,
        ),
    ];
    unreadCount = 0;
  }

  @override
  Future<int> deleteNotifications(List<String> notificationIds) async {
    archiveCallCount++;
    lastArchivedId = notificationIds.first;
    firstPageItems = firstPageItems
        .where((item) => !notificationIds.contains(item.id))
        .toList();
    unreadCount = firstPageItems.where((item) => !item.isRead).length;
    return unreadCount;
  }
}

Widget _buildApp({NotificationService? service, AuthService? authService}) {
  final auth = authService ?? _FakeAuthService();
  final svc = service ?? _FakeNotificationService();
  final router = GoRouter(
    initialLocation: '/notifications',
    routes: [
      GoRoute(
        path: '/notifications',
        builder: (_, _) => NotificationsScreen(authService: auth, service: svc),
      ),
      GoRoute(
        path: '/teams/:id',
        builder: (_, state) =>
            Scaffold(body: Text('team-detail-${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/messages/conversation/:id',
        builder: (_, state) =>
            Scaffold(body: Text('conversation-${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/teams/:id/announcements',
        builder: (_, state) =>
            Scaffold(body: Text('announcements-${state.pathParameters['id']}')),
      ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
  );
}

GoRouter _cachedRootRouter({
  required NotificationService service,
  required AuthService authService,
}) {
  const routes = ['/home', '/notifications'];

  Page<void> rootPage(GoRouterState state) {
    final index = routes.indexOf(state.uri.path);
    return NoTransitionPage<void>(
      key: const ValueKey('cached-root-shell'),
      child: ZadSwipeNav(
        routes: routes,
        index: index,
        screenBuilder: (route) => switch (route) {
          '/notifications' => NotificationsScreen(
            authService: authService,
            service: service,
          ),
          _ => const Scaffold(
            body: Center(child: Text('home')),
            bottomNavigationBar: ZadBottomNav(current: ZadTab.home),
          ),
        },
        child: const SizedBox.shrink(),
      ),
    );
  }

  return GoRouter(
    initialLocation: '/notifications',
    routes: [
      GoRoute(path: '/home', pageBuilder: (_, state) => rootPage(state)),
      GoRoute(
        path: '/notifications',
        pageBuilder: (_, state) => rootPage(state),
      ),
    ],
  );
}

Widget _buildCachedRootApp({
  required GoRouter router,
  required NotificationBadgeController badgeController,
}) {
  return ZadNotificationBadgeScope(
    controller: badgeController,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
    ),
  );
}

void main() {
  setUp(AppRefreshCoordinator.instance.resetForTesting);
  tearDown(AppRefreshCoordinator.instance.resetForTesting);

  testWidgets('placeholder wording is gone', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.text('التنبيهات قادمة قريبًا'), findsNothing);
    expect(
      find.text(
        'نعمل على إضافة التنبيهات لمساعدتك في متابعة ميزانيتك وفرقك. '
        'لا حاجة لأي إجراء منك الآن.',
      ),
      findsNothing,
    );
    expect(find.text('الإشعارات'), findsOneWidget);
  });

  testWidgets('loading state shows a spinner before data resolves', (
    tester,
  ) async {
    final svc = _FakeNotificationService()
      ..gate = Completer<NotificationsPage>();
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    svc.gate!.complete(
      const NotificationsPage(items: [], unreadCount: 0, hasMore: false),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('empty state shows icon and Arabic message', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.text('لا توجد إشعارات حالياً'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none_outlined), findsWidgets);
  });

  testWidgets('error state shows retry button and retrying reloads', (
    tester,
  ) async {
    final svc = _FakeNotificationService()
      ..getNotificationsError = Exception('network down');
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    expect(find.text('إعادة المحاولة'), findsOneWidget);

    svc.getNotificationsError = null;
    svc.firstPageItems = [_item(id: 'n1')];
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();

    expect(find.text('إعادة المحاولة'), findsNothing);
    expect(find.text('عنوان n1'), findsOneWidget);
  });

  testWidgets('unread items show a dot, read items do not', (tester) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [
        _item(id: 'unread-1', isRead: false),
        _item(id: 'read-1', isRead: true),
      ];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    // Both titles render; the unread row additionally carries a small
    // gold dot container that the read row does not.
    expect(find.text('عنوان unread-1'), findsOneWidget);
    expect(find.text('عنوان read-1'), findsOneWidget);
  });

  testWidgets('tapping an unread notification marks it read', (tester) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [_item(id: 'n1', isRead: false)];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('عنوان n1'));
    await tester.pumpAndSettle();

    expect(svc.markReadCallCount, 1);
    expect(svc.lastMarkedReadId, 'n1');
  });

  testWidgets('tapping a read notification does not call markRead again', (
    tester,
  ) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [_item(id: 'n1', isRead: true)];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('عنوان n1'));
    await tester.pumpAndSettle();

    expect(svc.markReadCallCount, 0);
  });

  testWidgets('tapping an actionable open_team notification navigates', (
    tester,
  ) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [
        _item(id: 'n1', actionType: 'open_team', teamId: 'team-42'),
      ];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('عنوان n1'));
    await tester.pumpAndSettle();

    expect(find.text('team-detail-team-42'), findsOneWidget);
  });

  testWidgets('open_team_shopping falls back to action_payload.team_id', (
    tester,
  ) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [
        _item(
          id: 'n1',
          actionType: 'open_team_shopping',
          actionPayload: {'team_id': 'team-7'},
        ),
      ];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('عنوان n1'));
    await tester.pumpAndSettle();

    expect(find.text('team-detail-team-7'), findsOneWidget);
  });

  testWidgets('open_team_conversation navigates by conversation id', (
    tester,
  ) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [
        _item(
          id: 'n1',
          actionType: 'open_team_conversation',
          actionPayload: {'team_id': 'team-1', 'conversation_id': 'conv-7'},
        ),
      ];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('عنوان n1'));
    await tester.pumpAndSettle();

    expect(find.text('conversation-conv-7'), findsOneWidget);
    expect(svc.markReadCallCount, 1);
  });

  testWidgets('open_team_announcements navigates by team id', (tester) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [
        _item(
          id: 'n1',
          actionType: 'open_team_announcements',
          actionPayload: {'team_id': 'team-8', 'announcement_id': 'ann-1'},
        ),
      ];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('عنوان n1'));
    await tester.pumpAndSettle();

    expect(find.text('announcements-team-8'), findsOneWidget);
  });

  testWidgets('malformed conversation payload shows friendly snackbar', (
    tester,
  ) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [
        _item(id: 'n1', actionType: 'open_team_conversation'),
      ];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('عنوان n1'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text('تعذر فتح المحادثة المرتبطة بهذا الإشعار'),
      findsOneWidget,
    );
  });

  testWidgets('unknown action_type does not crash and stays put', (
    tester,
  ) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [_item(id: 'n1', actionType: 'something_new')];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('عنوان n1'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('الإشعارات'), findsOneWidget);
  });

  testWidgets('missing team_id shows a friendly snackbar, does not crash', (
    tester,
  ) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [_item(id: 'n1', actionType: 'open_team')];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('عنوان n1'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('تعذر فتح الفريق المرتبط بهذا الإشعار'), findsOneWidget);
  });

  testWidgets('mark all as read is disabled at zero unread', (tester) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [_item(id: 'n1', isRead: true)]
      ..unreadCount = 0;
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.done_all),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('mark all as read marks every item read', (tester) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [
        _item(id: 'n1', isRead: false),
        _item(id: 'n2', isRead: false),
      ]
      ..unreadCount = 2;
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.done_all));
    await tester.pumpAndSettle();

    expect(svc.markAllReadCallCount, 1);
    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.done_all),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('permanent deletion removes a notification after the delay', (
    tester,
  ) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [_item(id: 'n1'), _item(id: 'n2')];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'حذف نهائياً'),
          )
          .onPressed,
      isNull,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.widgetWithText(FilledButton, 'حذف نهائياً'));
    await tester.pumpAndSettle();

    expect(svc.archiveCallCount, 1);
    expect(svc.lastArchivedId, 'n1');
    expect(find.text('عنوان n1'), findsNothing);
    expect(find.text('عنوان n2'), findsOneWidget);
  });

  testWidgets('load more on scroll uses the compound cursor', (tester) async {
    final firstPage = [
      for (var i = 0; i < 20; i++)
        _item(
          id: 'n$i',
          createdAt: DateTime(2026, 7, 13, 10).subtract(Duration(minutes: i)),
        ),
    ];
    final svc = _FakeNotificationService()
      ..firstPageItems = firstPage
      ..hasMore = true
      ..nextCursor = NotificationCursor(
        createdAt: DateTime(
          2026,
          7,
          13,
          10,
        ).subtract(const Duration(minutes: 19)),
        id: 'n19',
      );
    svc.secondPageItems = [_item(id: 'n20')];
    svc.secondPageHasMore = false;

    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    expect(svc.getNotificationsCallCount, 1);

    await tester.fling(find.byType(ListView), const Offset(0, -4000), 4000);
    await tester.pumpAndSettle();

    expect(svc.getNotificationsCallCount, 2);
    expect(svc.lastBefore, svc.nextCursor!.createdAt);
    expect(svc.lastBeforeId, 'n19');
    expect(find.text('عنوان n20'), findsOneWidget);
  });

  testWidgets('no duplicate items appear across pages', (tester) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [
        for (var i = 0; i < 20; i++)
          _item(
            id: 'n$i',
            createdAt: DateTime(2026, 7, 13, 10).subtract(Duration(minutes: i)),
          ),
      ]
      ..hasMore = true
      ..nextCursor = NotificationCursor(
        createdAt: DateTime(
          2026,
          7,
          13,
          10,
        ).subtract(const Duration(minutes: 19)),
        id: 'n19',
      );
    // Second page overlaps deliberately with n19 (already shown) plus a
    // genuinely new row — the screen must drop the overlap defensively.
    svc.secondPageItems = [_item(id: 'n19'), _item(id: 'n20')];
    svc.secondPageHasMore = false;

    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, -4000), 4000);
    await tester.pumpAndSettle();

    expect(find.text('عنوان n19'), findsOneWidget);
    expect(find.text('عنوان n20'), findsOneWidget);
  });

  testWidgets('pull to refresh reloads the first page', (tester) async {
    final svc = _FakeNotificationService()..firstPageItems = [_item(id: 'n1')];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    expect(svc.getNotificationsCallCount, 1);

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(svc.getNotificationsCallCount, greaterThanOrEqualTo(2));
  });

  testWidgets('cached root entry refreshes the existing notifications list', (
    tester,
  ) async {
    final svc = _FakeNotificationService()..firstPageItems = [_item(id: 'old')];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    svc.firstPageItems = [_item(id: 'new'), _item(id: 'old')];
    AppRefreshCoordinator.instance.notifyRootRouteVisible('/notifications');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('عنوان new'), findsOneWidget);
    expect(find.text('عنوان old'), findsOneWidget);
    expect(svc.getNotificationsCallCount, greaterThanOrEqualTo(2));
  });

  testWidgets(
    'badge-first cached root activation fetches and renders the new item',
    (tester) async {
      final auth = _FakeAuthService();
      final svc = _FakeNotificationService();
      final badgeController = NotificationBadgeController(svc);
      final router = _cachedRootRouter(service: svc, authService: auth);
      addTearDown(router.dispose);
      addTearDown(badgeController.dispose);

      await tester.pumpWidget(
        _buildCachedRootApp(router: router, badgeController: badgeController),
      );
      await tester.pumpAndSettle();
      expect(svc.getNotificationsCallCount, 1);

      router.go('/home');
      await tester.pumpAndSettle();
      svc
        ..firstPageItems = [_item(id: 'n1')]
        ..unreadCount = 1;
      badgeController.setCount(1);
      await tester.pump();
      expect(
        AppRefreshCoordinator.instance.isDirty(AppRefreshScope.notifications),
        isTrue,
      );

      await tester.tap(find.text('التنبيهات'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(svc.getNotificationsCallCount, 2);
      expect(svc.firstPageCallSnapshots, [
        <String>[],
        <String>['n1'],
      ]);
      expect(find.text('عنوان n1'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        AppRefreshCoordinator.instance.isDirty(AppRefreshScope.notifications),
        isFalse,
      );
    },
  );

  testWidgets('root swipe activates the same cached notifications screen', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    final svc = _FakeNotificationService();
    final badgeController = NotificationBadgeController(svc);
    final router = _cachedRootRouter(service: svc, authService: auth);
    addTearDown(router.dispose);
    addTearDown(badgeController.dispose);

    await tester.pumpWidget(
      _buildCachedRootApp(router: router, badgeController: badgeController),
    );
    await tester.pumpAndSettle();
    router.go('/home');
    await tester.pumpAndSettle();

    svc
      ..firstPageItems = [_item(id: 'swipe-new')]
      ..unreadCount = 1;
    badgeController.setCount(1);
    await tester.pump();

    await tester.drag(find.byType(ZadSwipeNav), const Offset(300, 0));
    await tester.pumpAndSettle();

    expect(find.text('عنوان swipe-new'), findsOneWidget);
    expect(svc.getNotificationsCallCount, 2);
  });

  testWidgets('refresh requested during an active refresh reruns once', (
    tester,
  ) async {
    final svc = _FakeNotificationService()..firstPageItems = [_item(id: 'old')];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    final first = Completer<NotificationsPage>();
    final second = Completer<NotificationsPage>();
    svc.queuedGates.addAll([first, second]);
    AppRefreshCoordinator.instance.invalidate(AppRefreshScope.notifications);
    await tester.pump();
    AppRefreshCoordinator.instance.invalidate(AppRefreshScope.notifications);
    await tester.pump();

    expect(svc.getNotificationsCallCount, 2);
    first.complete(
      NotificationsPage(
        items: [_item(id: 'old')],
        unreadCount: 0,
        hasMore: false,
      ),
    );
    await tester.pump();
    expect(svc.getNotificationsCallCount, 3);

    second.complete(
      NotificationsPage(
        items: [
          _item(id: 'new'),
          _item(id: 'old'),
        ],
        unreadCount: 1,
        hasMore: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('عنوان new'), findsOneWidget);
    expect(find.text('عنوان old'), findsOneWidget);
    expect(svc.getNotificationsCallCount, 3);
  });

  testWidgets('failed activation stays dirty and re-entry retries', (
    tester,
  ) async {
    final svc = _FakeNotificationService()..firstPageItems = [_item(id: 'old')];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    svc.getNotificationsError = Exception('network down');
    AppRefreshCoordinator.instance.notifyRootRouteVisible('/notifications');
    await tester.pumpAndSettle();

    expect(
      AppRefreshCoordinator.instance.isDirty(AppRefreshScope.notifications),
      isTrue,
    );
    expect(find.text('عنوان old'), findsOneWidget);

    svc
      ..getNotificationsError = null
      ..firstPageItems = [_item(id: 'new'), _item(id: 'old')];
    AppRefreshCoordinator.instance.notifyRootRouteVisible('/notifications');
    await tester.pumpAndSettle();

    expect(find.text('عنوان new'), findsOneWidget);
    expect(
      AppRefreshCoordinator.instance.isDirty(AppRefreshScope.notifications),
      isFalse,
    );
  });

  testWidgets('already-selected notifications tab refreshes immediately', (
    tester,
  ) async {
    final svc = _FakeNotificationService()..firstPageItems = [_item(id: 'old')];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    svc.firstPageItems = [_item(id: 'new'), _item(id: 'old')];
    await tester.tap(find.text('التنبيهات'));
    await tester.pumpAndSettle();

    expect(find.text('عنوان new'), findsOneWidget);
    expect(svc.getNotificationsCallCount, 2);
  });

  testWidgets(
    'polling stops in background and resumes without removing cards',
    (tester) async {
      final svc = _FakeNotificationService()
        ..firstPageItems = [_item(id: 'old')];
      await tester.pumpWidget(_buildApp(service: svc));
      await tester.pumpAndSettle();

      AppRefreshCoordinator.instance.notifyAppBackgrounded();
      await tester.pump();
      final callsWhileForeground = svc.getNotificationsCallCount;
      svc.firstPageItems = [_item(id: 'new'), _item(id: 'old')];
      await tester.pump(const Duration(seconds: 20));

      expect(svc.getNotificationsCallCount, callsWhileForeground);
      expect(find.text('عنوان new'), findsNothing);

      AppRefreshCoordinator.instance.notifyAppResumed();
      await tester.pump();
      await tester.pump();

      expect(find.text('عنوان new'), findsOneWidget);
      expect(find.text('عنوان old'), findsOneWidget);
    },
  );

  testWidgets('silent refresh failure preserves existing notifications', (
    tester,
  ) async {
    final svc = _FakeNotificationService()..firstPageItems = [_item(id: 'old')];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    svc.getNotificationsError = Exception('network down');
    AppRefreshCoordinator.instance.invalidate(AppRefreshScope.notifications);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('عنوان old'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsNothing);
  });

  testWidgets('first-page refresh deduplicates notification IDs', (
    tester,
  ) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [_item(id: 'n1'), _item(id: 'n1')];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    expect(find.text('عنوان n1'), findsOneWidget);
  });

  testWidgets('renders at 320px without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final svc = _FakeNotificationService()
      ..firstPageItems = [
        _item(id: 'n1'),
        _item(id: 'n2', isRead: true, type: 'shopping_report_rejected'),
      ]
      ..unreadCount = 1;
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
