import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/error_text.dart';
import '../../../services/auth_service.dart';
import '../../messaging/domain/team_messaging_models.dart';
import '../domain/student_directory_models.dart';

class StudentDirectoryService {
  final AuthService _auth;
  StudentDirectoryService(this._auth);
  SupabaseClient get _client => Supabase.instance.client;
  String get _token =>
      _auth.currentToken ??
      (throw Exception('انتهت الجلسة، يرجى تسجيل الدخول من جديد'));

  Future<AvailablePublicTeamsResult> getAvailablePublicTeams() async {
    try {
      final res = await rpc('get_available_public_teams', {
        'p_session_token': _token,
      });
      return AvailablePublicTeamsResult.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    } catch (e) {
      throw Exception(userErrorText(e));
    }
  }

  Future<TeamConversationRef> contactAvailableTeamLeader({
    required String teamId,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) throw Exception('اكتب رسالة أولاً');
    if (trimmed.length > 500) throw Exception('الرسالة طويلة جدًا');
    try {
      final res = await rpc('contact_available_team_leader', {
        'p_session_token': _token,
        'p_team_id': teamId,
        'p_body': trimmed,
      });
      final data = Map<String, dynamic>.from(res as Map);
      if (data['ok'] != true || data['conversation_id'] is! String) {
        throw Exception('رفض الإرسال');
      }
      return TeamConversationRef(
        id: data['conversation_id'] as String,
        teamId: data['team_id'] as String? ?? teamId,
        memberProfileId: '',
      );
    } catch (e) {
      throw Exception(userErrorText(e));
    }
  }

  @protected
  Future<dynamic> rpc(String name, Map<String, dynamic> params) =>
      _client.rpc(name, params: params);
}
