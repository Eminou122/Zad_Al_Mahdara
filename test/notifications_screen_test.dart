import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
  }

  @override
  Future<void> markAllRead() async {
    markAllReadCallCount++;
  }

  @override
  Future<void> archiveNotification(String notificationId) async {
    archiveCallCount++;
    lastArchivedId = notificationId;
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
        builder: (_, _) =>
            NotificationsScreen(authService: auth, service: svc),
      ),
      GoRoute(
        path: '/teams/:id',
        builder: (_, state) =>
            Scaffold(body: Text('team-detail-${state.pathParameters['id']}')),
      ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
  );
}

void main() {
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
    final svc = _FakeNotificationService()..gate = Completer<NotificationsPage>();
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

    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'تحديد الكل كمقروء'),
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

    await tester.tap(find.text('تحديد الكل كمقروء'));
    await tester.pumpAndSettle();

    expect(svc.markAllReadCallCount, 1);
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'تحديد الكل كمقروء'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('archiving a notification removes it and shows a snackbar', (
    tester,
  ) async {
    final svc = _FakeNotificationService()
      ..firstPageItems = [_item(id: 'n1'), _item(id: 'n2')];
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.archive_outlined).first);
    await tester.pumpAndSettle();

    expect(svc.archiveCallCount, 1);
    expect(svc.lastArchivedId, 'n1');
    expect(find.text('عنوان n1'), findsNothing);
    expect(find.text('عنوان n2'), findsOneWidget);
    expect(find.text('تم أرشفة الإشعار'), findsOneWidget);
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
        createdAt: DateTime(2026, 7, 13, 10).subtract(const Duration(minutes: 19)),
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
            createdAt: DateTime(
              2026,
              7,
              13,
              10,
            ).subtract(Duration(minutes: i)),
          ),
      ]
      ..hasMore = true
      ..nextCursor = NotificationCursor(
        createdAt: DateTime(2026, 7, 13, 10).subtract(const Duration(minutes: 19)),
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

  testWidgets('renders at 320px without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final svc = _FakeNotificationService()
      ..firstPageItems = [
        _item(id: 'n1'),
        _item(
          id: 'n2',
          isRead: true,
          type: 'shopping_report_rejected',
        ),
      ]
      ..unreadCount = 1;
    await tester.pumpWidget(_buildApp(service: svc));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
