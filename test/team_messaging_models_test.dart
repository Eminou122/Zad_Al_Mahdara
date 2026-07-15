import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/messaging/domain/team_messaging_models.dart';

void main() {
  group('TeamConversationSummary.fromJson', () {
    test('parses a leader-view row', () {
      final c = TeamConversationSummary.fromJson({
        'id': 'conv-1',
        'team_id': 'team-1',
        'team_name': 'فريق الغداء',
        'member_profile_id': 'member-1',
        'member_name': 'أحمد',
        'latest_message_preview': 'مرحباً',
        'latest_message_at': '2026-07-13T10:00:00.000Z',
        'unread_count': 2,
        'current_user_role': 'leader',
      });

      expect(c.id, 'conv-1');
      expect(c.teamName, 'فريق الغداء');
      expect(c.memberName, 'أحمد');
      expect(c.unreadCount, 2);
      expect(c.isLeaderView, true);
      expect(c.isMemberView, false);
      expect(c.hasUnread, true);
      expect(c.displayName, 'أحمد');
      expect(c.latestPreviewText, 'مرحباً');
    });

    test('parses a member-view row with role="member"', () {
      final c = TeamConversationSummary.fromJson({
        'id': 'conv-2',
        'team_id': 'team-1',
        'team_name': 'فريق الغداء',
        'member_profile_id': 'member-1',
        'member_name': 'أحمد',
        'unread_count': 0,
        'current_user_role': 'member',
      });

      expect(c.isMemberView, true);
      expect(c.isLeaderView, false);
      expect(c.hasUnread, false);
    });

    test('missing latest_message_preview/at parse safely as null', () {
      final c = TeamConversationSummary.fromJson({
        'id': 'conv-3',
        'team_id': 'team-1',
        'team_name': 't',
        'member_profile_id': 'm-1',
        'member_name': 'm',
        'unread_count': 0,
        'current_user_role': 'member',
      });

      expect(c.latestMessagePreview, isNull);
      expect(c.latestMessageAt, isNull);
      expect(c.latestPreviewText, '');
    });

    test('unknown extra fields are ignored', () {
      final c = TeamConversationSummary.fromJson({
        'id': 'conv-4',
        'team_id': 'team-1',
        'team_name': 't',
        'member_profile_id': 'm-1',
        'member_name': 'm',
        'unread_count': 0,
        'current_user_role': 'member',
        'something_new': 'value',
      });
      expect(c.id, 'conv-4');
    });

    test('missing current_user_role defaults to member (defensive)', () {
      final c = TeamConversationSummary.fromJson({
        'id': 'conv-5',
        'team_id': 'team-1',
        'team_name': 't',
        'member_profile_id': 'm-1',
        'member_name': 'm',
        'unread_count': 0,
      });
      expect(c.currentUserRole, 'member');
    });
  });

  group('TeamConversationCursor.fromJson', () {
    test('parses updated_at + id', () {
      final cur = TeamConversationCursor.fromJson({
        'updated_at': '2026-07-13T09:00:00.000Z',
        'id': 'conv-9',
      });
      expect(cur.updatedAt, DateTime.parse('2026-07-13T09:00:00.000Z'));
      expect(cur.id, 'conv-9');
    });
  });

  group('TeamConversationsPage.fromJson', () {
    test('parses items/has_more/next_cursor', () {
      final page = TeamConversationsPage.fromJson({
        'items': [
          {
            'id': 'conv-1',
            'team_id': 'team-1',
            'team_name': 't',
            'member_profile_id': 'm-1',
            'member_name': 'm',
            'unread_count': 0,
            'current_user_role': 'member',
          },
        ],
        'has_more': true,
        'next_cursor': {
          'updated_at': '2026-07-13T09:00:00.000Z',
          'id': 'conv-1',
        },
      });
      expect(page.items, hasLength(1));
      expect(page.hasMore, true);
      expect(page.nextCursor, isNotNull);
    });

    test('missing next_cursor parses safely as null, empty items safe', () {
      final page = TeamConversationsPage.fromJson({
        'items': [],
        'has_more': false,
      });
      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
      expect(page.hasMore, false);
    });
  });

  group('TeamMessage.fromJson', () {
    test('parses all fields', () {
      final m = TeamMessage.fromJson({
        'id': 'msg-1',
        'conversation_id': 'conv-1',
        'sender_profile_id': 'p-1',
        'sender_name': 'أحمد',
        'sender_role': 'member',
        'body': 'مرحباً',
        'created_at': '2026-07-13T10:00:00.000Z',
        'is_read': false,
      });
      expect(m.id, 'msg-1');
      expect(m.senderRole, 'member');
      expect(m.isMemberMessage, true);
      expect(m.isLeaderMessage, false);
      expect(m.isSentBy('p-1'), true);
      expect(m.isSentBy('p-2'), false);
      expect(m.isSentBy(null), false);
    });

    test('sender_role="leader" flags correctly', () {
      final m = TeamMessage.fromJson({
        'id': 'msg-2',
        'conversation_id': 'conv-1',
        'sender_profile_id': 'p-2',
        'sender_name': 'القائد',
        'sender_role': 'leader',
        'body': 'رد',
        'created_at': '2026-07-13T10:05:00.000Z',
        'is_read': true,
      });
      expect(m.isLeaderMessage, true);
      expect(m.isMemberMessage, false);
    });
  });

  group('TeamMessagesPage.fromJson', () {
    test('parses conversation_id/items/has_more/next_cursor', () {
      final page = TeamMessagesPage.fromJson({
        'conversation_id': 'conv-1',
        'items': [
          {
            'id': 'msg-1',
            'conversation_id': 'conv-1',
            'sender_profile_id': 'p-1',
            'sender_name': 'a',
            'sender_role': 'member',
            'body': 'b',
            'created_at': '2026-07-13T10:00:00.000Z',
            'is_read': true,
          },
        ],
        'has_more': false,
        'next_cursor': null,
      });
      expect(page.conversationId, 'conv-1');
      expect(page.items, hasLength(1));
      expect(page.hasMore, false);
      expect(page.nextCursor, isNull);
    });
  });

  group('SentTeamMessage.fromJson', () {
    test('parses nested conversation + message', () {
      final sent = SentTeamMessage.fromJson({
        'conversation': {
          'id': 'conv-1',
          'team_id': 'team-1',
          'member_profile_id': 'm-1',
          'updated_at': '2026-07-13T10:00:00.000Z',
        },
        'message': {
          'id': 'msg-1',
          'conversation_id': 'conv-1',
          'sender_profile_id': 'm-1',
          'sender_name': 'a',
          'sender_role': 'member',
          'body': 'hi',
          'created_at': '2026-07-13T10:00:00.000Z',
          'is_read': true,
        },
      });
      expect(sent.conversation.id, 'conv-1');
      expect(sent.conversation.teamId, 'team-1');
      expect(sent.message.id, 'msg-1');
    });
  });

  group('TeamAnnouncement.fromJson', () {
    test('parses with title', () {
      final a = TeamAnnouncement.fromJson({
        'id': 'ann-1',
        'team_id': 'team-1',
        'team_name': 't',
        'author_profile_id': 'p-1',
        'author_name': 'القائد',
        'title': 'إعلان مهم',
        'body': 'نص الإعلان',
        'created_at': '2026-07-13T10:00:00.000Z',
        'is_read': false,
      });
      expect(a.title, 'إعلان مهم');
      expect(a.isRead, false);
    });

    test('nullable title parses safely (title omitted)', () {
      final a = TeamAnnouncement.fromJson({
        'id': 'ann-2',
        'team_id': 'team-1',
        'team_name': 't',
        'author_profile_id': 'p-1',
        'author_name': 'القائد',
        'body': 'نص الإعلان',
        'created_at': '2026-07-13T10:00:00.000Z',
        'is_read': true,
      });
      expect(a.title, isNull);
    });
  });

  group('TeamAnnouncementsPage.fromJson', () {
    test('parses items/has_more/next_cursor', () {
      final page = TeamAnnouncementsPage.fromJson({
        'items': [
          {
            'id': 'ann-1',
            'team_id': 'team-1',
            'team_name': 't',
            'author_profile_id': 'p-1',
            'author_name': 'a',
            'body': 'b',
            'created_at': '2026-07-13T10:00:00.000Z',
            'is_read': false,
          },
        ],
        'has_more': true,
        'next_cursor': {
          'created_at': '2026-07-13T09:00:00.000Z',
          'id': 'ann-1',
        },
      });
      expect(page.items, hasLength(1));
      expect(page.hasMore, true);
      expect(page.nextCursor!.id, 'ann-1');
    });
  });

  group('MessagingUnreadCount.fromJson', () {
    test('parses all three counts', () {
      final count = MessagingUnreadCount.fromJson({
        'private_message_unread_count': 3,
        'announcement_unread_count': 2,
        'total_unread_count': 5,
      });
      expect(count.privateMessageUnreadCount, 3);
      expect(count.announcementUnreadCount, 2);
      expect(count.totalUnreadCount, 5);
    });

    test('zero unread parses safely', () {
      final count = MessagingUnreadCount.fromJson({
        'private_message_unread_count': 0,
        'announcement_unread_count': 0,
        'total_unread_count': 0,
      });
      expect(count.totalUnreadCount, 0);
      expect(count, isNotNull);
    });

    test('MessagingUnreadCount.zero is all-zero', () {
      expect(MessagingUnreadCount.zero.totalUnreadCount, 0);
      expect(MessagingUnreadCount.zero.privateMessageUnreadCount, 0);
      expect(MessagingUnreadCount.zero.announcementUnreadCount, 0);
    });
  });
}
