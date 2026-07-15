import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/messaging/data/team_messaging_service.dart';
import 'package:zad_al_mahdara/features/messaging/domain/team_messaging_models.dart';
import 'package:zad_al_mahdara/features/messaging/presentation/messaging_home_screen.dart';
import 'package:zad_al_mahdara/features/teams/data/team_service.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_models.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _FakeAuthService extends AuthService {
  @override
  String? get currentToken => 'test-token';
}

TeamConversationSummary _conversation(
  String id, {
  int unread = 0,
  String role = 'member',
}) => TeamConversationSummary(
  id: id,
  teamId: 'team-$id',
  teamName: 'فريق $id',
  memberProfileId: 'member-$id',
  memberName: 'أحمد $id',
  latestMessagePreview: 'رسالة $id',
  latestMessageAt: DateTime(2026, 7, 13, 10),
  unreadCount: unread,
  currentUserRole: role,
);

TeamAnnouncement _announcement(String id) => TeamAnnouncement(
  id: id,
  teamId: 'team-1',
  teamName: 'فريق الغداء',
  authorProfileId: 'leader-1',
  authorName: 'القائد',
  title: 'إعلان $id',
  body: 'نص الإعلان $id',
  createdAt: DateTime(2026, 7, 13, 10),
  isRead: false,
);

class _FakeMessagingService extends TeamMessagingService {
  List<TeamConversationSummary> first = [];
  List<TeamConversationSummary> second = [];
  bool firstHasMore = false;
  TeamConversationCursor? firstCursor;
  int conversationCalls = 0;
  TeamConversationCursor? lastBefore;

  _FakeMessagingService() : super(AuthService());

  @override
  Future<TeamConversationsPage> getMyTeamConversations({
    int limit = 30,
    TeamConversationCursor? before,
    bool unreadOnly = false,
  }) async {
    conversationCalls++;
    lastBefore = before;
    if (before != null) {
      return TeamConversationsPage(items: second, hasMore: false);
    }
    return TeamConversationsPage(
      items: first,
      hasMore: firstHasMore,
      nextCursor: firstCursor,
    );
  }

  @override
  Future<TeamAnnouncementsPage> getMyTeamAnnouncements({
    String? teamId,
    int limit = 30,
    TeamAnnouncementCursor? before,
    bool unreadOnly = false,
  }) async =>
      TeamAnnouncementsPage(items: [_announcement('1')], hasMore: false);
}

class _FakeTeamService extends TeamService {
  final bool leader;
  _FakeTeamService({this.leader = false}) : super(AuthService());

  @override
  Future<List<TeamSummary>> getMyTeams() async => [
    TeamSummary(
      id: 'team-1',
      name: 'فريق الغداء',
      teamType: 'lunch',
      isPublic: true,
      status: 'open',
      leaderName: 'القائد',
      memberCount: 1,
      activeMemberCount: 1,
      inactiveMemberCount: 0,
      isLeader: leader,
    ),
  ];
}

Widget _wrap(_FakeMessagingService service, {bool leader = false}) =>
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MessagingHomeScreen(
          authService: _FakeAuthService(),
          service: service,
          teamService: _FakeTeamService(leader: leader),
        ),
      ),
    );

void main() {
  testWidgets('shows tabs and member empty state', (tester) async {
    await tester.pumpWidget(_wrap(_FakeMessagingService()));
    await tester.pumpAndSettle();

    expect(find.text('المحادثات'), findsOneWidget);
    expect(find.text('الإعلانات'), findsWidgets);
    expect(find.text('لا توجد محادثات حتى الآن'), findsOneWidget);
    expect(find.text('يمكنك مراسلة قائد فريقك من صفحة الفريق'), findsOneWidget);
  });

  testWidgets('leader empty state uses leader copy', (tester) async {
    await tester.pumpWidget(_wrap(_FakeMessagingService(), leader: true));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد رسائل من أعضاء الفريق'), findsOneWidget);
  });

  testWidgets('renders conversations with unread badge', (tester) async {
    final service = _FakeMessagingService()
      ..first = [_conversation('1', unread: 3, role: 'leader')];
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('أحمد 1'), findsOneWidget);
    expect(find.text('فريق 1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('load more sends compound cursor and drops duplicate ids', (
    tester,
  ) async {
    final cursor = TeamConversationCursor(
      updatedAt: DateTime.utc(2026, 7, 13, 9),
      id: '1',
    );
    final service = _FakeMessagingService()
      ..first = List.generate(20, (i) => _conversation('$i'))
      ..second = [_conversation('19'), _conversation('20')]
      ..firstHasMore = true
      ..firstCursor = cursor;

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, -4000), 4000);
    await tester.pumpAndSettle();

    expect(service.lastBefore, cursor);
    expect(find.text('فريق 19'), findsOneWidget);
    expect(find.text('فريق 20'), findsOneWidget);
  });

  testWidgets('renders at 320px without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakeMessagingService()..first = [_conversation('1')];
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
