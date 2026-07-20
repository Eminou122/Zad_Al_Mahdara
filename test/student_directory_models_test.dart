import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/directory/domain/student_directory_models.dart';

void main() {
  test('parses safe teams', () {
    final r = AvailablePublicTeamsResult.fromJson({
      'items': [
        {'team_id': 't', 'name': 'فريق', 'member_count': -1},
        {'name': 'bad'},
      ],
    });
    expect(r.items, hasLength(1));
    expect(r.items.single.memberCount, 0);
  });
}
