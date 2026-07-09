import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/auth_service.dart';
import '../domain/team_turn_models.dart';

class TeamTurnService {
  final AuthService _auth;
  TeamTurnService(this._auth);

  SupabaseClient get _c => Supabase.instance.client;
  String get _token {
    final t = _auth.currentToken;
    if (t == null) throw Exception('not authenticated');
    return t;
  }

  Future<TeamTurnState> getTurnState(String teamId) async {
    final res = await _c.rpc(
      'get_team_turn_state',
      params: {'p_session_token': _token, 'p_team_id': teamId},
    );
    return TeamTurnState.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<TeamTurnState> ensureTodayTurn(String teamId) async {
    final res = await _c.rpc(
      'ensure_today_turn',
      params: {'p_session_token': _token, 'p_team_id': teamId},
    );
    return TeamTurnState.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<TeamTurnState> completeTurn(String turnId) async {
    final res = await _c.rpc(
      'complete_team_turn',
      params: {'p_session_token': _token, 'p_turn_id': turnId},
    );
    return TeamTurnState.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<TeamTurnState> skipMissedTurn(
    String teamId,
    String turnId, {
    String? reason,
  }) async {
    final trimmedReason = reason?.trim();
    final params = <String, dynamic>{
      'p_session_token': _token,
      'p_team_id': teamId,
      'p_turn_id': turnId,
      if (trimmedReason != null && trimmedReason.isNotEmpty)
        'p_reason': trimmedReason,
    };
    final res = await _c.rpc('skip_missed_team_turn', params: params);
    return TeamTurnState.fromJson(Map<String, dynamic>.from(res as Map));
  }
}
