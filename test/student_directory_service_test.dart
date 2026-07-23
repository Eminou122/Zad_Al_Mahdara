import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/directory/data/student_directory_service.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class A extends AuthService {
  @override
  String? get currentToken => 't';
}

class S extends StudentDirectoryService {
  String? n;
  Map<String, dynamic>? p;
  int contacts = 0;
  Object? error;
  S() : super(A());
  @override
  Future<dynamic> rpc(String x, Map<String, dynamic> y) async {
    n = x;
    p = y;
    if (error != null) throw error!;
    if (x == 'get_available_public_teams') return {'items': []};
    contacts++;
    return {'ok': true, 'conversation_id': 'conv-1', 'team_id': 't'};
  }
}

void main() {
  test('contact parses and reuses the returned conversation id', () async {
    final s = S();
    await s.getAvailablePublicTeams();
    expect(s.n, 'get_available_public_teams');
    final first = await s.contactAvailableTeamLeader(teamId: 't', body: ' hi ');
    expect(s.n, 'contact_available_team_leader');
    expect(s.p!['p_body'], 'hi');
    expect(first.id, 'conv-1');
    final repeated = await s.contactAvailableTeamLeader(
      teamId: 't',
      body: 'again',
    );
    expect(repeated.id, first.id);
    expect(s.contacts, 2);
  });

  test('contact rejects an invalid backend response safely', () async {
    final s = S();
    s.error = Exception('backend');
    expect(
      () => s.contactAvailableTeamLeader(teamId: 't', body: 'hi'),
      throwsA(isA<Exception>()),
    );
  });
}
