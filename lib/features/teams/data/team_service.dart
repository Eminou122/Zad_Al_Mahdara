import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/auth_service.dart';
import '../domain/team_models.dart';

class TeamService {
  final AuthService _auth;
  TeamService(this._auth);

  SupabaseClient get _c => Supabase.instance.client;
  String get _token {
    final t = _auth.currentToken;
    if (t == null) throw Exception('not authenticated');
    return t;
  }

  Future<List<TeamSummary>> getMyTeams() async {
    final res = await _c.rpc(
      'get_my_teams',
      params: {'p_session_token': _token},
    );
    return (res as List)
        .map((e) => TeamSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<TeamSummary>> getPublicTeams() async {
    final res = await _c.rpc(
      'get_public_teams',
      params: {'p_session_token': _token},
    );
    return (res as List)
        .map((e) => TeamSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<TeamDetail> getTeamDetail(String teamId) async {
    final res = await _c.rpc(
      'get_team_detail',
      params: {'p_session_token': _token, 'p_team_id': teamId},
    );
    return TeamDetail.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<TeamDetail> createTeam({
    required String name,
    required String teamType,
    required bool isPublic,
    required String status,
    String? note,
  }) async {
    final res = await _c.rpc(
      'create_team',
      params: {
        'p_session_token': _token,
        'p_name': name,
        'p_team_type': teamType,
        'p_is_public': isPublic,
        'p_status': status,
        'p_note': note,
      },
    );
    return TeamDetail.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<TeamDetail> updateTeamSettings({
    required String teamId,
    required String name,
    required String teamType,
    required bool isPublic,
    required String status,
    String? note,
  }) async {
    final res = await _c.rpc(
      'update_team_settings',
      params: {
        'p_session_token': _token,
        'p_team_id': teamId,
        'p_name': name,
        'p_team_type': teamType,
        'p_is_public': isPublic,
        'p_status': status,
        'p_note': note,
      },
    );
    return TeamDetail.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<List<StudentResult>> searchStudents(String query) async {
    final res = await _c.rpc(
      'search_students_for_team',
      params: {'p_session_token': _token, 'p_query': query},
    );
    return (res as List)
        .map((e) => StudentResult.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> addTeamMember({
    required String teamId,
    required String profileId,
  }) async {
    await _c.rpc(
      'add_team_member',
      params: {
        'p_session_token': _token,
        'p_team_id': teamId,
        'p_user_id': profileId,
      },
    );
  }

  Future<void> deactivateTeamMember({
    required String teamId,
    required String memberId,
  }) async {
    await _c.rpc(
      'deactivate_team_member',
      params: {
        'p_session_token': _token,
        'p_team_id': teamId,
        'p_member_id': memberId,
      },
    );
  }

  Future<void> removeTeamMember({
    required String teamId,
    required String memberId,
  }) async {
    await _c.rpc(
      'remove_team_member',
      params: {
        'p_session_token': _token,
        'p_team_id': teamId,
        'p_member_id': memberId,
      },
    );
  }

  Future<void> reactivateTeamMember({
    required String teamId,
    required String memberId,
  }) async {
    await _c.rpc(
      'reactivate_team_member',
      params: {
        'p_session_token': _token,
        'p_team_id': teamId,
        'p_member_id': memberId,
      },
    );
  }
}
