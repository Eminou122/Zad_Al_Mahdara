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
  dynamic response;

  _RecordingTeamService() : super(_Auth());

  @override
  Future<dynamic> rpc(String name, Map<String, dynamic> params) async {
    rpcCallCount++;
    lastRpc = name;
    lastParams = params;
    if (name == 'upsert_external_student_and_add_to_team') {
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
    return response ??
        {
          'ok': true,
          'removed': true,
          'team': {
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
          },
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

  group('remove team member', () {
    test(
      'calls the shared removal RPC with trimmed reason and safe detail',
      () async {
        final service = _RecordingTeamService();
        final result = await service.removeTeamMember(
          memberId: 'membership-1',
          reason: ' سبب واضح ',
        );

        expect(service.lastRpc, 'remove_team_member');
        expect(service.lastParams, {
          'p_session_token': 'test-token',
          'p_membership_id': 'membership-1',
          'p_reason': 'سبب واضح',
        });
        expect(result.removed, isTrue);
        expect(result.detail.team.id, 'team-1');
      },
    );

    test(
      'accepts exactly 300 characters and rejects blank or overlong reason',
      () async {
        final service = _RecordingTeamService();
        await service.removeTeamMember(
          memberId: 'registered-or-external-membership',
          reason: List.filled(300, 'a').join(),
        );
        expect(service.rpcCallCount, 1);

        await expectLater(
          service.removeTeamMember(memberId: 'member', reason: '   '),
          throwsArgumentError,
        );
        await expectLater(
          service.removeTeamMember(
            memberId: 'member',
            reason: List.filled(301, 'a').join(),
          ),
          throwsArgumentError,
        );
        expect(service.rpcCallCount, 1);
      },
    );

    test('parses an idempotent removed=false response', () async {
      final service = _RecordingTeamService()
        ..response = {
          'ok': true,
          'removed': false,
          'team': {
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
          },
        };

      final result = await service.removeTeamMember(
        memberId: 'external-membership',
        reason: 'سبق الإخراج',
      );
      expect(result.removed, isFalse);
      expect(result.detail.team.activeMemberCount, 1);
    });

    test('rejects malformed backend responses safely', () async {
      final service = _RecordingTeamService()..response = {'ok': true};
      await expectLater(
        service.removeTeamMember(memberId: 'member', reason: 'سبب'),
        throwsStateError,
      );
    });
  });

  group('team lifecycle', () {
    test('uses archive and restore RPCs', () async {
      final service = _RecordingTeamService()
        ..response = {
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
            'is_archived': true,
          },
          'members': [],
          'can_edit': false,
          'can_manage_lifecycle': true,
          'is_member': true,
        };
      expect((await service.archiveTeam('team-1')).team.isArchived, isTrue);
      expect(service.lastRpc, 'archive_team');
      expect((await service.restoreTeam('team-1')).team.isArchived, isTrue);
      expect(service.lastRpc, 'restore_team');
    });

    test('uses permanent-removal RPC with a validated reason', () async {
      final service = _RecordingTeamService()
        ..response = {'ok': true, 'removed': false, 'blocked': true};
      final result = await service.removeTeamPermanently(
        teamId: 'team-1',
        reason: ' سبب ',
      );
      expect(service.lastRpc, 'remove_team_permanently');
      expect(service.lastParams!['p_reason'], 'سبب');
      expect(result.blocked, isTrue);
      await expectLater(
        service.removeTeamPermanently(teamId: 'team-1', reason: ' '),
        throwsArgumentError,
      );
    });
  });
}
