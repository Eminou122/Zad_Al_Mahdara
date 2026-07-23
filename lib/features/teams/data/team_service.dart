import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/mauritanian_phone.dart';
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

  Future<TeamDetail> createTeamWithMembers({
    required String name,
    required String teamType,
    required bool isPublic,
    required String status,
    String? note,
    required List<Map<String, dynamic>> members,
  }) async {
    final res = await rpc('create_team_with_members', {
      'p_session_token': _token,
      'p_name': name,
      'p_team_type': teamType,
      'p_is_public': isPublic,
      'p_status': status,
      'p_note': note,
      'p_members': members,
    });
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
        .map(
          (e) =>
              TeamMemberCandidate.fromJson(Map<String, dynamic>.from(e as Map)),
        )
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
    final normalizedPhone = normalizeMauritanianPhone(phoneNumber);
    if (validateMauritanianPhone(normalizedPhone) != null) {
      throw Exception(mauritanianPhoneValidationMessage);
    }
    final res = await rpc('upsert_external_student_and_add_to_team', {
      'p_session_token': _token,
      'p_team_id': teamId,
      'p_display_name': displayName,
      'p_phone_number': normalizedPhone,
    });
    return TeamDetail.fromJson(Map<String, dynamic>.from(res as Map));
  }

  @protected
  Future<dynamic> rpc(String name, Map<String, dynamic> params) =>
      _c.rpc(name, params: params);

  Future<TeamDetail> reorderTeamMembers(
    String teamId,
    List<String> memberIds,
  ) async {
    final res = await rpc('reorder_team_members', {
      'p_session_token': _token,
      'p_team_id': teamId,
      'p_member_ids': memberIds,
    });
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

  Future<TeamMemberRemoval> removeTeamMember({
    required String memberId,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty || trimmed.length > 300) {
      throw ArgumentError('invalid removal reason');
    }
    final res = await rpc('remove_team_member', {
      'p_session_token': _token,
      'p_membership_id': memberId,
      'p_reason': trimmed,
    });
    final result = Map<String, dynamic>.from(res as Map);
    if (result['ok'] != true ||
        result['removed'] is! bool ||
        result['team'] is! Map) {
      throw StateError('invalid removal response');
    }
    return TeamMemberRemoval(
      removed: result['removed'] as bool,
      detail: TeamDetail.fromJson(
        Map<String, dynamic>.from(result['team'] as Map),
      ),
    );
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

  Future<TeamDetail> archiveTeam(String teamId) async {
    final res = await rpc('archive_team', {
      'p_session_token': _token,
      'p_team_id': teamId,
    });
    return TeamDetail.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<TeamDetail> restoreTeam(String teamId) async {
    final res = await rpc('restore_team', {
      'p_session_token': _token,
      'p_team_id': teamId,
    });
    return TeamDetail.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<TeamRemovalResult> removeTeamPermanently({
    required String teamId,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty || trimmed.length > 300) {
      throw ArgumentError('invalid removal reason');
    }
    final res = await rpc('remove_team_permanently', {
      'p_session_token': _token,
      'p_team_id': teamId,
      'p_reason': trimmed,
    });
    final result = Map<String, dynamic>.from(res as Map);
    if (result['ok'] != true ||
        result['removed'] is! bool ||
        result['blocked'] is! bool) {
      throw StateError('invalid team removal response');
    }
    return TeamRemovalResult(
      removed: result['removed'] as bool,
      blocked: result['blocked'] as bool,
    );
  }
}

class TeamMemberRemoval {
  final bool removed;
  final TeamDetail detail;

  const TeamMemberRemoval({required this.removed, required this.detail});
}

class TeamRemovalResult {
  final bool removed;
  final bool blocked;
  const TeamRemovalResult({required this.removed, required this.blocked});
}
