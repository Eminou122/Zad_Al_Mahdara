import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/messaging/data/team_messaging_service.dart';
import 'package:zad_al_mahdara/features/messaging/domain/team_messaging_models.dart';
import 'package:zad_al_mahdara/features/messaging/presentation/team_conversation_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _FakeAuthService extends AuthService {
  @override
  String? get currentToken => 'test-token';

  @override
  UserProfile? get profile => const UserProfile(
    id: 'me',
    displayName: 'أنا',
    phoneMasked: '22****88',
    isAdmin: false,
    isActive: true,
  );
}

TeamMessage _message(
  String id, {
  String senderId = 'other',
  String role = 'member',
  DateTime? at,
}) => TeamMessage(
  id: id,
  conversationId: 'conv-1',
  senderProfileId: senderId,
  senderName: senderId == 'me' ? 'أنا' : 'القائد',
  senderRole: role,
  body: 'رسالة $id',
  createdAt: at ?? DateTime(2026, 7, 13, 10),
  isRead: false,
);

class _FakeMessagingService extends TeamMessagingService {
  List<TeamMessage> first = [];
  List<TeamMessage> second = [];
  bool firstHasMore = false;
  TeamMessageCursor? firstCursor;
  TeamConversationSummary? summary;
  Object? sendError;
  int markReadCalls = 0;
  int memberSendCalls = 0;
  int leaderReplyCalls = 0;
  String? lastBody;
  TeamMessageCursor? lastBefore;

  _FakeMessagingService() : super(AuthService());

  @override
  Future<TeamConversationsPage> getMyTeamConversations({
    int limit = 30,
    TeamConversationCursor? before,
    bool unreadOnly = false,
  }) async => TeamConversationsPage(
    items: summary == null ? const [] : [summary!],
    hasMore: false,
  );

  @override
  Future<TeamMessagesPage> getTeamConversationMessages({
    required String conversationId,
    int limit = 50,
    TeamMessageCursor? before,
  }) async {
    lastBefore = before;
    if (before != null) {
      return TeamMessagesPage(
        conversationId: conversationId,
        items: second,
        hasMore: false,
      );
    }
    return TeamMessagesPage(
      conversationId: conversationId,
      items: first,
      hasMore: firstHasMore,
      nextCursor: firstCursor,
    );
  }

  @override
  Future<void> markConversationRead(String conversationId) async {
    markReadCalls++;
  }

  @override
  Future<SentTeamMessage> sendMessageToTeamLeader({
    required String teamId,
    required String body,
  }) async {
    memberSendCalls++;
    lastBody = body;
    if (sendError != null) throw sendError!;
    return SentTeamMessage(
      conversation: const TeamConversationRef(
        id: 'conv-1',
        teamId: 'team-1',
        memberProfileId: 'me',
      ),
      message: _message('sent', senderId: 'me', role: 'member'),
    );
  }

  @override
  Future<SentTeamMessage> replyToTeamConversation({
    required String conversationId,
    required String body,
  }) async {
    leaderReplyCalls++;
    lastBody = body;
    return SentTeamMessage(
      conversation: const TeamConversationRef(
        id: 'conv-1',
        teamId: 'team-1',
        memberProfileId: 'member-1',
      ),
      message: _message('reply', senderId: 'me', role: 'leader'),
    );
  }
}

Widget _wrap(_FakeMessagingService service) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: TeamConversationScreen(
      authService: _FakeAuthService(),
      conversationId: 'conv-1',
      teamId: 'team-1',
      currentUserRole: 'member',
      service: service,
    ),
  ),
);

void main() {
  testWidgets('opens, displays messages, and marks read', (tester) async {
    final service = _FakeMessagingService()
      ..summary = const TeamConversationSummary(
        id: 'conv-1',
        teamId: 'team-1',
        teamName: 'فريق الغداء',
        memberProfileId: 'me',
        memberName: 'أنا',
        unreadCount: 1,
        currentUserRole: 'member',
      )
      ..first = [_message('1', senderId: 'other', role: 'leader')];
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('رسالة 1'), findsOneWidget);
    expect(service.markReadCalls, 1);
  });

  testWidgets('untrusted route role alone cannot send', (tester) async {
    final service = _FakeMessagingService()
      ..first = [_message('1', senderId: 'other', role: 'leader')];
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'مرحبا');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(service.memberSendCalls, 0);
    expect(find.text('تعذر تحديد صلاحيتك في هذه المحادثة'), findsOneWidget);
  });

  testWidgets('member sends through member RPC after backend role hydration', (
    tester,
  ) async {
    final service = _FakeMessagingService()
      ..summary = const TeamConversationSummary(
        id: 'conv-1',
        teamId: 'team-1',
        teamName: 'فريق الغداء',
        memberProfileId: 'me',
        memberName: 'أنا',
        unreadCount: 0,
        currentUserRole: 'member',
      )
      ..first = [_message('mine', senderId: 'me', role: 'member')];
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  السلام عليكم  ');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(service.memberSendCalls, 1);
    expect(service.leaderReplyCalls, 0);
    expect(service.lastBody, 'السلام عليكم');
  });

  testWidgets('leader sends through reply RPC', (tester) async {
    final service = _FakeMessagingService()
      ..summary = const TeamConversationSummary(
        id: 'conv-1',
        teamId: 'team-1',
        teamName: 'فريق الغداء',
        memberProfileId: 'member-1',
        memberName: 'أحمد',
        unreadCount: 0,
        currentUserRole: 'leader',
      )
      ..first = [_message('old', senderId: 'member-1', role: 'member')];
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'رد');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(service.leaderReplyCalls, 1);
    expect(service.memberSendCalls, 0);
  });

  testWidgets('draft is retained after send failure', (tester) async {
    final service = _FakeMessagingService()
      ..summary = const TeamConversationSummary(
        id: 'conv-1',
        teamId: 'team-1',
        teamName: 'فريق الغداء',
        memberProfileId: 'me',
        memberName: 'أنا',
        unreadCount: 0,
        currentUserRole: 'member',
      )
      ..first = [_message('mine', senderId: 'me', role: 'member')]
      ..sendError = Exception('فشل الإرسال');
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'مسودة');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('مسودة'), findsOneWidget);
    expect(find.textContaining('فشل الإرسال'), findsOneWidget);
  });

  testWidgets(
    'pagination preserves same-timestamp messages without duplicates',
    (tester) async {
      final at = DateTime.utc(2026, 7, 13, 10);
      final cursor = TeamMessageCursor(createdAt: at, id: '2');
      final service = _FakeMessagingService()
        ..summary = const TeamConversationSummary(
          id: 'conv-1',
          teamId: 'team-1',
          teamName: 'فريق الغداء',
          memberProfileId: 'me',
          memberName: 'أنا',
          unreadCount: 0,
          currentUserRole: 'member',
        )
        ..first = List.generate(20, (i) => _message('$i', at: at))
        ..second = [_message('19', at: at), _message('20', at: at)]
        ..firstHasMore = true
        ..firstCursor = cursor;
      await tester.pumpWidget(_wrap(service));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.fling(find.byType(ListView), const Offset(0, 4000), 4000);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(service.lastBefore, cursor);
      expect(find.text('رسالة 19'), findsOneWidget);
      expect(find.text('رسالة 20'), findsOneWidget);
    },
  );

  testWidgets('renders long Arabic at 320px without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakeMessagingService()
      ..summary = const TeamConversationSummary(
        id: 'conv-1',
        teamId: 'team-1',
        teamName: 'فريق الغداء',
        memberProfileId: 'me',
        memberName: 'أنا',
        unreadCount: 0,
        currentUserRole: 'member',
      )
      ..first = [
        TeamMessage(
          id: 'long',
          conversationId: 'conv-1',
          senderProfileId: 'other',
          senderName: 'القائد',
          senderRole: 'leader',
          body: 'هذه رسالة عربية طويلة جداً للتأكد من الالتفاف داخل الفقاعة',
          createdAt: DateTime(2026, 7, 13, 10),
          isRead: false,
        ),
      ];
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
