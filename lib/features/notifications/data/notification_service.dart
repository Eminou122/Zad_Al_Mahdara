import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/auth_service.dart';
import '../domain/notification_models.dart';

class NotificationService {
  final AuthService _auth;
  NotificationService(this._auth);

  SupabaseClient get _c => Supabase.instance.client;
  String get _token {
    final t = _auth.currentToken;
    if (t == null) throw Exception('not authenticated');
    return t;
  }

  Future<NotificationsPage> getNotifications({
    int limit = 30,
    DateTime? before,
    String? beforeId,
    bool unreadOnly = false,
  }) async {
    // _token is read into the params map before _c is ever touched, so the
    // auth guard always throws first regardless of Supabase's init state.
    final params = <String, dynamic>{
      'p_session_token': _token,
      'p_limit': limit,
      'p_unread_only': unreadOnly,
    };
    if (before != null) params['p_before'] = before.toIso8601String();
    if (beforeId != null) params['p_before_id'] = beforeId;
    final res = await _c.rpc('get_my_notifications', params: params);
    return NotificationsPage.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<int> getUnreadCount() async {
    final token = _token;
    final res = await _c.rpc(
      'get_my_notification_unread_count',
      params: {'p_session_token': token},
    );
    return (res as num).toInt();
  }

  Future<void> markRead(String notificationId) async {
    final token = _token;
    await _c.rpc(
      'mark_notification_read',
      params: {'p_session_token': token, 'p_notification_id': notificationId},
    );
  }

  Future<void> markAllRead() async {
    final token = _token;
    await _c.rpc('mark_all_notifications_read', params: {'p_session_token': token});
  }

  Future<void> archiveNotification(String notificationId) async {
    final token = _token;
    await _c.rpc(
      'archive_notification',
      params: {'p_session_token': token, 'p_notification_id': notificationId},
    );
  }
}
