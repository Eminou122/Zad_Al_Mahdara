import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:zad_al_mahdara/features/directory/presentation/student_directory_screen.dart';
import 'package:zad_al_mahdara/features/directory/data/student_directory_service.dart';
import 'package:zad_al_mahdara/features/directory/domain/student_directory_models.dart';
import 'package:zad_al_mahdara/features/messaging/domain/team_messaging_models.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class A extends AuthService {
  @override
  String? get currentToken => 't';
}

class S extends StudentDirectoryService {
  final AvailablePublicTeamsResult r;
  Object? contactError;
  int contactCalls = 0;
  S(this.r) : super(A());
  @override
  Future<AvailablePublicTeamsResult> getAvailablePublicTeams() async => r;
  @override
  Future<TeamConversationRef> contactAvailableTeamLeader({
    required String teamId,
    required String body,
  }) async {
    contactCalls++;
    if (contactError != null) throw contactError!;
    return TeamConversationRef(
      id: 'conv-7',
      teamId: teamId,
      memberProfileId: '',
    );
  }
}

Widget wrap(AvailablePublicTeam t) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: StudentDirectoryScreen(
      authService: A(),
      service: S(AvailablePublicTeamsResult([t])),
    ),
  ),
);
void main() {
  testWidgets('renders team and non-member contact', (t) async {
    await t.pumpWidget(
      wrap(
        const AvailablePublicTeam(
          teamId: 't',
          name: 'فريق',
          teamType: 'lunch',
          note: null,
          leaderDisplayName: null,
          memberCount: 3,
          isCurrentMember: false,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('الفرق المتاحة'), findsOneWidget);
    expect(find.text('عدد الأعضاء: 3'), findsOneWidget);
    expect(find.text('تواصل مع مسؤول المجموعة'), findsOneWidget);
  });
  testWidgets('hides contact for current member', (t) async {
    await t.pumpWidget(
      wrap(
        const AvailablePublicTeam(
          teamId: 't',
          name: 'فريق',
          teamType: 'lunch',
          note: null,
          leaderDisplayName: null,
          memberCount: 1,
          isCurrentMember: true,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('أنت عضو في هذه المجموعة'), findsOneWidget);
    expect(find.text('تواصل مع مسؤول المجموعة'), findsNothing);
  });

  testWidgets(
    'contact opens the exact returned conversation without overflow',
    (t) async {
      const team = AvailablePublicTeam(
        teamId: 't',
        name: 'فريق طويل للاختبار',
        teamType: 'lunch',
        note: null,
        leaderDisplayName: null,
        memberCount: 3,
        isCurrentMember: false,
      );
      final s = S(const AvailablePublicTeamsResult([team]));
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => Directionality(
              textDirection: TextDirection.rtl,
              child: StudentDirectoryScreen(authService: A(), service: s),
            ),
          ),
          GoRoute(
            path: '/messages/conversation/:id',
        builder: (context, state) => Text('thread-${state.pathParameters['id']}'),
          ),
        ],
      );
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await t.pumpAndSettle();
      await t.tap(find.text('تواصل مع مسؤول المجموعة'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'رسالة');
      await t.tap(find.text('إرسال'));
      await t.pumpAndSettle();
      expect(find.text('thread-conv-7'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('contact backend errors are shown safely', (t) async {
    const team = AvailablePublicTeam(
      teamId: 't',
      name: 'فريق',
      teamType: 'lunch',
      note: null,
      leaderDisplayName: null,
      memberCount: 3,
      isCurrentMember: false,
    );
    final s = S(const AvailablePublicTeamsResult([team]))
      ..contactError = Exception('backend');
    await t.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: StudentDirectoryScreen(authService: A(), service: s),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('تواصل مع مسؤول المجموعة'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'رسالة');
    await t.tap(find.text('إرسال'));
    await t.pump();
    expect(find.text('تعذر إرسال الرسالة، حاول مرة أخرى'), findsOneWidget);
  });
}
