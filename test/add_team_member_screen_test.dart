import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/utils/ltr_fragment.dart';
import 'package:zad_al_mahdara/features/teams/data/team_service.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_models.dart';
import 'package:zad_al_mahdara/features/teams/presentation/add_team_member_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

TeamMemberCandidate _candidate({
  required String profileId,
  required String displayName,
  String? phoneMasked,
  bool alreadyInCurrentTeam = false,
  String? conflictingTeamId,
  String? conflictingTeamName,
  String? conflictingTeamType,
  bool canAdd = true,
  String status = 'available',
}) =>
    TeamMemberCandidate(
      profileId: profileId,
      displayName: displayName,
      phoneMasked: phoneMasked,
      isActive: true,
      alreadyInCurrentTeam: alreadyInCurrentTeam,
      conflictingTeamId: conflictingTeamId,
      conflictingTeamName: conflictingTeamName,
      conflictingTeamType: conflictingTeamType,
      canAdd: canAdd,
      status: status,
    );

TeamDetail _dummyTeamDetail() => TeamDetail(
      team: TeamInfo(
        id: 'team-1',
        name: 'فريق الغداء',
        teamType: 'lunch',
        isPublic: true,
        status: 'open',
        leaderId: 'leader-1',
        leaderName: 'محمد',
        memberCount: 1,
        activeMemberCount: 1,
        inactiveMemberCount: 0,
        createdAt: DateTime(2026, 7, 1),
      ),
      members: const [],
      canEdit: true,
      isMember: true,
    );

class _FakeTeamService extends TeamService {
  List<TeamMemberCandidate> candidates;
  Object? error;
  int getCandidatesCallCount = 0;
  String? lastQuery;

  String? lastAddedProfileId;
  Object? addError;

  _FakeTeamService({this.candidates = const []}) : super(AuthService());

  @override
  Future<List<TeamMemberCandidate>> getTeamMemberCandidates(
    String teamId, {
    String? query,
  }) async {
    getCandidatesCallCount++;
    lastQuery = query;
    if (error != null) throw error!;
    if (query == null || query.isEmpty) return candidates;
    final q = query.toLowerCase();
    return candidates
        .where((c) => c.displayName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<TeamDetail> addTeamMember({
    required String teamId,
    required String profileId,
  }) async {
    lastAddedProfileId = profileId;
    if (addError != null) throw addError!;
    // Mimic the backend: the just-added candidate now shows as already added
    // on the next candidate fetch, same as real get_team_member_candidates
    // would report after add_team_member's insert.
    candidates = candidates
        .map((c) => c.profileId == profileId
            ? _candidate(
                profileId: c.profileId,
                displayName: c.displayName,
                phoneMasked: c.phoneMasked,
                alreadyInCurrentTeam: true,
                canAdd: false,
                status: 'already_added',
              )
            : c)
        .toList();
    return _dummyTeamDetail();
  }
}

class _FakeAuthService extends AuthService {
  @override
  String? get currentToken => 'test-token';
}

Widget _buildTest(TeamService teamService) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: AddTeamMemberScreen(
        authService: _FakeAuthService(),
        teamId: 'team-1',
        teamService: teamService,
      ),
    ),
  );
}

void main() {
  testWidgets(
      'screen initially loads and shows candidates without typing search',
      (tester) async {
    final svc = _FakeTeamService(candidates: [
      _candidate(profileId: 'p1', displayName: 'أحمد'),
      _candidate(profileId: 'p2', displayName: 'سالم'),
    ]);
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    expect(svc.getCandidatesCallCount, 1);
    expect(svc.lastQuery, isNull);
    expect(find.text('أحمد'), findsOneWidget);
    expect(find.text('سالم'), findsOneWidget);
  });

  testWidgets('search field calls candidate RPC and filters shown candidates',
      (tester) async {
    final svc = _FakeTeamService(candidates: [
      _candidate(profileId: 'p1', displayName: 'أحمد'),
      _candidate(profileId: 'p2', displayName: 'سالم'),
    ]);
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'أحمد');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(svc.lastQuery, 'أحمد');
    // "أحمد" now matches both the search field's own text and the row below
    // it, so assert the row via its type rather than a bare text lookup.
    expect(find.widgetWithText(ElevatedButton, 'إضافة'), findsOneWidget);
    expect(find.text('سالم'), findsNothing);
  });

  testWidgets('available row shows enabled إضافة button', (tester) async {
    final svc = _FakeTeamService(candidates: [
      _candidate(profileId: 'p1', displayName: 'أحمد'),
    ]);
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    final addButton = find.widgetWithText(ElevatedButton, 'إضافة');
    expect(addButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(addButton).onPressed, isNotNull);
  });

  testWidgets('tapping available row calls addTeamMember', (tester) async {
    final svc = _FakeTeamService(candidates: [
      _candidate(profileId: 'p1', displayName: 'أحمد'),
    ]);
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'إضافة'));
    await tester.pumpAndSettle();

    expect(svc.lastAddedProfileId, 'p1');
  });

  testWidgets('after successful add, candidates refresh and row becomes مضاف',
      (tester) async {
    final svc = _FakeTeamService(candidates: [
      _candidate(profileId: 'p1', displayName: 'أحمد'),
    ]);
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'إضافة'));
    await tester.pumpAndSettle();

    expect(find.text('مضاف'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'إضافة'), findsNothing);
    expect(svc.getCandidatesCallCount, 2);
  });

  testWidgets('already-added row shows مضاف and has no add control',
      (tester) async {
    final svc = _FakeTeamService(candidates: [
      _candidate(
        profileId: 'p1',
        displayName: 'أحمد',
        alreadyInCurrentTeam: true,
        canAdd: false,
        status: 'already_added',
      ),
    ]);
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    expect(find.text('مضاف'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'إضافة'), findsNothing);
    expect(svc.lastAddedProfileId, isNull);
  });

  testWidgets('conflict row shows warning and has no add control',
      (tester) async {
    final svc = _FakeTeamService(candidates: [
      _candidate(
        profileId: 'p1',
        displayName: 'أحمد',
        canAdd: false,
        status: 'conflict_same_category',
        conflictingTeamId: 'team-2',
        conflictingTeamType: 'breakfast',
      ),
    ]);
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    expect(find.text('في فريق آخر لنفس الوجبة'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'إضافة'), findsNothing);
    expect(svc.lastAddedProfileId, isNull);
  });

  testWidgets('conflict row shows conflicting team name when present',
      (tester) async {
    final svc = _FakeTeamService(candidates: [
      _candidate(
        profileId: 'p1',
        displayName: 'أحمد',
        canAdd: false,
        status: 'conflict_same_category',
        conflictingTeamId: 'team-2',
        conflictingTeamName: 'فريق الفطور',
        conflictingTeamType: 'breakfast',
      ),
    ]);
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    expect(find.text('الفريق: فريق الفطور'), findsOneWidget);
  });

  testWidgets('phone_masked is isolated with ltrFragment', (tester) async {
    final svc = _FakeTeamService(candidates: [
      _candidate(profileId: 'p1', displayName: 'أحمد', phoneMasked: '20****56'),
    ]);
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    expect(find.text(ltrFragment('20****56')), findsOneWidget);
  });

  testWidgets(
      'shows a loading indicator on first load then لا توجد حسابات متاحة for an empty default list',
      (tester) async {
    final svc = _FakeTeamService(candidates: const []);
    await tester.pumpWidget(_buildTest(svc));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.text('لا توجد حسابات متاحة'), findsOneWidget);
  });

  testWidgets('shows لا توجد نتائج when a search yields nothing',
      (tester) async {
    final svc = _FakeTeamService(candidates: [
      _candidate(profileId: 'p1', displayName: 'أحمد'),
    ]);
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'زيد');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد نتائج'), findsOneWidget);
  });
}
