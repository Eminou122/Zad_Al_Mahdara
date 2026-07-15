import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/auth_service.dart';
import '../domain/team_messaging_models.dart';

const _sessionExpiredMessage = 'انتهت الجلسة، يرجى تسجيل الدخول من جديد';
const _genericErrorMessage = 'حدث خطأ، حاول مرة أخرى';
const _conversationAccessDeniedMessage =
    'لا تملك صلاحية الوصول إلى هذه المحادثة';
const _conversationUnavailableMessage = 'لم يعد بإمكانك استخدام هذه المحادثة';

/// Wraps the nine messaging RPCs from migrations 033/034. Same shape as
/// [NotificationService]/[TeamService]: no client.from(), no auth.uid(),
/// session token resolved fresh on every call.
class TeamMessagingService {
  final AuthService _auth;
  TeamMessagingService(this._auth);

  SupabaseClient get _c => Supabase.instance.client;

  String get _token {
    final t = _auth.currentToken;
    if (t == null) throw Exception(_sessionExpiredMessage);
    return t;
  }

  /// Maps a raised error to a user-safe message. Backend RPCs already raise
  /// Arabic exception text (see migration 033/034 design notes), so a
  /// [PostgrestException] is safe to surface as-is; anything else (network,
  /// timeout, the local session guard above) is replaced so no stack trace
  /// or SQL detail ever reaches the UI.
  Never _throwSafe(Object e) {
    if (e is PostgrestException) {
      if (e.message.contains('غير مصرح لك بعرض هذه المحادثة')) {
        throw Exception(_conversationAccessDeniedMessage);
      }
      if (e.message.contains('لم يعد ضمن الفريق')) {
        throw Exception(_conversationUnavailableMessage);
      }
      throw Exception(e.message);
    }
    final msg = e.toString();
    if (msg.contains(_sessionExpiredMessage)) {
      throw Exception(_sessionExpiredMessage);
    }
    throw Exception(_genericErrorMessage);
  }

  Future<T> _run<T>(Future<T> Function() body) async {
    try {
      _token;
      return await body();
    } catch (e) {
      _throwSafe(e);
    }
  }

  Future<SentTeamMessage> sendMessageToTeamLeader({
    required String teamId,
    required String body,
  }) {
    return _run(() async {
      final res = await _c.rpc(
        'send_team_leader_message',
        params: {
          'p_session_token': _token,
          'p_team_id': teamId,
          'p_body': body,
        },
      );
      return SentTeamMessage.fromJson(Map<String, dynamic>.from(res as Map));
    });
  }

  Future<SentTeamMessage> replyToTeamConversation({
    required String conversationId,
    required String body,
  }) {
    return _run(() async {
      final res = await _c.rpc(
        'leader_reply_team_message',
        params: {
          'p_session_token': _token,
          'p_conversation_id': conversationId,
          'p_body': body,
        },
      );
      return SentTeamMessage.fromJson(Map<String, dynamic>.from(res as Map));
    });
  }

  Future<TeamConversationsPage> getMyTeamConversations({
    int limit = 30,
    TeamConversationCursor? before,
    bool unreadOnly = false,
  }) {
    return _run(() async {
      final params = <String, dynamic>{
        'p_session_token': _token,
        'p_limit': limit,
        'p_unread_only': unreadOnly,
      };
      if (before != null) {
        params['p_before_updated_at'] = before.updatedAt.toIso8601String();
        params['p_before_id'] = before.id;
      }
      final res = await _c.rpc('get_my_team_conversations', params: params);
      return TeamConversationsPage.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    });
  }

  Future<TeamMessagesPage> getTeamConversationMessages({
    required String conversationId,
    int limit = 50,
    TeamMessageCursor? before,
  }) {
    return _run(() async {
      final params = <String, dynamic>{
        'p_session_token': _token,
        'p_conversation_id': conversationId,
        'p_limit': limit,
      };
      if (before != null) {
        params['p_before_created_at'] = before.createdAt.toIso8601String();
        params['p_before_id'] = before.id;
      }
      final res = await _c.rpc(
        'get_team_conversation_messages',
        params: params,
      );
      return TeamMessagesPage.fromJson(Map<String, dynamic>.from(res as Map));
    });
  }

  Future<void> markConversationRead(String conversationId) {
    return _run(() async {
      await _c.rpc(
        'mark_team_conversation_read',
        params: {
          'p_session_token': _token,
          'p_conversation_id': conversationId,
        },
      );
    });
  }

  Future<TeamAnnouncement> createTeamAnnouncement({
    required String teamId,
    required String body,
    String? title,
  }) {
    return _run(() async {
      final res = await _c.rpc(
        'create_team_announcement',
        params: {
          'p_session_token': _token,
          'p_team_id': teamId,
          'p_body': body,
          'p_title': title,
        },
      );
      return TeamAnnouncement.fromJson(Map<String, dynamic>.from(res as Map));
    });
  }

  Future<TeamAnnouncementsPage> getMyTeamAnnouncements({
    String? teamId,
    int limit = 30,
    TeamAnnouncementCursor? before,
    bool unreadOnly = false,
  }) {
    return _run(() async {
      final params = <String, dynamic>{
        'p_session_token': _token,
        'p_team_id': teamId,
        'p_limit': limit,
        'p_unread_only': unreadOnly,
      };
      if (before != null) {
        params['p_before_created_at'] = before.createdAt.toIso8601String();
        params['p_before_id'] = before.id;
      }
      final res = await _c.rpc('get_my_team_announcements', params: params);
      return TeamAnnouncementsPage.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    });
  }

  Future<void> markAnnouncementRead(String announcementId) {
    return _run(() async {
      await _c.rpc(
        'mark_team_announcement_read',
        params: {
          'p_session_token': _token,
          'p_announcement_id': announcementId,
        },
      );
    });
  }

  // Dedupe concurrent calls: this is refreshed from many places (login,
  // resume, every send/read/create) so overlapping refreshes should share
  // one in-flight request instead of racing the RPC.
  Future<MessagingUnreadCount>? _unreadCountInFlight;

  Future<MessagingUnreadCount> getMessagingUnreadCount() {
    final inFlight = _unreadCountInFlight;
    if (inFlight != null) return inFlight;
    late final Future<MessagingUnreadCount> future;
    future =
        _run(() async {
          final res = await _c.rpc(
            'get_my_messaging_unread_count',
            params: {'p_session_token': _token},
          );
          return MessagingUnreadCount.fromJson(
            Map<String, dynamic>.from(res as Map),
          );
        }).whenComplete(() {
          if (identical(_unreadCountInFlight, future)) {
            _unreadCountInFlight = null;
          }
        });
    _unreadCountInFlight = future;
    return future;
  }
}
