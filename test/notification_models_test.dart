import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/notifications/domain/notification_models.dart';

void main() {
  group('NotificationItem.fromJson', () {
    test('parses all fields', () {
      final item = NotificationItem.fromJson({
        'id': 'notif-1',
        'type': 'team_turn_today',
        'title': 'دورك اليوم',
        'body': 'دورك اليوم في فريق الغداء',
        'team_id': 'team-1',
        'turn_id': 'turn-1',
        'shopping_report_id': 'report-1',
        'action_type': 'open_team',
        'action_payload': {'team_id': 'team-1'},
        'is_read': false,
        'read_at': null,
        'created_at': '2026-07-13T10:00:00.000Z',
      });

      expect(item.id, 'notif-1');
      expect(item.type, 'team_turn_today');
      expect(item.title, 'دورك اليوم');
      expect(item.body, 'دورك اليوم في فريق الغداء');
      expect(item.teamId, 'team-1');
      expect(item.turnId, 'turn-1');
      expect(item.shoppingReportId, 'report-1');
      expect(item.actionType, 'open_team');
      expect(item.actionPayload, {'team_id': 'team-1'});
      expect(item.isRead, false);
      expect(item.readAt, isNull);
      expect(item.createdAt, DateTime.parse('2026-07-13T10:00:00.000Z'));
      expect(item.isUnread, true);
      expect(item.hasAction, true);
    });

    test('parses nullable action fields (no team/turn/report/action)', () {
      final item = NotificationItem.fromJson({
        'id': 'notif-2',
        'type': 'shopping_report_accepted',
        'title': 'تم القبول',
        'body': 'body',
        'is_read': true,
        'read_at': '2026-07-13T11:00:00.000Z',
        'created_at': '2026-07-13T10:00:00.000Z',
      });

      expect(item.teamId, isNull);
      expect(item.turnId, isNull);
      expect(item.shoppingReportId, isNull);
      expect(item.actionType, isNull);
      expect(item.actionPayload, isNull);
      expect(item.hasAction, false);
      expect(item.isUnread, false);
    });

    test('unknown type does not fail and is preserved as-is', () {
      final item = NotificationItem.fromJson({
        'id': 'notif-3',
        'type': 'something_never_seen_before',
        'title': 't',
        'body': 'b',
        'is_read': false,
        'created_at': '2026-07-13T10:00:00.000Z',
      });

      expect(item.type, 'something_never_seen_before');
    });

    test('missing type/title/body falls back safely', () {
      final item = NotificationItem.fromJson({
        'id': 'notif-4',
        'is_read': false,
        'created_at': '2026-07-13T10:00:00.000Z',
      });

      expect(item.type, 'unknown');
      expect(item.title, '');
      expect(item.body, '');
    });

    test('markedRead() returns a read copy with the same other fields', () {
      final item = NotificationItem.fromJson({
        'id': 'notif-5',
        'type': 'team_turn_skipped',
        'title': 't',
        'body': 'b',
        'is_read': false,
        'created_at': '2026-07-13T10:00:00.000Z',
      });

      final read = item.markedRead(at: DateTime(2026, 7, 13, 12));
      expect(read.isRead, true);
      expect(read.readAt, DateTime(2026, 7, 13, 12));
      expect(read.id, item.id);
      expect(read.title, item.title);
    });
  });

  group('NotificationsPage.fromJson', () {
    test('parses items, unread_count, has_more, and next_cursor', () {
      final page = NotificationsPage.fromJson({
        'items': [
          {
            'id': 'notif-1',
            'type': 'team_turn_today',
            'title': 't',
            'body': 'b',
            'is_read': false,
            'created_at': '2026-07-13T10:00:00.000Z',
          },
        ],
        'unread_count': 3,
        'has_more': true,
        'next_cursor': {'created_at': '2026-07-13T09:00:00.000Z', 'id': 'notif-9'},
      });

      expect(page.items, hasLength(1));
      expect(page.unreadCount, 3);
      expect(page.hasMore, true);
      expect(page.nextCursor, isNotNull);
      expect(page.nextCursor!.id, 'notif-9');
      expect(
        page.nextCursor!.createdAt,
        DateTime.parse('2026-07-13T09:00:00.000Z'),
      );
    });

    test('missing next_cursor parses safely as null', () {
      final page = NotificationsPage.fromJson({
        'items': [],
        'unread_count': 0,
        'has_more': false,
      });

      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
      expect(page.hasMore, false);
    });
  });
}
