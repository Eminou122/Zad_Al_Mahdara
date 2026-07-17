import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/refresh/app_refresh_coordinator.dart';
import 'package:zad_al_mahdara/core/theme/zad_tokens.dart';
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
  String? preview,
  DateTime? latestAt,
}) => TeamConversationSummary(
  id: id,
  teamId: 'team-$id',
  teamName: 'فريق $id',
  memberProfileId: 'member-$id',
  memberName: 'أحمد $id',
  latestMessagePreview: preview ?? 'رسالة $id',
  latestMessageAt: latestAt ?? DateTime(2026, 7, 13, 10),
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

Widget _wrap(
  _FakeMessagingService service, {
  bool leader = false,
  Duration inboxRefreshInterval = const Duration(seconds: 10),
}) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: MessagingHomeScreen(
      authService: _FakeAuthService(),
      service: service,
      teamService: _FakeTeamService(leader: leader),
      inboxRefreshInterval: inboxRefreshInterval,
    ),
  ),
);

void main() {
  setUp(AppRefreshCoordinator.instance.resetForTesting);
  tearDown(AppRefreshCoordinator.instance.resetForTesting);

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

  testWidgets('initially shows المحادثات (page 0)', (tester) async {
    await tester.pumpWidget(_wrap(_FakeMessagingService()));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد محادثات حتى الآن'), findsOneWidget);
    expect(find.text('لا توجد إعلانات للفريق'), findsNothing);
  });

  testWidgets('tapping الإعلانات changes the visible page', (tester) async {
    await tester.pumpWidget(_wrap(_FakeMessagingService()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('الإعلانات').first);
    await tester.pumpAndSettle();

    expect(find.text('نص الإعلان 1'), findsOneWidget);
    expect(find.text('لا توجد محادثات حتى الآن'), findsNothing);

    // Tapping back returns to المحادثات.
    await tester.tap(find.text('المحادثات').first);
    await tester.pumpAndSettle();
    expect(find.text('لا توجد محادثات حتى الآن'), findsOneWidget);
  });

  testWidgets('horizontal swipe changes to الإعلانات and reverse swipe '
      'returns to المحادثات', (tester) async {
    await tester.pumpWidget(_wrap(_FakeMessagingService()));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('نص الإعلان 1'), findsOneWidget);
    expect(find.text('لا توجد محادثات حتى الآن'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد محادثات حتى الآن'), findsOneWidget);
  });

  testWidgets('selected tab style stays in sync with the visible page', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_FakeMessagingService()));
    await tester.pumpAndSettle();

    Color? colorOf(String label) =>
        tester.widget<Text>(find.text(label).first).style?.color;

    expect(colorOf('المحادثات'), Colors.white);
    expect(colorOf('الإعلانات'), ZadTokens.textMuted);

    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(colorOf('المحادثات'), ZadTokens.textMuted);
    expect(colorOf('الإعلانات'), Colors.white);
  });

  testWidgets('pull-to-refresh on المحادثات still works', (tester) async {
    final service = _FakeMessagingService()..first = [_conversation('1')];
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();
    final callsBefore = service.conversationCalls;

    // Same downward-fling gesture used elsewhere in this suite to trigger
    // RefreshIndicator's onRefresh.
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(service.conversationCalls, greaterThan(callsBefore));
  });

  testWidgets('silent inbox refresh updates preview and unread count', (
    tester,
  ) async {
    final service = _FakeMessagingService()
      ..first = [_conversation('1', unread: 0)];
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('0'), findsNothing);
    service.first = [_conversation('1', unread: 4)];
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();

    expect(find.text('4'), findsOneWidget);
    expect(find.text('المحادثات'), findsOneWidget);
  });

  testWidgets(
    'cached messages root entry refreshes conversations immediately',
    (tester) async {
      final service = _FakeMessagingService()
        ..first = [_conversation('1', unread: 0, preview: 'قديم')];
      await tester.pumpWidget(_wrap(service));
      await tester.pumpAndSettle();

      service.first = [
        _conversation(
          '1',
          unread: 5,
          preview: 'جديد',
          latestAt: DateTime(2026, 7, 13, 11),
        ),
      ];
      AppRefreshCoordinator.instance.notifyRootRouteVisible('/messages');
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('جديد'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('قديم'), findsNothing);
    },
  );

  testWidgets('messages invalidation keeps selected announcements tab', (
    tester,
  ) async {
    final service = _FakeMessagingService()
      ..first = [_conversation('1', unread: 0)];
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الإعلانات').first);
    await tester.pumpAndSettle();

    AppRefreshCoordinator.instance.notifyRootRouteVisible('/messages');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('نص الإعلان 1'), findsOneWidget);
    expect(find.text('لا توجد محادثات حتى الآن'), findsNothing);
  });
}
