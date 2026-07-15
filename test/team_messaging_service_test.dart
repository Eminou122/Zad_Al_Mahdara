import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/messaging/data/team_messaging_service.dart';
import 'package:zad_al_mahdara/features/messaging/domain/team_messaging_models.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _UnauthAuthService extends AuthService {
  @override
  String? get currentToken => null;
}

TeamMessage _msg({String senderRole = 'member'}) => TeamMessage(
  id: 'msg-1',
  conversationId: 'conv-1',
  senderProfileId: 'p-1',
  senderName: 'a',
  senderRole: senderRole,
  body: 'hi',
  createdAt: DateTime(2026, 7, 13, 10),
  isRead: true,
);

SentTeamMessage _sent() => SentTeamMessage(
  conversation: const TeamConversationRef(
    id: 'conv-1',
    teamId: 'team-1',
    memberProfileId: 'p-1',
  ),
  message: _msg(),
);

// Records the exact params each RPC call would carry — same pattern as
// notification_service_test.dart's _RecordingNotificationService: there is
// no injectable Supabase client seam, so the public method contract is
// verified this way instead of intercepting the network call.
class _RecordingTeamMessagingService extends TeamMessagingService {
  String? lastRpc;
  Map<String, dynamic>? lastParams;

  _RecordingTeamMessagingService() : super(AuthService());

  @override
  Future<SentTeamMessage> sendMessageToTeamLeader({
    required String teamId,
    required String body,
  }) async {
    lastRpc = 'send_team_leader_message';
    lastParams = {
      'p_session_token': 'test-token',
      'p_team_id': teamId,
      'p_body': body,
    };
    return _sent();
  }

  @override
  Future<SentTeamMessage> replyToTeamConversation({
    required String conversationId,
    required String body,
  }) async {
    lastRpc = 'leader_reply_team_message';
    lastParams = {
      'p_session_token': 'test-token',
      'p_conversation_id': conversationId,
      'p_body': body,
    };
    return _sent();
  }

  @override
  Future<TeamConversationsPage> getMyTeamConversations({
    int limit = 30,
    TeamConversationCursor? before,
    bool unreadOnly = false,
  }) async {
    lastRpc = 'get_my_team_conversations';
    lastParams = {
      'p_session_token': 'test-token',
      'p_limit': limit,
      'p_unread_only': unreadOnly,
    };
    if (before != null) {
      lastParams!['p_before_updated_at'] = before.updatedAt.toIso8601String();
      lastParams!['p_before_id'] = before.id;
    }
    return const TeamConversationsPage(items: [], hasMore: false);
  }

  @override
  Future<TeamMessagesPage> getTeamConversationMessages({
    required String conversationId,
    int limit = 50,
    TeamMessageCursor? before,
  }) async {
    lastRpc = 'get_team_conversation_messages';
    lastParams = {
      'p_session_token': 'test-token',
      'p_conversation_id': conversationId,
      'p_limit': limit,
    };
    if (before != null) {
      lastParams!['p_before_created_at'] = before.createdAt.toIso8601String();
      lastParams!['p_before_id'] = before.id;
    }
    return TeamMessagesPage(
      conversationId: conversationId,
      items: const [],
      hasMore: false,
    );
  }

  @override
  Future<void> markConversationRead(String conversationId) async {
    lastRpc = 'mark_team_conversation_read';
    lastParams = {
      'p_session_token': 'test-token',
      'p_conversation_id': conversationId,
    };
  }

  @override
  Future<TeamAnnouncement> createTeamAnnouncement({
    required String teamId,
    required String body,
    String? title,
  }) async {
    lastRpc = 'create_team_announcement';
    lastParams = {
      'p_session_token': 'test-token',
      'p_team_id': teamId,
      'p_body': body,
      'p_title': title,
    };
    return TeamAnnouncement(
      id: 'ann-1',
      teamId: teamId,
      teamName: 't',
      authorProfileId: 'p-1',
      authorName: 'a',
      title: title,
      body: body,
      createdAt: DateTime(2026, 7, 13, 10),
      isRead: true,
    );
  }

  @override
  Future<TeamAnnouncementsPage> getMyTeamAnnouncements({
    String? teamId,
    int limit = 30,
    TeamAnnouncementCursor? before,
    bool unreadOnly = false,
  }) async {
    lastRpc = 'get_my_team_announcements';
    lastParams = {
      'p_session_token': 'test-token',
      'p_team_id': teamId,
      'p_limit': limit,
      'p_unread_only': unreadOnly,
    };
    if (before != null) {
      lastParams!['p_before_created_at'] = before.createdAt.toIso8601String();
      lastParams!['p_before_id'] = before.id;
    }
    return const TeamAnnouncementsPage(items: [], hasMore: false);
  }

  @override
  Future<void> markAnnouncementRead(String announcementId) async {
    lastRpc = 'mark_team_announcement_read';
    lastParams = {
      'p_session_token': 'test-token',
      'p_announcement_id': announcementId,
    };
  }

  @override
  Future<MessagingUnreadCount> getMessagingUnreadCount() async {
    lastRpc = 'get_my_messaging_unread_count';
    lastParams = {'p_session_token': 'test-token'};
    return MessagingUnreadCount.zero;
  }
}

void main() {
  group('TeamMessagingService session guard (Arabic-safe error)', () {
    test('sendMessageToTeamLeader throws without a session token', () async {
      final svc = TeamMessagingService(_UnauthAuthService());
      await expectLater(
        svc.sendMessageToTeamLeader(teamId: 't1', body: 'hi'),
        throwsA(predicate((e) => e.toString().contains('انتهت الجلسة'))),
      );
    });

    test('replyToTeamConversation throws without a session token', () async {
      final svc = TeamMessagingService(_UnauthAuthService());
      await expectLater(
        svc.replyToTeamConversation(conversationId: 'c1', body: 'hi'),
        throwsA(predicate((e) => e.toString().contains('انتهت الجلسة'))),
      );
    });

    test('getMyTeamConversations throws without a session token', () async {
      final svc = TeamMessagingService(_UnauthAuthService());
      await expectLater(
        svc.getMyTeamConversations(),
        throwsA(predicate((e) => e.toString().contains('انتهت الجلسة'))),
      );
    });

    test(
      'getTeamConversationMessages throws without a session token',
      () async {
        final svc = TeamMessagingService(_UnauthAuthService());
        await expectLater(
          svc.getTeamConversationMessages(conversationId: 'c1'),
          throwsA(predicate((e) => e.toString().contains('انتهت الجلسة'))),
        );
      },
    );

    test('markConversationRead throws without a session token', () async {
      final svc = TeamMessagingService(_UnauthAuthService());
      await expectLater(
        svc.markConversationRead('c1'),
        throwsA(predicate((e) => e.toString().contains('انتهت الجلسة'))),
      );
    });

    test('createTeamAnnouncement throws without a session token', () async {
      final svc = TeamMessagingService(_UnauthAuthService());
      await expectLater(
        svc.createTeamAnnouncement(teamId: 't1', body: 'b'),
        throwsA(predicate((e) => e.toString().contains('انتهت الجلسة'))),
      );
    });

    test('getMyTeamAnnouncements throws without a session token', () async {
      final svc = TeamMessagingService(_UnauthAuthService());
      await expectLater(
        svc.getMyTeamAnnouncements(),
        throwsA(predicate((e) => e.toString().contains('انتهت الجلسة'))),
      );
    });

    test('markAnnouncementRead throws without a session token', () async {
      final svc = TeamMessagingService(_UnauthAuthService());
      await expectLater(
        svc.markAnnouncementRead('a1'),
        throwsA(predicate((e) => e.toString().contains('انتهت الجلسة'))),
      );
    });

    test('getMessagingUnreadCount throws without a session token', () async {
      final svc = TeamMessagingService(_UnauthAuthService());
      await expectLater(
        svc.getMessagingUnreadCount(),
        throwsA(predicate((e) => e.toString().contains('انتهت الجلسة'))),
      );
    });
  });

  group('TeamMessagingService call shape', () {
    test('member-send sends team id + body, no conversation id', () async {
      final svc = _RecordingTeamMessagingService();
      await svc.sendMessageToTeamLeader(teamId: 'team-1', body: 'hello');
      expect(svc.lastRpc, 'send_team_leader_message');
      expect(svc.lastParams!['p_team_id'], 'team-1');
      expect(svc.lastParams!['p_body'], 'hello');
      expect(svc.lastParams!.containsKey('p_conversation_id'), false);
    });

    test('leader-reply sends conversation id + body, no team id', () async {
      final svc = _RecordingTeamMessagingService();
      await svc.replyToTeamConversation(conversationId: 'conv-1', body: 'ok');
      expect(svc.lastRpc, 'leader_reply_team_message');
      expect(svc.lastParams!['p_conversation_id'], 'conv-1');
      expect(svc.lastParams!['p_body'], 'ok');
      expect(svc.lastParams!.containsKey('p_team_id'), false);
    });

    test('conversation pagination sends both cursor parts together', () async {
      final svc = _RecordingTeamMessagingService();
      final cursor = TeamConversationCursor(
        updatedAt: DateTime.utc(2026, 7, 13, 9),
        id: 'conv-9',
      );
      await svc.getMyTeamConversations(before: cursor);
      expect(
        svc.lastParams!['p_before_updated_at'],
        cursor.updatedAt.toIso8601String(),
      );
      expect(svc.lastParams!['p_before_id'], 'conv-9');
    });

    test('first conversation page sends no cursor', () async {
      final svc = _RecordingTeamMessagingService();
      await svc.getMyTeamConversations();
      expect(svc.lastParams!.containsKey('p_before_updated_at'), false);
      expect(svc.lastParams!.containsKey('p_before_id'), false);
    });

    test('message pagination sends both cursor parts together', () async {
      final svc = _RecordingTeamMessagingService();
      final cursor = TeamMessageCursor(
        createdAt: DateTime.utc(2026, 7, 13, 9),
        id: 'msg-9',
      );
      await svc.getTeamConversationMessages(
        conversationId: 'conv-1',
        before: cursor,
      );
      expect(
        svc.lastParams!['p_before_created_at'],
        cursor.createdAt.toIso8601String(),
      );
      expect(svc.lastParams!['p_before_id'], 'msg-9');
    });

    test('announcement pagination sends both cursor parts together', () async {
      final svc = _RecordingTeamMessagingService();
      final cursor = TeamAnnouncementCursor(
        createdAt: DateTime.utc(2026, 7, 13, 9),
        id: 'ann-9',
      );
      await svc.getMyTeamAnnouncements(teamId: 'team-1', before: cursor);
      expect(svc.lastParams!['p_team_id'], 'team-1');
      expect(
        svc.lastParams!['p_before_created_at'],
        cursor.createdAt.toIso8601String(),
      );
      expect(svc.lastParams!['p_before_id'], 'ann-9');
    });

    test('mark_team_conversation_read sends conversation id', () async {
      final svc = _RecordingTeamMessagingService();
      await svc.markConversationRead('conv-1');
      expect(svc.lastRpc, 'mark_team_conversation_read');
      expect(svc.lastParams!['p_conversation_id'], 'conv-1');
    });

    test('mark_team_announcement_read sends announcement id', () async {
      final svc = _RecordingTeamMessagingService();
      await svc.markAnnouncementRead('ann-1');
      expect(svc.lastRpc, 'mark_team_announcement_read');
      expect(svc.lastParams!['p_announcement_id'], 'ann-1');
    });

    test(
      'create announcement sends team id, body, and optional title',
      () async {
        final svc = _RecordingTeamMessagingService();
        await svc.createTeamAnnouncement(
          teamId: 'team-1',
          body: 'body text',
          title: 'title text',
        );
        expect(svc.lastRpc, 'create_team_announcement');
        expect(svc.lastParams!['p_team_id'], 'team-1');
        expect(svc.lastParams!['p_body'], 'body text');
        expect(svc.lastParams!['p_title'], 'title text');
      },
    );

    test(
      'getMessagingUnreadCount calls get_my_messaging_unread_count',
      () async {
        final svc = _RecordingTeamMessagingService();
        final count = await svc.getMessagingUnreadCount();
        expect(svc.lastRpc, 'get_my_messaging_unread_count');
        expect(count.totalUnreadCount, 0);
      },
    );
  });

  group('TeamMessagingService error mapping', () {
    test(
      'unauthenticated error never leaks the raw "not authenticated" text',
      () async {
        final svc = TeamMessagingService(_UnauthAuthService());
        try {
          await svc.getMyTeamConversations();
          fail('expected an exception');
        } catch (e) {
          expect(e.toString().contains('not authenticated'), false);
          expect(e.toString().contains('انتهت الجلسة'), true);
        }
      },
    );
  });
}
