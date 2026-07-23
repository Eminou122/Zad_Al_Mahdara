import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zad_al_mahdara/core/widgets/mauritanian_phone_field.dart';
import 'package:zad_al_mahdara/features/teams/data/team_service.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_models.dart';
import 'package:zad_al_mahdara/features/teams/presentation/team_form_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _FakeAuthService extends AuthService {
  @override
  String? get currentToken => 'test-token';

  @override
  UserProfile? get profile => const UserProfile(
    id: 'p1',
    displayName: 'محمد',
    phoneMasked: '22****88',
    isAdmin: false,
    isActive: true,
  );
}

class _FakeTeamService extends TeamService {
  List<StudentResult> searchResults;
  List<Map<String, dynamic>>? submittedMembers;
  Object? createError;

  _FakeTeamService({this.searchResults = const []}) : super(AuthService());

  @override
  Future<List<StudentResult>> searchStudents(String query) async =>
      searchResults;

  @override
  Future<TeamDetail> createTeamWithMembers({
    required String name,
    required String teamType,
    required bool isPublic,
    required String status,
    String? note,
    required List<Map<String, dynamic>> members,
  }) async {
    if (createError != null) throw createError!;
    submittedMembers = members;
    return TeamDetail(
      team: TeamInfo(
        id: 'team-1',
        name: name,
        teamType: teamType,
        isPublic: isPublic,
        status: status,
        leaderId: 'leader-1',
        leaderName: 'محمد',
        memberCount: members.length,
        activeMemberCount: members.length,
        inactiveMemberCount: 0,
        createdAt: DateTime(2026, 7, 1),
      ),
      members: const [],
      canEdit: true,
      isMember: true,
    );
  }
}

Widget _buildTest(TeamService svc) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: TeamFormScreen(authService: _FakeAuthService(), teamService: svc),
    ),
  ),
);

/// Wraps the form behind a GoRouter route so `context.pop(true)` on
/// successful save has somewhere to pop to (mirrors budget_form_return_test).
Future<Completer<Object?>> _runFormInRouter(
  WidgetTester tester,
  TeamService svc,
) async {
  final result = Completer<Object?>();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: ElevatedButton(
            onPressed: () async => result.complete(await context.push('/form')),
            child: const Text('open'),
          ),
        ),
      ),
      GoRoute(
        path: '/form',
        builder: (context, state) =>
            TeamFormScreen(authService: _FakeAuthService(), teamService: svc),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _addManualMember(
  WidgetTester tester,
  String name,
  String phone,
) async {
  await tester.enterText(find.byKey(const Key('team-form-manual-name')), name);
  final phoneField = find.descendant(
    of: find.byType(MauritanianPhoneField),
    matching: find.byType(TextField),
  );
  await tester.enterText(phoneField, phone);
  await _tapVisible(
    tester,
    find.widgetWithText(OutlinedButton, 'إضافة عضو يدوياً'),
  );
}

void main() {
  testWidgets('creator appears automatically as the first member', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTest(_FakeTeamService()));
    await tester.pumpAndSettle();

    expect(find.text('محمد'), findsOneWidget);
    expect(find.textContaining('أنت (المنشئ)'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('creator can move away from position 1', (tester) async {
    final svc = _FakeTeamService();
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();
    await _addManualMember(tester, 'زيد', '12345678');

    final creatorYBefore = tester.getTopLeft(find.text('محمد')).dy;
    final otherYBefore = tester.getTopLeft(find.text('زيد')).dy;
    expect(creatorYBefore, lessThan(otherYBefore));

    // The creator's row is first, so its "خفض" (move down) button is the
    // first one in the tree.
    await _tapVisible(tester, find.byTooltip('خفض'));

    final creatorYAfter = tester.getTopLeft(find.text('محمد')).dy;
    final otherYAfter = tester.getTopLeft(find.text('زيد')).dy;
    expect(creatorYAfter, greaterThan(otherYAfter));
  });

  testWidgets('registered member can be added through search', (tester) async {
    final svc = _FakeTeamService(
      searchResults: const [
        StudentResult(
          profileId: 'p9',
          displayName: 'سالم',
          phoneMasked: '20****56',
        ),
      ],
    );
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('team-form-member-search')),
      'سالم',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.widgetWithText(TextButton, 'إضافة'));

    expect(
      find.descendant(
        of: find.byKey(const Key('team-form-member-list')),
        matching: find.text('سالم'),
      ),
      findsOneWidget,
    );
    expect(find.text('مضاف'), findsOneWidget);
  });

  testWidgets('duplicate registered member is blocked', (tester) async {
    final svc = _FakeTeamService(
      searchResults: const [
        StudentResult(
          profileId: 'p9',
          displayName: 'سالم',
          phoneMasked: '20****56',
        ),
      ],
    );
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('team-form-member-search')),
      'سالم',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.widgetWithText(TextButton, 'إضافة'));

    // The add control is replaced by "مضاف" once already added, so a
    // second add cannot be triggered through the UI.
    expect(find.widgetWithText(TextButton, 'إضافة'), findsNothing);
    expect(find.text('مضاف'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('team-form-member-list')),
        matching: find.text('سالم'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('manual member can be added with name and phone', (tester) async {
    final svc = _FakeTeamService();
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();

    await _addManualMember(tester, 'زيد', '12345678');

    expect(find.text('زيد'), findsOneWidget);
    expect(find.textContaining('بدون حساب'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('team-form-manual-name')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('removing a member compacts displayed positions', (tester) async {
    final svc = _FakeTeamService();
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();
    await _addManualMember(tester, 'زيد', '12345678');
    await _addManualMember(tester, 'سعيد', '87654321');

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // Remove the middle row ("زيد", position 2).
    await _tapVisible(tester, find.byTooltip('إزالة'));

    expect(find.text('زيد'), findsNothing);
    expect(find.text('سعيد'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('save submits members in the exact displayed order', (
    tester,
  ) async {
    final svc = _FakeTeamService(
      searchResults: const [
        StudentResult(
          profileId: 'p9',
          displayName: 'سالم',
          phoneMasked: '20****56',
        ),
      ],
    );
    final result = await _runFormInRouter(tester, svc);

    await tester.enterText(find.byType(TextField).first, 'فريق الفحص');
    await _addManualMember(tester, 'زيد', '12345678');
    await tester.enterText(
      find.byKey(const Key('team-form-member-search')),
      'سالم',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.widgetWithText(TextButton, 'إضافة'));

    // Displayed order so far: leader(محمد), manual(زيد), account(سالم).
    // Move the leader down one so the submitted order is no longer default.
    await _tapVisible(tester, find.byTooltip('خفض'));

    await _tapVisible(tester, find.widgetWithText(ElevatedButton, 'حفظ'));

    await result.future;
    expect(svc.submittedMembers, isNotNull);
    expect(svc.submittedMembers!.map((m) => m['kind']).toList(), [
      'manual',
      'leader',
      'account',
    ]);
    expect(svc.submittedMembers![0]['name'], 'زيد');
    expect(svc.submittedMembers![2]['profile_id'], 'p9');
  });

  testWidgets('does not overflow at 320px RTL width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final svc = _FakeTeamService();
    await tester.pumpWidget(_buildTest(svc));
    await tester.pumpAndSettle();
    await _addManualMember(
      tester,
      'عضو باسم طويل جداً للفحص الحدي',
      '12345678',
    );

    expect(tester.takeException(), isNull);
    expect(find.text('عضو باسم طويل جداً للفحص الحدي'), findsOneWidget);
  });
}
