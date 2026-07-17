import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/widgets/zad_scaffold.dart';
import 'package:zad_al_mahdara/features/teams/data/team_service.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_models.dart';
import 'package:zad_al_mahdara/features/teams/presentation/teams_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _FakeAuthService extends AuthService {
  @override
  String? get currentToken => 'test-token';
}

class _FakeTeamService extends TeamService {
  final List<TeamSummary> myTeams;
  final List<TeamSummary> publicTeams;
  final Object? publicError;

  _FakeTeamService({
    this.myTeams = const [],
    this.publicTeams = const [],
    this.publicError,
  }) : super(AuthService());

  @override
  Future<List<TeamSummary>> getMyTeams() async => myTeams;

  @override
  Future<List<TeamSummary>> getPublicTeams() async {
    if (publicError != null) throw publicError!;
    return publicTeams;
  }
}

TeamSummary _team({
  required String id,
  required String name,
  bool isPublic = true,
  String? myRole,
}) => TeamSummary(
  id: id,
  name: name,
  teamType: 'lunch',
  isPublic: isPublic,
  status: 'open',
  leaderName: 'محمد',
  memberCount: 1,
  activeMemberCount: 1,
  inactiveMemberCount: 0,
  myRole: myRole,
  isLeader: myRole == 'leader',
);

Widget _build(TeamService service) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: TeamsScreen(authService: _FakeAuthService(), service: service),
  ),
);

void main() {
  testWidgets('ZadScaffold refreshes short content once without hiding it', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ZadScaffold(
          title: 'اختبار',
          onRefresh: () async => calls++,
          body: const Text('محتوى موجود'),
        ),
      ),
    );

    await tester.fling(
      find.byType(SingleChildScrollView),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('محتوى موجود'), findsOneWidget);
  });

  testWidgets('shows my teams after loading', (tester) async {
    await tester.pumpWidget(
      _build(
        _FakeTeamService(
          myTeams: [_team(id: 'mine-1', name: 'فريق الغداء', myRole: 'leader')],
          publicTeams: [_team(id: 'public-1', name: 'الفريق العام')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('فريق الغداء'), findsOneWidget);
    expect(find.text('قائد'), findsOneWidget);
  });

  testWidgets('public teams failure does not hide my teams', (tester) async {
    await tester.pumpWidget(
      _build(
        _FakeTeamService(
          myTeams: [_team(id: 'mine-1', name: 'فريق الغداء', myRole: 'leader')],
          publicError: Exception('public failed'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('فريق الغداء'), findsOneWidget);
    expect(find.textContaining('public failed'), findsNothing);

    await tester.tap(find.text('الفرق العامة'));
    await tester.pumpAndSettle();

    expect(find.textContaining('public failed'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });
}
