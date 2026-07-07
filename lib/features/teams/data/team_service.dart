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

  Future<List<TeamMemberCandidate>> getTeamMemberCandidates(
    String teamId, {
    String? query,
  }) async {
    final res = await _c.rpc(
      'get_team_member_candidates',
      params: {
        'p_session_token': _token,
        'p_team_id': teamId,
        'p_query': query,
      },
    );
    return (res as List)
        .map((e) =>
            TeamMemberCandidate.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<TeamDetail> addTeamMember({
    required String teamId,
    required String profileId,
  }) async {
    final res = await _c.rpc(
      'add_team_member',
      params: {
        'p_session_token': _token,
        'p_team_id': teamId,
        'p_user_id': profileId,
      },
    );
    return TeamDetail.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<TeamDetail> upsertExternalStudentAndAddToTeam({
    required String teamId,
    required String displayName,
    required String phoneNumber,
  }) async {
    final res = await _c.rpc(
      'upsert_external_student_and_add_to_team',
      params: {
        'p_session_token': _token,
        'p_team_id': teamId,
        'p_display_name': displayName,
        'p_phone_number': phoneNumber,
      },
    );
    return TeamDetail.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<TeamDetail> deactivateTeamMember({
    required String teamId,
    required String memberId,
  }) async {
    final res = await _c.rpc(
      'deactivate_team_member',
      params: {
        'p_session_token': _token,
        'p_team_id': teamId,
        'p_member_id': memberId,
      },
    );
    return TeamDetail.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<TeamDetail> removeTeamMember({
    required String teamId,
    required String memberId,
  }) async {
    final res = await _c.rpc(
      'remove_team_member',
      params: {
        'p_session_token': _token,
        'p_team_id': teamId,
        'p_member_id': memberId,
      },
    );
    return TeamDetail.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<TeamDetail> reactivateTeamMember({
    required String teamId,
    required String memberId,
  }) async {
    final res = await _c.rpc(
      'reactivate_team_member',
      params: {
        'p_session_token': _token,
        'p_team_id': teamId,
        'p_member_id': memberId,
      },
    );
    return TeamDetail.fromJson(Map<String, dynamic>.from(res as Map));
  }
}
