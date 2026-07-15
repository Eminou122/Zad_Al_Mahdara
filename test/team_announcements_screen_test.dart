import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zad_al_mahdara/features/messaging/data/team_messaging_service.dart';
import 'package:zad_al_mahdara/features/messaging/domain/team_messaging_models.dart';
import 'package:zad_al_mahdara/features/messaging/presentation/compose_team_announcement_screen.dart';
import 'package:zad_al_mahdara/features/messaging/presentation/team_announcements_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _FakeAuthService extends AuthService {
  @override
  String? get currentToken => 'test-token';
}

TeamAnnouncement _announcement(String id, {bool read = false, DateTime? at}) =>
    TeamAnnouncement(
      id: id,
      teamId: 'team-1',
      teamName: 'فريق الغداء',
      authorProfileId: 'leader-1',
      authorName: 'القائد',
      title: 'إعلان $id',
      body: 'نص الإعلان $id',
      createdAt: at ?? DateTime(2026, 7, 13, 10),
      isRead: read,
    );

class _FakeMessagingService extends TeamMessagingService {
  List<TeamAnnouncement> first = [];
  List<TeamAnnouncement> second = [];
  bool firstHasMore = false;
  TeamAnnouncementCursor? firstCursor;
  Object? loadError;
  int readCalls = 0;
  int createCalls = 0;
  String? lastTeamId;
  String? lastTitle;
  String? lastBody;
  TeamAnnouncementCursor? lastBefore;

  _FakeMessagingService() : super(AuthService());

  @override
  Future<TeamAnnouncementsPage> getMyTeamAnnouncements({
    String? teamId,
    int limit = 30,
    TeamAnnouncementCursor? before,
    bool unreadOnly = false,
  }) async {
    lastTeamId = teamId;
    lastBefore = before;
    if (loadError != null) throw loadError!;
    if (before != null) {
      return TeamAnnouncementsPage(items: second, hasMore: false);
    }
    return TeamAnnouncementsPage(
      items: first,
      hasMore: firstHasMore,
      nextCursor: firstCursor,
    );
  }

  @override
  Future<void> markAnnouncementRead(String announcementId) async {
    readCalls++;
  }

  @override
  Future<TeamAnnouncement> createTeamAnnouncement({
    required String teamId,
    required String body,
    String? title,
  }) async {
    createCalls++;
    lastTeamId = teamId;
    lastTitle = title;
    lastBody = body;
    return _announcement('created', read: true);
  }
}

Widget _listApp(_FakeMessagingService service, {bool leader = false}) =>
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: TeamAnnouncementsScreen(
          authService: _FakeAuthService(),
          teamId: 'team-1',
          teamName: 'فريق الغداء',
          isLeader: leader,
          service: service,
        ),
      ),
    );

Widget _composeApp(_FakeMessagingService service) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: ComposeTeamAnnouncementScreen(
      authService: _FakeAuthService(),
      teamId: 'team-1',
      service: service,
    ),
  ),
);

void main() {
  testWidgets('empty state renders', (tester) async {
    await tester.pumpWidget(_listApp(_FakeMessagingService()));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد إعلانات للفريق'), findsOneWidget);
  });

  testWidgets('error state has retry', (tester) async {
    final service = _FakeMessagingService()..loadError = Exception('down');
    await tester.pumpWidget(_listApp(service));
    await tester.pumpAndSettle();

    expect(find.text('تعذر تحميل الإعلانات'), findsOneWidget);
    service.loadError = null;
    service.first = [_announcement('1')];
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();

    expect(find.text('إعلان 1'), findsOneWidget);
  });

  testWidgets('list marks unread announcement as read on tap', (tester) async {
    final service = _FakeMessagingService()..first = [_announcement('1')];
    await tester.pumpWidget(_listApp(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إعلان 1'));
    await tester.pumpAndSettle();

    expect(service.readCalls, 1);
  });

  testWidgets('leader sees composer action, member does not', (tester) async {
    final service = _FakeMessagingService()..first = [_announcement('1')];
    await tester.pumpWidget(_listApp(service, leader: true));
    await tester.pumpAndSettle();
    expect(find.text('إعلان جديد'), findsOneWidget);

    await tester.pumpWidget(_listApp(service));
    await tester.pumpAndSettle();
    expect(find.text('إعلان جديد'), findsNothing);
  });

  testWidgets('composer validates required body and limits title length', (
    tester,
  ) async {
    final service = _FakeMessagingService();
    await tester.pumpWidget(_composeApp(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('نشر الإعلان'));
    await tester.pumpAndSettle();
    expect(find.text('لا يمكن نشر إعلان فارغ'), findsOneWidget);

    final titleField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'العنوان'),
    );
    expect(titleField.maxLength, 120);
  });

  testWidgets('composer publishes trimmed title/body and pops true', (
    tester,
  ) async {
    final service = _FakeMessagingService();
    final router = GoRouter(
      initialLocation: '/teams/team-1/announcements/new',
      routes: [
        GoRoute(
          path: '/teams/:id/announcements/new',
          builder: (context, state) => ComposeTeamAnnouncementScreen(
            authService: _FakeAuthService(),
            teamId: 'team-1',
            service: service,
          ),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('done')),
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
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'العنوان'),
      ' عنوان ',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'نص الإعلان'),
      ' نص ',
    );
    await tester.tap(find.text('نشر الإعلان'));
    await tester.pumpAndSettle();

    expect(service.createCalls, 1);
    expect(service.lastTitle, 'عنوان');
    expect(service.lastBody, 'نص');
  });

  testWidgets('pagination sends cursor and drops duplicate ids', (
    tester,
  ) async {
    final cursor = TeamAnnouncementCursor(
      createdAt: DateTime.utc(2026, 7, 13, 9),
      id: '19',
    );
    final service = _FakeMessagingService()
      ..first = List.generate(20, (i) => _announcement('$i'))
      ..second = [_announcement('19'), _announcement('20')]
      ..firstHasMore = true
      ..firstCursor = cursor;
    await tester.pumpWidget(_listApp(service));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, -4000), 4000);
    await tester.pumpAndSettle();

    expect(service.lastBefore, cursor);
    expect(find.text('إعلان 19'), findsOneWidget);
    expect(find.text('إعلان 20'), findsOneWidget);
  });

  testWidgets('renders at 320px without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakeMessagingService()..first = [_announcement('1')];
    await tester.pumpWidget(_listApp(service, leader: true));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
