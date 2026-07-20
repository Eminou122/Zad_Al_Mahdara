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
  S() : super(A());
  @override
  Future<dynamic> rpc(String x, Map<String, dynamic> y) async {
    n = x;
    p = y;
    return x == 'get_available_public_teams' ? {'items': []} : {'ok': true};
  }
}

void main() {
  test('uses new RPCs', () async {
    final s = S();
    await s.getAvailablePublicTeams();
    expect(s.n, 'get_available_public_teams');
    await s.contactAvailableTeamLeader(teamId: 't', body: ' hi ');
    expect(s.n, 'contact_available_team_leader');
    expect(s.p!['p_body'], 'hi');
  });
}
