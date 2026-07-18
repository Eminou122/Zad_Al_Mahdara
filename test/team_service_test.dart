import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/teams/data/team_service.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _Auth extends AuthService {
  @override
  String? get currentToken => 'test-token';
}

class _RecordingTeamService extends TeamService {
  int rpcCallCount = 0;
  String? lastRpc;
  Map<String, dynamic>? lastParams;

  _RecordingTeamService() : super(_Auth());

  @override
  Future<dynamic> rpc(String name, Map<String, dynamic> params) async {
    rpcCallCount++;
    lastRpc = name;
    lastParams = params;
    return {
      'team': {
        'id': 'team-1',
        'name': 'team',
        'team_type': 'lunch',
        'is_public': true,
        'status': 'open',
        'leader_id': 'leader-1',
        'leader_name': 'leader',
        'member_count': 1,
        'active_member_count': 1,
        'inactive_member_count': 0,
        'created_at': '2026-07-01T00:00:00Z',
      },
      'members': [],
      'can_edit': true,
      'is_member': true,
    };
  }
}

void main() {
  Future<void> add(_RecordingTeamService service, String phone) =>
      service.upsertExternalStudentAndAddToTeam(
        teamId: 'team-1',
        displayName: 'طالب',
        phoneNumber: phone,
      );

  test(
    'external student RPC normalizes raw and separated phone input',
    () async {
      for (final phone in ['12345678', '12 34 56 78', '12-34-56-78']) {
        final service = _RecordingTeamService();
        await add(service, phone);
        expect(service.lastRpc, 'upsert_external_student_and_add_to_team');
        expect(service.lastParams!['p_phone_number'], '12345678');
        expect(service.lastParams!.keys, {
          'p_session_token',
          'p_team_id',
          'p_display_name',
          'p_phone_number',
        });
      }
    },
  );

  test('invalid external phone makes no RPC call', () async {
    final service = _RecordingTeamService();
    await expectLater(add(service, '1234567'), throwsException);
    expect(service.rpcCallCount, 0);
  });
}
