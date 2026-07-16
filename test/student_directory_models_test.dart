import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/directory/domain/student_directory_models.dart';

void main() {
  test('parses profile with public teams, contact targets, and cursor', () {
    final page = StudentDirectoryPage.fromJson({
      'items': [
        {
          'profile_id': 'profile-1',
          'display_name': 'أحمد',
          'phone_number': '22222222',
          'public_teams': [
            {
              'team_id': 'team-1',
              'team_name': 'فريق الغداء',
              'team_type': 'lunch',
              'is_current_leader': true,
              'role': 'leader',
              'leader_profile_id': 'hidden',
            },
          ],
          'contact_targets': [
            {
              'team_id': 'team-1',
              'team_name': 'فريق الغداء',
              'team_type': 'lunch',
              'label': 'مراسلة قائد الفريق',
              'recipient_profile_id': 'hidden',
            },
          ],
        },
      ],
      'has_more': true,
      'next_cursor': {'sort_name': 'أحمد', 'profile_id': 'profile-1'},
    });

    expect(page.items, hasLength(1));
    expect(page.items.first.profileId, 'profile-1');
    expect(page.items.first.displayName, 'أحمد');
    expect(page.items.first.publicTeams.single.isCurrentLeader, true);
    expect(page.items.first.publicTeams.single.role, 'leader');
    expect(page.items.first.contactTargets.single.teamId, 'team-1');
    expect(page.nextCursor!.sortName, 'أحمد');
    expect(page.nextCursor!.profileId, 'profile-1');
  });

  test('zero-team profile and null cursor parse safely', () {
    final page = StudentDirectoryPage.fromJson({
      'items': [
        {'profile_id': 'profile-2', 'display_name': 'محمد'},
      ],
      'has_more': false,
      'next_cursor': null,
    });

    expect(page.items.single.publicTeams, isEmpty);
    expect(page.items.single.contactTargets, isEmpty);
    expect(page.nextCursor, isNull);
  });

  test('invalid nested team and contact target are ignored', () {
    final entry = StudentDirectoryEntry.fromJson({
      'profile_id': 'profile-1',
      'display_name': 'أحمد',
      'public_teams': [
        {'team_id': '', 'team_name': 'bad'},
        {'team_id': 'team-1', 'team_name': 'ok'},
      ],
      'contact_targets': [
        {'team_id': 'bad', 'team_name': ''},
        {'team_id': 'team-1', 'team_name': 'ok'},
      ],
    });

    expect(entry.publicTeams, hasLength(1));
    expect(entry.contactTargets, hasLength(1));
  });

  test('malformed item is ignored and missing display name is safe', () {
    final page = StudentDirectoryPage.fromJson({
      'items': [
        'bad',
        {'profile_id': 'profile-1'},
        {'display_name': 'missing id'},
      ],
      'has_more': false,
    });

    expect(page.items, hasLength(1));
    expect(page.items.single.displayName, '');
  });
}
