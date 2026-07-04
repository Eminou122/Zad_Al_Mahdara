import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/auth_service.dart';
import 'admin_models.dart';

class AdminService {
  final AuthService _auth;
  AdminService(this._auth);

  SupabaseClient get _client => Supabase.instance.client;

  String get _token {
    final t = _auth.currentToken;
    if (t == null) throw Exception('not authenticated');
    return t;
  }

  Future<AdminDashboard> getDashboard() async {
    final r = await _client.rpc(
      'get_admin_dashboard',
      params: {'p_session_token': _token},
    );
    return AdminDashboard.fromJson(Map<String, dynamic>.from(r as Map));
  }

  Future<List<AdminUserSummary>> listUsers(String query) async {
    final r = await _client.rpc(
      'admin_list_users',
      params: {'p_session_token': _token, 'p_query': query},
    );
    return (r as List)
        .map((e) => AdminUserSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<AdminUserDetail> getUserDetail(String profileId) async {
    final r = await _client.rpc(
      'admin_get_user_detail',
      params: {'p_session_token': _token, 'p_profile_id': profileId},
    );
    return AdminUserDetail.fromJson(Map<String, dynamic>.from(r as Map));
  }

  Future<void> deactivateUser(String profileId) async {
    await _client.rpc(
      'admin_deactivate_user',
      params: {'p_session_token': _token, 'p_profile_id': profileId},
    );
  }

  Future<void> reactivateUser(String profileId) async {
    await _client.rpc(
      'admin_reactivate_user',
      params: {'p_session_token': _token, 'p_profile_id': profileId},
    );
  }

  Future<List<AdminPublicTeam>> listPublicTeams() async {
    final r = await _client.rpc(
      'admin_list_public_teams',
      params: {'p_session_token': _token},
    );
    return (r as List)
        .map((e) => AdminPublicTeam.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<AdminPinResetRequest>> listActivePinResetRequests() async {
    final pending = await _listPinResetRequests('pending');
    final issued = await _listPinResetRequests('code_issued');
    return [...pending, ...issued]
      ..sort((a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)));
  }

  Future<AdminIssuedPinResetCode> issuePinResetCode(String requestId) async {
    final r = await _client.rpc(
      'admin_issue_pin_reset_code',
      params: {'p_session_token': _token, 'p_request_id': requestId},
    );
    return AdminIssuedPinResetCode.fromJson(Map<String, dynamic>.from(r as Map));
  }

  Future<void> cancelPinResetRequest(String requestId) async {
    await _client.rpc(
      'admin_cancel_pin_reset_request',
      params: {'p_session_token': _token, 'p_request_id': requestId},
    );
  }

  Future<List<AdminPinResetRequest>> _listPinResetRequests(String status) async {
    final r = await _client.rpc(
      'admin_list_pin_reset_requests',
      params: {'p_session_token': _token, 'p_status': status},
    );
    return (r as List)
        .map((e) =>
            AdminPinResetRequest.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
