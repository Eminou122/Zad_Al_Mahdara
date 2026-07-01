import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_models.dart';

void main() {
  group('TeamSummary.fromJson', () {
    test('parses my-team entry', () {
      final t = TeamSummary.fromJson({
        'id': 'abc',
        'name': 'الغداء الكبير',
        'team_type': 'lunch',
        'is_public': true,
        'status': 'open',
        'leader_name': 'محمد',
        'member_count': 5,
        'active_member_count': 3,
        'inactive_member_count': 2,
        'my_role': 'member',
        'is_leader': false,
      });
      expect(t.name, 'الغداء الكبير');
      expect(t.memberCount, 5);
      expect(t.activeMemberCount, 3);
      expect(t.inactiveMemberCount, 2);
      expect(t.isLeader, false);
    });

    test('parses public entry without my_role', () {
      final t = TeamSummary.fromJson({
        'id': 'xyz',
        'name': 'فريق الشاي',
        'team_type': 'tea',
        'status': 'open',
        'leader_name': 'فاطمة',
        'member_count': 3,
      });
      expect(t.myRole, isNull);
      expect(t.isPublic, true);
    });
  });

  group('TeamDetail.fromJson', () {
    test('parses full detail with members', () {
      final d = TeamDetail.fromJson({
        'team': {
          'id': 't1',
          'name': 'فريق العشاء',
          'team_type': 'dinner',
          'is_public': false,
          'status': 'closed',
          'leader_id': 'p1',
          'leader_name': 'أحمد',
          'member_count': 2,
          'active_member_count': 1,
          'inactive_member_count': 1,
          'created_at': '2026-01-15T10:00:00Z',
        },
        'members': [
          {
            'member_id': 'm1',
            'profile_id': 'p1',
            'display_name': 'أحمد',
            'role': 'leader',
            'position': 1,
            'is_active': true,
            'joined_at': '2026-01-15T10:00:00Z',
          },
        ],
        'can_edit': true,
        'is_member': true,
      });
      expect(d.team.name, 'فريق العشاء');
      expect(d.team.memberCount, 2);
      expect(d.team.activeMemberCount, 1);
      expect(d.team.inactiveMemberCount, 1);
      expect(d.members.length, 1);
      expect(d.members.first.role, 'leader');
      expect(d.members.first.isActive, true);
      expect(d.canEdit, true);
    });

    test('parses public non-member view with empty members', () {
      final d = TeamDetail.fromJson({
        'team': {
          'id': 't2',
          'name': 'فريق مفتوح',
          'team_type': 'breakfast',
          'is_public': true,
          'status': 'open',
          'leader_id': 'p2',
          'leader_name': 'خديجة',
          'member_count': 10,
          'created_at': '2026-02-01T08:00:00Z',
        },
        'members': [],
        'can_edit': false,
        'is_member': false,
      });
      expect(d.members, isEmpty);
      expect(d.isMember, false);
    });
  });

  group('TeamMember.fromJson', () {
    test('parses is_active false for a deactivated member', () {
      final m = TeamMember.fromJson({
        'member_id': 'm2',
        'profile_id': 'p2',
        'display_name': 'يوسف',
        'role': 'member',
        'position': 2,
        'is_active': false,
        'joined_at': '2026-01-15T10:00:00Z',
      });
      expect(m.isActive, false);
    });

    test('defaults is_active to true when field is missing', () {
      final m = TeamMember.fromJson({
        'member_id': 'm3',
        'profile_id': 'p3',
        'display_name': 'مريم',
        'role': 'member',
        'position': 3,
        'joined_at': '2026-01-15T10:00:00Z',
      });
      expect(m.isActive, true);
    });
  });

  group('StudentResult.fromJson', () {
    test('parses search result', () {
      final s = StudentResult.fromJson({
        'profile_id': 'p3',
        'display_name': 'عمر',
        'phone_masked': '4941****',
      });
      expect(s.displayName, 'عمر');
      expect(s.phoneMasked, '4941****');
    });
  });
}
