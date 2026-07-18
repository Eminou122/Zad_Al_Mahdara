import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/utils/ltr_fragment.dart';
import 'package:zad_al_mahdara/core/widgets/mauritanian_phone_field.dart';
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
}) => TeamMemberCandidate(
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
  String? lastExternalName;
  String? lastExternalPhone;
  Object? externalError;
  int externalAddCallCount = 0;

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
        .map(
          (c) => c.profileId == profileId
              ? _candidate(
                  profileId: c.profileId,
                  displayName: c.displayName,
                  phoneMasked: c.phoneMasked,
                  alreadyInCurrentTeam: true,
                  canAdd: false,
                  status: 'already_added',
                )
              : c,
        )
        .toList();
    return _dummyTeamDetail();
  }

  @override
  Future<TeamDetail> upsertExternalStudentAndAddToTeam({
    required String teamId,
    required String displayName,
    required String phoneNumber,
  }) async {
    externalAddCallCount++;
    lastExternalName = displayName;
    lastExternalPhone = phoneNumber;
    if (externalError != null) throw externalError!;
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

Future<void> _openExternalForm(WidgetTester tester) async {
  await tester.tap(find.text('إضافة طالب بدون حساب').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'screen initially loads and shows candidates without typing search',
    (tester) async {
      final svc = _FakeTeamService(
        candidates: [
          _candidate(profileId: 'p1', displayName: 'أحمد'),
          _candidate(profileId: 'p2', displayName: 'سالم'),
        ],
      );
      await tester.pumpWidget(_buildTest(svc));
      await tester.pumpAndSettle();

      expect(svc.getCandidatesCallCount, 1);
      expect(svc.lastQuery, isNull);
      expect(find.text('أحمد'), findsOneWidget);
      expect(find.text('سالم'), findsOneWidget);
    },
  );

  testWidgets('search field calls candidate RPC and filters shown candidates', (
    tester,
  ) async {
    final svc = _FakeTeamService(
      candidates: [
        _candidate(profileId: 'p1', displayName: 'أحمد'),
        _candidate(profileId: 'p2', displayName: 'سالم'),
      ],
    );
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
    final svc = _FakeTeamService(
      candidates: [_candidate(profileId: 'p1', displayName: 'أحمد')],
    );
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    final addButton = find.widgetWithText(ElevatedButton, 'إضافة');
    expect(addButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(addButton).onPressed, isNotNull);
  });

  testWidgets('tapping available row calls addTeamMember', (tester) async {
    final svc = _FakeTeamService(
      candidates: [_candidate(profileId: 'p1', displayName: 'أحمد')],
    );
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'إضافة'));
    await tester.pumpAndSettle();

    expect(svc.lastAddedProfileId, 'p1');
  });

  testWidgets('after successful add, candidates refresh and row becomes مضاف', (
    tester,
  ) async {
    final svc = _FakeTeamService(
      candidates: [_candidate(profileId: 'p1', displayName: 'أحمد')],
    );
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'إضافة'));
    await tester.pumpAndSettle();

    expect(find.text('مضاف'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'إضافة'), findsNothing);
    expect(svc.getCandidatesCallCount, 2);
  });

  testWidgets('already-added row shows مضاف and has no add control', (
    tester,
  ) async {
    final svc = _FakeTeamService(
      candidates: [
        _candidate(
          profileId: 'p1',
          displayName: 'أحمد',
          alreadyInCurrentTeam: true,
          canAdd: false,
          status: 'already_added',
        ),
      ],
    );
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    expect(find.text('مضاف'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'إضافة'), findsNothing);
    expect(svc.lastAddedProfileId, isNull);
  });

  testWidgets('conflict row shows warning and has no add control', (
    tester,
  ) async {
    final svc = _FakeTeamService(
      candidates: [
        _candidate(
          profileId: 'p1',
          displayName: 'أحمد',
          canAdd: false,
          status: 'conflict_same_category',
          conflictingTeamId: 'team-2',
          conflictingTeamType: 'breakfast',
        ),
      ],
    );
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    expect(find.text('في فريق آخر لنفس الوجبة'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'إضافة'), findsNothing);
    expect(svc.lastAddedProfileId, isNull);
  });

  testWidgets('conflict row shows conflicting team name when present', (
    tester,
  ) async {
    final svc = _FakeTeamService(
      candidates: [
        _candidate(
          profileId: 'p1',
          displayName: 'أحمد',
          canAdd: false,
          status: 'conflict_same_category',
          conflictingTeamId: 'team-2',
          conflictingTeamName: 'فريق الفطور',
          conflictingTeamType: 'breakfast',
        ),
      ],
    );
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    expect(find.text('الفريق: فريق الفطور'), findsOneWidget);
  });

  testWidgets('phone_masked is isolated with ltrFragment', (tester) async {
    final svc = _FakeTeamService(
      candidates: [
        _candidate(
          profileId: 'p1',
          displayName: 'أحمد',
          phoneMasked: '20****56',
        ),
      ],
    );
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    expect(find.text(ltrFragment('20****56')), findsOneWidget);
  });

  testWidgets('does not overflow at 320px width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final svc = _FakeTeamService(
      candidates: [
        _candidate(
          profileId: 'p1',
          displayName: 'طالب باسم طويل للفحص',
          phoneMasked: '20****56',
        ),
      ],
    );
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('طالب باسم طويل للفحص'), findsOneWidget);
  });

  testWidgets('external phone uses the shared LTR phone field', (tester) async {
    final svc = _FakeTeamService();
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();
    await _openExternalForm(tester);

    final phone = find.descendant(
      of: find.byType(MauritanianPhoneField),
      matching: find.byType(TextField),
    );
    expect(phone, findsOneWidget);
    expect(tester.widget<TextField>(phone).textDirection, TextDirection.ltr);
    expect(
      tester
          .widget<Directionality>(find.byType(Directionality).last)
          .textDirection,
      TextDirection.rtl,
    );
  });

  testWidgets('external phone formats raw, spaced, and hyphenated input', (
    tester,
  ) async {
    final svc = _FakeTeamService();
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();
    await _openExternalForm(tester);
    final phone = find.descendant(
      of: find.byType(MauritanianPhoneField),
      matching: find.byType(TextField),
    );

    await tester.enterText(phone, '123456789');
    expect(tester.widget<TextField>(phone).controller!.text, '12 34 56 78');
    await tester.enterText(phone, '12 34 56 78');
    expect(tester.widget<TextField>(phone).controller!.text, '12 34 56 78');
    await tester.enterText(phone, '12-34-56-78');
    expect(tester.widget<TextField>(phone).controller!.text, '12 34 56 78');
  });

  testWidgets('invalid external phone blocks submission with shared message', (
    tester,
  ) async {
    final svc = _FakeTeamService();
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();
    await _openExternalForm(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'طالب');
    await tester.enterText(fields.at(2), '1234567');
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'إضافة طالب بدون حساب'),
    );
    await tester.pump();

    expect(svc.externalAddCallCount, 0);
    expect(find.text('أدخل رقم هاتف صحيحًا مكونًا من 8 أرقام'), findsOneWidget);
    expect(
      tester.widget<TextField>(fields.at(2)).controller!.text,
      '12 34 56 7',
    );
  });

  testWidgets(
    'external add sends normalized digits and keeps form on failure',
    (tester) async {
      final svc = _FakeTeamService()..externalError = Exception('failed');
      await tester.pumpWidget(_buildTest(svc));
      await tester.pumpAndSettle();
      await _openExternalForm(tester);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), 'طالب');
      await tester.enterText(fields.at(2), '12-34-56-78');
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'إضافة طالب بدون حساب'),
      );
      await tester.pumpAndSettle();

      expect(svc.lastExternalPhone, '12345678');
      expect(svc.lastExternalName, 'طالب');
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, 'طالب');
      expect(
        tester.widget<TextField>(fields.at(2)).controller!.text,
        '12 34 56 78',
      );
    },
  );

  testWidgets('successful external add clears the existing form', (
    tester,
  ) async {
    final svc = _FakeTeamService();
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();
    await _openExternalForm(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'طالب');
    await tester.enterText(fields.at(2), '12345678');
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'إضافة طالب بدون حساب'),
    );
    await tester.pumpAndSettle();

    expect(svc.externalAddCallCount, 1);
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, isEmpty);
    expect(tester.widget<TextField>(fields.at(2)).controller!.text, isEmpty);
  });

  testWidgets('candidate refresh preserves entered external phone', (
    tester,
  ) async {
    final svc = _FakeTeamService();
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();
    await _openExternalForm(tester);
    final phone = find.descendant(
      of: find.byType(MauritanianPhoneField),
      matching: find.byType(TextField),
    );
    await tester.enterText(phone, '12345678');

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(phone).controller!.text, '12 34 56 78');
  });

  testWidgets('duplicate external submit creates one service call', (
    tester,
  ) async {
    final svc = _FakeTeamService();
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();
    await _openExternalForm(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'طالب');
    await tester.enterText(fields.at(2), '12345678');
    final button = find.widgetWithText(ElevatedButton, 'إضافة طالب بدون حساب');
    await tester.tap(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(svc.externalAddCallCount, 1);
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
    },
  );

  testWidgets('shows لا توجد نتائج when a search yields nothing', (
    tester,
  ) async {
    final svc = _FakeTeamService(
      candidates: [_candidate(profileId: 'p1', displayName: 'أحمد')],
    );
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'زيد');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد نتائج'), findsOneWidget);
  });
}
