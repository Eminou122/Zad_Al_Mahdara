import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zad_al_mahdara/features/messaging/data/team_messaging_service.dart';
import 'package:zad_al_mahdara/features/messaging/domain/team_messaging_models.dart';
import 'package:zad_al_mahdara/features/messaging/presentation/compose_team_announcement_screen.dart';
import 'package:zad_al_mahdara/features/messaging/presentation/team_announcements_screen.dart';
import 'package:zad_al_mahdara/features/teams/data/team_service.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_models.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _FakeAuthService extends AuthService {
  @override
  String? get currentToken => 'test-token';

  @override
  UserProfile? get profile => const UserProfile(
    id: 'member-1',
    displayName: 'سالم',
    phoneMasked: '22****88',
    isAdmin: false,
    isActive: true,
  );
}

TeamAnnouncement _announcement(
  String id, {
  bool read = false,
  DateTime? at,
  String authorProfileId = 'old-leader',
}) => TeamAnnouncement(
  id: id,
  teamId: 'team-1',
  teamName: 'فريق الغداء',
  authorProfileId: authorProfileId,
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
  Object? sendError;
  int readCalls = 0;
  int createCalls = 0;
  int sendCalls = 0;
  String? lastTeamId;
  String? lastSentTeamId;
  String? lastSentBody;
  String? lastTitle;
  String? lastBody;
  TeamAnnouncementCursor? lastBefore;
  Completer<void>? sendGate;

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

  @override
  Future<SentTeamMessage> sendMessageToTeamLeader({
    required String teamId,
    required String body,
  }) async {
    sendCalls++;
    lastSentTeamId = teamId;
    lastSentBody = body;
    final gate = sendGate;
    if (gate != null && !gate.isCompleted) await gate.future;
    if (sendError != null) throw sendError!;
    return SentTeamMessage(
      conversation: TeamConversationRef(
        id: 'conv-$sendCalls',
        teamId: teamId,
        memberProfileId: 'member-1',
      ),
      message: TeamMessage(
        id: 'msg-$sendCalls',
        conversationId: 'conv-$sendCalls',
        senderProfileId: 'member-1',
        senderName: 'سالم',
        senderRole: 'member',
        body: body,
        createdAt: DateTime(2026, 7, 13, 10),
        isRead: true,
      ),
    );
  }
}

TeamDetail _detail({
  bool isMember = true,
  bool isLeader = false,
  bool isActive = true,
  bool hasAccount = true,
}) => TeamDetail(
  team: TeamInfo(
    id: 'team-1',
    name: 'فريق الغداء',
    teamType: 'lunch',
    isPublic: true,
    status: 'open',
    leaderId: 'leader-current',
    leaderName: 'القائد الحالي',
    memberCount: 2,
    activeMemberCount: isActive ? 2 : 1,
    inactiveMemberCount: isActive ? 0 : 1,
    createdAt: DateTime(2026, 7, 1),
  ),
  members: [
    TeamMember(
      memberId: 'mem-leader',
      profileId: 'leader-current',
      displayName: 'القائد الحالي',
      memberKind: 'account',
      hasAccount: true,
      role: 'leader',
      position: 1,
      isActive: true,
      joinedAt: DateTime(2026, 7, 1),
    ),
    TeamMember(
      memberId: 'mem-member',
      profileId: 'member-1',
      displayName: 'سالم',
      memberKind: hasAccount ? 'account' : 'external',
      hasAccount: hasAccount,
      role: isLeader ? 'leader' : 'member',
      position: 2,
      isActive: isActive,
      joinedAt: DateTime(2026, 7, 1),
    ),
  ],
  canEdit: isLeader,
  isMember: isMember,
);

class _FakeTeamService extends TeamService {
  TeamDetail? detail;
  Object? error;
  int getTeamDetailCalls = 0;

  _FakeTeamService({this.detail}) : super(AuthService());

  @override
  Future<TeamDetail> getTeamDetail(String teamId) async {
    getTeamDetailCalls++;
    if (error != null) throw error!;
    return detail ?? _detail();
  }
}

Widget _listApp(
  _FakeMessagingService service, {
  bool leader = false,
  String? teamId = 'team-1',
  _FakeTeamService? teamService,
}) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: TeamAnnouncementsScreen(
      authService: _FakeAuthService(),
      teamId: teamId,
      teamName: 'فريق الغداء',
      isLeader: leader,
      service: service,
      teamService: teamService ?? _FakeTeamService(),
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

  testWidgets(
    'active ordinary member sees message-leader action only in team feed',
    (tester) async {
      final service = _FakeMessagingService()..first = [_announcement('1')];
      await tester.pumpWidget(
        _listApp(service, teamService: _FakeTeamService(detail: _detail())),
      );
      await tester.pumpAndSettle();
      expect(find.text('مراسلة قائد الفريق'), findsOneWidget);

      await tester.pumpWidget(
        _listApp(
          service,
          teamId: null,
          teamService: _FakeTeamService(detail: _detail()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('مراسلة قائد الفريق'), findsNothing);
    },
  );

  testWidgets(
    'leader and inactive membership do not see message-leader action',
    (tester) async {
      final service = _FakeMessagingService()..first = [_announcement('1')];
      await tester.pumpWidget(
        _listApp(
          service,
          leader: true,
          teamService: _FakeTeamService(detail: _detail(isLeader: true)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('مراسلة قائد الفريق'), findsNothing);

      await tester.pumpWidget(
        _listApp(
          service,
          teamService: _FakeTeamService(detail: _detail(isActive: false)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('مراسلة قائد الفريق'), findsNothing);
    },
  );

  testWidgets(
    'message-leader composer validates body, preserves failure draft, and sends team id once',
    (tester) async {
      final service = _FakeMessagingService()
        ..first = [_announcement('1', authorProfileId: 'former-leader')];
      final router = GoRouter(
        initialLocation: '/teams/team-1/announcements',
        routes: [
          GoRoute(
            path: '/teams/:id/announcements',
            builder: (context, state) => TeamAnnouncementsScreen(
              authService: _FakeAuthService(),
              teamId: 'team-1',
              teamName: 'فريق الغداء',
              service: service,
              teamService: _FakeTeamService(detail: _detail()),
            ),
          ),
          GoRoute(
            path: '/messages/conversation/:id',
            builder: (_, state) => Scaffold(
              body: Text('conversation-${state.pathParameters['id']}'),
            ),
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

      await tester.tap(find.text('مراسلة قائد الفريق'));
      await tester.pumpAndSettle();
      expect(find.text('رسالة إلى قائد الفريق'), findsOneWidget);
      expect(find.text('اكتب رسالتك'), findsOneWidget);
      expect(find.text('إلغاء'), findsOneWidget);
      expect(find.text('إرسال'), findsOneWidget);

      await tester.tap(find.text('إرسال'));
      await tester.pumpAndSettle();
      expect(find.text('اكتب رسالة أولاً'), findsOneWidget);
      expect(service.sendCalls, 0);

      await tester.enterText(
        find.byType(TextField).last,
        List.filled(2001, 'x').join(),
      );
      await tester.tap(find.text('إرسال'));
      await tester.pumpAndSettle();
      expect(find.text('الرسالة طويلة جداً'), findsOneWidget);
      expect(service.sendCalls, 0);

      service.sendError = Exception('تعذر الإرسال');
      await tester.enterText(find.byType(TextField).last, '  السلام عليكم  ');
      await tester.tap(find.text('إرسال'));
      await tester.pumpAndSettle();
      expect(service.sendCalls, 1);
      expect(service.lastSentTeamId, 'team-1');
      expect(service.lastSentBody, 'السلام عليكم');
      expect(service.lastSentTeamId, isNot('former-leader'));
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller?.text,
        '  السلام عليكم  ',
      );

      service.sendError = null;
      await tester.tap(find.text('إرسال'));
      await tester.pumpAndSettle();
      expect(service.sendCalls, 2);
      expect(find.text('conversation-conv-2'), findsOneWidget);
    },
  );

  testWidgets('double submit does not duplicate message-leader send', (
    tester,
  ) async {
    final gate = Completer<void>();
    final service = _FakeMessagingService()
      ..first = [_announcement('1')]
      ..sendGate = gate;
    await tester.pumpWidget(
      _listApp(service, teamService: _FakeTeamService(detail: _detail())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('مراسلة قائد الفريق'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'السلام عليكم');
    await tester.tap(find.text('إرسال'));
    await tester.tap(find.text('إرسال'));
    await tester.pump();
    expect(service.sendCalls, 1);

    service.sendError = Exception('تعذر الإرسال');
    gate.complete();
    await tester.pumpAndSettle();
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
