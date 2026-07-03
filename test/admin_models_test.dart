import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/admin/data/admin_models.dart';

void main() {
  test('admin models parse expected json', () {
    final dashboard = AdminDashboard.fromJson({
      'active_users_count': 3,
      'inactive_users_count': 1,
      'public_teams_count': 2,
      'pending_pin_reset_requests_count': 4,
    });

    expect(dashboard.activeUsersCount, 3);
    expect(dashboard.pendingPinResetRequestsCount, 4);

    final user = AdminUserDetail.fromJson({
      'id': 'u1',
      'display_name': 'Student One',
      'phone_masked': '49****35',
      'is_active': false,
      'is_admin': false,
      'created_at': '2026-07-01T10:00:00Z',
      'last_login_at': null,
      'failed_login_count': 2,
      'locked_until': '2026-07-02T10:00:00Z',
    });

    expect(user.displayName, 'Student One');
    expect(user.phoneMasked, '49****35');
    expect(user.isActive, isFalse);
    expect(user.failedLoginCount, 2);
    expect(user.lockedUntil, isNotNull);

    final team = AdminPublicTeam.fromJson({
      'id': 't1',
      'name': 'Public Team',
      'team_type': 'mahdara',
      'leader_name': 'Leader',
      'member_count': 5,
      'active_member_count': 4,
      'inactive_member_count': 1,
      'status': 'open',
      'created_at': '2026-07-01T10:00:00Z',
    });

    expect(team.name, 'Public Team');
    expect(team.memberCount, 5);
    expect(team.activeMemberCount, 4);
  });
}
