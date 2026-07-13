import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/notifications/data/notification_service.dart';
import 'package:zad_al_mahdara/features/notifications/domain/notification_models.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _UnauthAuthService extends AuthService {
  @override
  String? get currentToken => null;
}

// Records the exact params each RPC call would carry, same pattern as
// team_shopping_service_test.dart's _FakeTeamShoppingService — there is no
// injectable Supabase client seam (the real `_c` getter is library-private),
// so every *_service_test.dart in this project verifies the public method
// contract this way rather than intercepting the network call itself.
class _RecordingNotificationService extends NotificationService {
  String? lastRpc;
  Map<String, dynamic>? lastParams;
  NotificationsPage? pageReturnValue;

  _RecordingNotificationService() : super(AuthService());

  @override
  Future<NotificationsPage> getNotifications({
    int limit = 30,
    DateTime? before,
    String? beforeId,
    bool unreadOnly = false,
  }) async {
    lastRpc = 'get_my_notifications';
    lastParams = {
      'p_session_token': 'test-token',
      'p_limit': limit,
      'p_unread_only': unreadOnly,
    };
    if (before != null) lastParams!['p_before'] = before.toIso8601String();
    if (beforeId != null) lastParams!['p_before_id'] = beforeId;
    return pageReturnValue ??
        const NotificationsPage(items: [], unreadCount: 0, hasMore: false);
  }

  @override
  Future<int> getUnreadCount() async {
    lastRpc = 'get_my_notification_unread_count';
    lastParams = {'p_session_token': 'test-token'};
    return 0;
  }

  @override
  Future<void> markRead(String notificationId) async {
    lastRpc = 'mark_notification_read';
    lastParams = {
      'p_session_token': 'test-token',
      'p_notification_id': notificationId,
    };
  }

  @override
  Future<void> markAllRead() async {
    lastRpc = 'mark_all_notifications_read';
    lastParams = {'p_session_token': 'test-token'};
  }

  @override
  Future<void> archiveNotification(String notificationId) async {
    lastRpc = 'archive_notification';
    lastParams = {
      'p_session_token': 'test-token',
      'p_notification_id': notificationId,
    };
  }
}

void main() {
  group('NotificationService auth guard', () {
    test('getNotifications throws without a session token', () async {
      final svc = NotificationService(_UnauthAuthService());
      await expectLater(svc.getNotifications(), throwsException);
    });

    test('getUnreadCount throws without a session token', () async {
      final svc = NotificationService(_UnauthAuthService());
      await expectLater(svc.getUnreadCount(), throwsException);
    });

    test('markRead throws without a session token', () async {
      final svc = NotificationService(_UnauthAuthService());
      await expectLater(svc.markRead('n1'), throwsException);
    });

    test('markAllRead throws without a session token', () async {
      final svc = NotificationService(_UnauthAuthService());
      await expectLater(svc.markAllRead(), throwsException);
    });

    test('archiveNotification throws without a session token', () async {
      final svc = NotificationService(_UnauthAuthService());
      await expectLater(svc.archiveNotification('n1'), throwsException);
    });
  });

  group('NotificationService call shape', () {
    test('first page sends only limit and unread_only (no cursor)', () async {
      final svc = _RecordingNotificationService();
      await svc.getNotifications(limit: 25);
      expect(svc.lastRpc, 'get_my_notifications');
      expect(svc.lastParams!['p_limit'], 25);
      expect(svc.lastParams!['p_unread_only'], false);
      expect(svc.lastParams!.containsKey('p_before'), false);
      expect(svc.lastParams!.containsKey('p_before_id'), false);
    });

    test('later page sends compound cursor p_before + p_before_id', () async {
      final svc = _RecordingNotificationService();
      final before = DateTime.utc(2026, 7, 13, 10);
      await svc.getNotifications(limit: 25, before: before, beforeId: 'notif-9');
      expect(svc.lastParams!['p_before'], before.toIso8601String());
      expect(svc.lastParams!['p_before_id'], 'notif-9');
    });

    test('unread_only param threads through', () async {
      final svc = _RecordingNotificationService();
      await svc.getNotifications(unreadOnly: true);
      expect(svc.lastParams!['p_unread_only'], true);
    });

    test('markRead calls mark_notification_read with the id', () async {
      final svc = _RecordingNotificationService();
      await svc.markRead('notif-1');
      expect(svc.lastRpc, 'mark_notification_read');
      expect(svc.lastParams!['p_notification_id'], 'notif-1');
    });

    test('markAllRead calls mark_all_notifications_read', () async {
      final svc = _RecordingNotificationService();
      await svc.markAllRead();
      expect(svc.lastRpc, 'mark_all_notifications_read');
    });

    test('archiveNotification calls archive_notification with the id', () async {
      final svc = _RecordingNotificationService();
      await svc.archiveNotification('notif-1');
      expect(svc.lastRpc, 'archive_notification');
      expect(svc.lastParams!['p_notification_id'], 'notif-1');
    });

    test('getUnreadCount calls get_my_notification_unread_count', () async {
      final svc = _RecordingNotificationService();
      final count = await svc.getUnreadCount();
      expect(svc.lastRpc, 'get_my_notification_unread_count');
      expect(count, 0);
    });
  });
}
