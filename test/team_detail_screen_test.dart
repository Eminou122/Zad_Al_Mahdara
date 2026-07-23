import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zad_al_mahdara/core/refresh/app_refresh_coordinator.dart';
import 'package:zad_al_mahdara/core/routing/route_observer.dart';
import 'package:zad_al_mahdara/core/utils/ltr_fragment.dart';
import 'package:zad_al_mahdara/core/widgets/zad_section_header.dart';
import 'package:zad_al_mahdara/features/teams/data/team_service.dart';
import 'package:zad_al_mahdara/features/teams/data/team_shopping_service.dart';
import 'package:zad_al_mahdara/features/teams/data/team_turn_service.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_models.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_shopping_models.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_turn_models.dart';
import 'package:zad_al_mahdara/features/teams/presentation/team_detail_screen.dart';
import 'package:zad_al_mahdara/features/messaging/data/team_messaging_service.dart';
import 'package:zad_al_mahdara/features/messaging/domain/team_messaging_models.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

TeamDetail _sampleTeamDetail() => TeamDetail(
  team: TeamInfo(
    id: 'team-1',
    name: 'فريق الغداء',
    teamType: 'lunch',
    isPublic: true,
    status: 'open',
    leaderId: 'leader-1',
    leaderName: 'أحمد',
    memberCount: 3,
    activeMemberCount: 2,
    inactiveMemberCount: 1,
    createdAt: DateTime(2026, 7, 1),
  ),
  members: [
    TeamMember(
      memberId: 'mem-1',
      profileId: 'p1',
      displayName: 'محمد',
      memberKind: 'account',
      hasAccount: true,
      role: 'leader',
      position: 1,
      isActive: true,
      joinedAt: DateTime(2026, 7, 1),
    ),
  ],
  canEdit: true,
  isMember: true,
);

TeamTurnState _sampleTurnState() => TeamTurnState(
  canManageTurns: true,
  todayTurn: TurnEntry(
    id: 'turn-1',
    turnDate: '2026-07-05',
    status: 'pending',
    memberId: 'mem-1',
    displayName: 'محمد',
    position: 1,
  ),
  nextMember: null,
  lastCompletedTurn: null,
  history: const [],
);

TeamTurnState _turnStateWithoutToday() => const TeamTurnState(
  canManageTurns: true,
  todayTurn: null,
  nextMember: TurnMemberRef(
    memberId: 'mem-1',
    position: 1,
    displayName: 'محمد',
  ),
  lastCompletedTurn: null,
  history: [],
);

TeamTurnState _blockedTurnState({bool canSkip = true}) => TeamTurnState(
  canManageTurns: true,
  todayTurn: null,
  nextMember: const TurnMemberRef(
    memberId: 'mem-1',
    position: 1,
    displayName: 'محمد',
  ),
  lastCompletedTurn: null,
  history: const [],
  blockingPreviousTurn: true,
  canSkipPreviousTurn: canSkip,
  previousTurnId: 'prev-turn',
  previousTurnMemberName: 'سالم',
  previousTurnDate: '2026-07-04',
  previousTurnStatus: canSkip ? 'pending' : 'started',
);

TeamShoppingOverview _sampleShoppingOverview({
  bool canMark = true,
  bool canEditList = false,
  bool includeResponsible = true,
  int itemCount = 2,
  double? firstItemPrice,
  double? firstItemQuantityValue,
  String? firstItemQuantityUnit,
  TeamShoppingReport? report,
  bool hasReportObject = false,
  List<TeamShoppingItem>? items,
}) => TeamShoppingOverview(
  turnDate: DateTime(2026, 7, 5),
  responsibleMember: includeResponsible
      ? TeamShoppingResponsibleMember(id: 'p1', displayName: 'محمد')
      : null,
  canMark: canMark,
  canEditList: canEditList,
  report:
      report ??
      TeamShoppingReport(
        canSubmit: canMark,
        canReview: false,
        canEditMarks: canMark,
      ),
  hasReportObject: hasReportObject,
  items:
      items ??
      List.generate(itemCount, (i) {
        final bought = i == 1;
        return TeamShoppingItem(
          id: 'item-$i',
          name: i == 0 ? 'خبز' : 'حليب',
          quantityNote: i == 0 ? '2 رغيف' : null,
          quantityValue: i == 0 ? firstItemQuantityValue : null,
          quantityUnit: i == 0 ? firstItemQuantityUnit : null,
          isRequired: i == 0,
          position: i + 1,
          bought: bought,
          status: bought ? 'bought' : 'untouched',
          markedByName: bought ? 'أحمد' : null,
          markedAt: bought ? DateTime(2026, 7, 5, 8, 30) : null,
          price: i == 0 ? firstItemPrice : null,
        );
      }),
);

// _sampleTeamDetail's only member is the leader, who can't be
// deactivated/removed/reactivated from the UI. This variant adds a
// manageable non-leader member for the Gate 41.1 member-action test.
TeamDetail _teamDetailWithManageableMember({bool memberActive = true}) =>
    TeamDetail(
      team: TeamInfo(
        id: 'team-1',
        name: 'فريق الغداء',
        teamType: 'lunch',
        isPublic: true,
        status: 'open',
        leaderId: 'leader-1',
        leaderName: 'أحمد',
        memberCount: 2,
        activeMemberCount: memberActive ? 2 : 1,
        inactiveMemberCount: memberActive ? 0 : 1,
        createdAt: DateTime(2026, 7, 1),
      ),
      members: [
        TeamMember(
          memberId: 'mem-1',
          profileId: 'p1',
          displayName: 'محمد',
          memberKind: 'account',
          hasAccount: true,
          role: 'leader',
          position: 1,
          isActive: true,
          joinedAt: DateTime(2026, 7, 1),
        ),
        TeamMember(
          memberId: 'mem-2',
          profileId: 'p2',
          displayName: 'سالم',
          phoneMasked: '22****88',
          memberKind: 'account',
          hasAccount: true,
          role: 'member',
          position: 2,
          isActive: memberActive,
          joinedAt: DateTime(2026, 7, 1),
        ),
      ],
      canEdit: true,
      isMember: true,
    );

TeamDetail _teamDetailAfterRemoval() => TeamDetail(
  team: TeamInfo(
    id: 'team-1',
    name: 'فريق الغداء',
    teamType: 'lunch',
    isPublic: true,
    status: 'open',
    leaderId: 'leader-1',
    leaderName: 'أحمد',
    memberCount: 1,
    activeMemberCount: 1,
    inactiveMemberCount: 0,
    createdAt: DateTime(2026, 7, 1),
  ),
  members: [_teamDetailWithManageableMember().members.first],
  canEdit: true,
  isMember: true,
);

TeamDetail _ordinaryMemberDetail({bool isMember = true}) => TeamDetail(
  team: TeamInfo(
    id: 'team-1',
    name: 'فريق الغداء',
    teamType: 'lunch',
    isPublic: true,
    status: 'open',
    leaderId: 'leader-1',
    leaderName: 'أحمد',
    memberCount: 2,
    activeMemberCount: isMember ? 2 : 1,
    inactiveMemberCount: isMember ? 0 : 1,
    createdAt: DateTime(2026, 7, 1),
  ),
  members: const [],
  canEdit: false,
  isMember: isMember,
);

class _FakeTeamService extends TeamService {
  TeamDetail? detail;
  Object? error;
  int getTeamDetailCallCount = 0;

  // Set to make getTeamDetail hang until the test completes it, to inspect
  // Gate 41.2 in-flight background-refresh state.
  Completer<TeamDetail>? pendingDetail;

  // Only overridden for the member-action regression test below; the real
  // TeamService methods call Supabase RPC directly and are not otherwise
  // exercised by this fake.
  TeamDetail? deactivateResult;
  String? lastDeactivatedMemberId;
  TeamMemberRemoval? removalResult;
  Object? removalError;
  Completer<TeamMemberRemoval>? pendingRemoval;
  int removeCallCount = 0;
  String? lastRemovedMemberId;
  String? lastRemovalReason;

  _FakeTeamService({this.detail}) : super(AuthService());

  @override
  Future<TeamDetail> getTeamDetail(String teamId) async {
    getTeamDetailCallCount++;
    if (pendingDetail != null) return pendingDetail!.future;
    if (error != null) throw error!;
    return detail ?? _sampleTeamDetail();
  }

  @override
  Future<TeamDetail> deactivateTeamMember({
    required String teamId,
    required String memberId,
  }) async {
    lastDeactivatedMemberId = memberId;
    return deactivateResult ?? detail ?? _sampleTeamDetail();
  }

  @override
  Future<TeamMemberRemoval> removeTeamMember({
    required String memberId,
    required String reason,
  }) async {
    removeCallCount++;
    lastRemovedMemberId = memberId;
    lastRemovalReason = reason;
    if (removalError != null) throw removalError!;
    if (pendingRemoval != null) return pendingRemoval!.future;
    return removalResult ??
        TeamMemberRemoval(removed: true, detail: detail ?? _sampleTeamDetail());
  }
}

class _FakeTurnService extends TeamTurnService {
  TeamTurnState? state;
  Object? error;
  int getTurnStateCallCount = 0;
  int skipMissedTurnCallCount = 0;
  int ensureTodayTurnCallCount = 0;
  int completeTurnCallCount = 0;
  int startDailyRoleCallCount = 0;
  int leaderFinalizeDailyRoleCallCount = 0;
  String? lastSkipTeamId;
  String? lastSkipTurnId;
  String? lastSkipReason;

  _FakeTurnService({this.state}) : super(AuthService());

  @override
  Future<TeamTurnState> getTurnState(String teamId) async {
    getTurnStateCallCount++;
    if (error != null) throw error!;
    return state ?? _sampleTurnState();
  }

  @override
  Future<TeamTurnState> ensureTodayTurn(String teamId) async {
    ensureTodayTurnCallCount++;
    if (error != null) throw error!;
    state = _sampleTurnState();
    return state!;
  }

  @override
  Future<TeamTurnState> completeTurn(String turnId) async {
    completeTurnCallCount++;
    if (error != null) throw error!;
    return state ?? _sampleTurnState();
  }

  @override
  Future<TeamTurnState> startDailyRole(String teamId) async {
    startDailyRoleCallCount++;
    if (error != null) throw error!;
    return state ?? _sampleTurnState();
  }

  @override
  Future<TeamTurnState> leaderFinalizeDailyRole(String turnId) async {
    leaderFinalizeDailyRoleCallCount++;
    if (error != null) throw error!;
    return state ?? _sampleTurnState();
  }

  @override
  Future<TeamTurnState> skipMissedTurn(
    String teamId,
    String turnId, {
    String? reason,
  }) async {
    skipMissedTurnCallCount++;
    lastSkipTeamId = teamId;
    lastSkipTurnId = turnId;
    lastSkipReason = reason;
    if (error != null) throw error!;
    state = TeamTurnState(
      canManageTurns: true,
      todayTurn: null,
      nextMember: const TurnMemberRef(
        memberId: 'mem-1',
        position: 1,
        displayName: 'محمد',
      ),
      lastCompletedTurn: null,
      history: const [
        TurnEntry(
          id: 'prev-turn',
          turnDate: '2026-07-04',
          status: 'skipped',
          memberId: 'mem-2',
          displayName: 'سالم',
          position: 2,
        ),
      ],
    );
    return state!;
  }
}

class _FakeTeamShoppingService extends TeamShoppingService {
  TeamShoppingOverview? overview;
  Object? error;
  int getShoppingListCallCount = 0;

  // Set to make getShoppingList hang until the test completes it, to
  // inspect Gate 41.2 in-flight background-refresh state.
  Completer<TeamShoppingOverview>? pendingShoppingList;

  String? lastMarkedItemId;
  bool? lastMarkedBought;
  String? lastMarkedReason;
  int submitCallCount = 0;
  Completer<TeamShoppingOverview>? pendingSubmit;
  String? lastReviewStatus;
  String? lastReviewNote;
  int reviewCallCount = 0;
  Object? reviewError;

  String? lastAddedName;
  String? lastAddedQuantityNote;
  bool? lastAddedIsRequired;
  double? lastAddedPrice;
  double? lastAddedQuantityValue;
  String? lastAddedQuantityUnit;

  String? lastUpdatedItemId;
  String? lastUpdatedName;
  double? lastUpdatedPrice;
  double? lastUpdatedQuantityValue;
  String? lastUpdatedQuantityUnit;

  String? lastDeactivatedItemId;

  Object? actionError;

  _FakeTeamShoppingService({this.overview, this.error});

  @override
  Future<TeamShoppingOverview> getShoppingList({
    required String sessionToken,
    required String teamId,
    DateTime? date,
  }) async {
    getShoppingListCallCount++;
    if (pendingShoppingList != null) return pendingShoppingList!.future;
    if (error != null) throw error!;
    return overview ?? _sampleShoppingOverview();
  }

  @override
  Future<TeamShoppingOverview> markItemStatus({
    required String sessionToken,
    required String teamId,
    required String itemId,
    required bool bought,
    DateTime? date,
    String? reason,
  }) async {
    if (error != null) throw error!;
    lastMarkedItemId = itemId;
    lastMarkedBought = bought;
    lastMarkedReason = reason;
    overview = _sampleShoppingOverview(
      canMark: overview?.canMark ?? true,
      itemCount: overview?.items.length ?? 2,
    );
    return overview!;
  }

  @override
  Future<TeamShoppingOverview> submitShoppingReport({
    required String sessionToken,
    required String teamId,
    DateTime? date,
  }) async {
    submitCallCount++;
    if (pendingSubmit != null) return pendingSubmit!.future;
    overview = _sampleShoppingOverview(
      canMark: false,
      report: TeamShoppingReport(
        submittedAt: DateTime(2026, 7, 5, 9),
        leaderStatus: 'pending',
        canSubmit: false,
        canReview: false,
        canEditMarks: false,
      ),
      hasReportObject: true,
      items: overview?.items,
    );
    return overview!;
  }

  @override
  Future<TeamShoppingOverview> reviewShoppingReport({
    required String sessionToken,
    required String teamId,
    required String status,
    DateTime? date,
    String? note,
  }) async {
    reviewCallCount++;
    if (reviewError != null) throw reviewError!;
    lastReviewStatus = status;
    lastReviewNote = note;
    overview = _sampleShoppingOverview(
      canMark: false,
      report: TeamShoppingReport(
        submittedAt: DateTime(2026, 7, 5, 9),
        leaderStatus: status,
        leaderNote: note,
        canSubmit: false,
        canReview: false,
        canEditMarks: false,
      ),
      hasReportObject: true,
      items: overview?.items,
    );
    return overview!;
  }

  @override
  Future<TeamShoppingOverview> addItem({
    required String sessionToken,
    required String teamId,
    required String name,
    String? quantityNote,
    bool isRequired = true,
    double? price,
    double? quantityValue,
    String? quantityUnit,
  }) async {
    if (actionError != null) throw actionError!;
    lastAddedName = name;
    lastAddedQuantityNote = quantityNote;
    lastAddedIsRequired = isRequired;
    lastAddedPrice = price;
    lastAddedQuantityValue = quantityValue;
    lastAddedQuantityUnit = quantityUnit;
    overview = _sampleShoppingOverview(
      canEditList: overview?.canEditList ?? true,
      itemCount: (overview?.items.length ?? 2) + 1,
      firstItemPrice: price,
      firstItemQuantityValue: quantityValue,
      firstItemQuantityUnit: quantityUnit,
    );
    return overview!;
  }

  @override
  Future<TeamShoppingOverview> updateItem({
    required String sessionToken,
    required String teamId,
    required String itemId,
    required String name,
    String? quantityNote,
    bool isRequired = true,
    double? price,
    double? quantityValue,
    String? quantityUnit,
  }) async {
    if (actionError != null) throw actionError!;
    lastUpdatedItemId = itemId;
    lastUpdatedName = name;
    lastUpdatedPrice = price;
    lastUpdatedQuantityValue = quantityValue;
    lastUpdatedQuantityUnit = quantityUnit;
    overview = _sampleShoppingOverview(
      canEditList: overview?.canEditList ?? true,
      itemCount: overview?.items.length ?? 2,
      firstItemPrice: price,
      firstItemQuantityValue: quantityValue,
      firstItemQuantityUnit: quantityUnit,
    );
    return overview!;
  }

  @override
  Future<TeamShoppingOverview> deactivateItem({
    required String sessionToken,
    required String teamId,
    required String itemId,
  }) async {
    if (actionError != null) throw actionError!;
    lastDeactivatedItemId = itemId;
    overview = _sampleShoppingOverview(
      canEditList: overview?.canEditList ?? true,
      itemCount: ((overview?.items.length ?? 2) - 1).clamp(0, 999),
    );
    return overview!;
  }
}

class _FakeMessagingService extends TeamMessagingService {
  int sendCalls = 0;
  String? lastBody;

  _FakeMessagingService() : super(AuthService());

  @override
  Future<SentTeamMessage> sendMessageToTeamLeader({
    required String teamId,
    required String body,
  }) async {
    sendCalls++;
    lastBody = body;
    return SentTeamMessage(
      conversation: const TeamConversationRef(
        id: 'conv-1',
        teamId: 'team-1',
        memberProfileId: 'p1',
      ),
      message: TeamMessage(
        id: 'msg-1',
        conversationId: 'conv-1',
        senderProfileId: 'p1',
        senderName: 'محمد',
        senderRole: 'member',
        body: body,
        createdAt: DateTime(2026, 7, 13, 10),
        isRead: true,
      ),
    );
  }
}

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

Widget _buildTest(
  AuthService authService, {
  TeamService? teamService,
  TeamTurnService? turnService,
  TeamShoppingService? shoppingService,
  TeamMessagingService? messagingService,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: TeamDetailScreen(
        authService: authService,
        teamId: 'team-1',
        teamService: teamService,
        turnService: turnService,
        shoppingService: shoppingService,
        messagingService: messagingService,
      ),
    ),
  );
}

// Same as _buildTest, but registers appRouteObserver so a real push/pop can
// trigger TeamDetailScreen's didPopNext (Gate 41.2 background-refresh test).
Widget _buildRoutedTest(
  AuthService authService, {
  TeamService? teamService,
  TeamTurnService? turnService,
  TeamShoppingService? shoppingService,
}) {
  return MaterialApp(
    navigatorObservers: [appRouteObserver],
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: TeamDetailScreen(
        authService: authService,
        teamId: 'team-1',
        teamService: teamService,
        turnService: turnService,
        shoppingService: shoppingService,
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  TeamShoppingOverview? overview,
  TeamDetail? detail,
  TeamTurnState? turnState,
  Object? shoppingError,
}) async {
  await tester.pumpWidget(
    _buildTest(
      _FakeAuthService(),
      teamService: _FakeTeamService(detail: detail ?? _sampleTeamDetail()),
      turnService: _FakeTurnService(state: turnState ?? _sampleTurnState()),
      shoppingService: _FakeTeamShoppingService(
        overview: overview,
        error: shoppingError,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _scrollToTurnCard(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('نظام النوبات اليومي'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ordinary active member sees messaging and announcements', (
    tester,
  ) async {
    await _pump(tester, detail: _ordinaryMemberDetail());

    expect(find.text('مراسلة قائد الفريق'), findsOneWidget);
    expect(find.text('الإعلانات'), findsOneWidget);
    expect(find.text('إعلان جديد'), findsNothing);
  });

  testWidgets('leader sees announcements but not member messaging', (
    tester,
  ) async {
    await _pump(tester, detail: _sampleTeamDetail());

    expect(find.text('الإعلانات'), findsOneWidget);
    expect(find.text('مراسلة قائد الفريق'), findsNothing);
  });

  testWidgets('ineligible non-member does not see messaging or announcements', (
    tester,
  ) async {
    await _pump(tester, detail: _ordinaryMemberDetail(isMember: false));

    expect(find.text('مراسلة قائد الفريق'), findsNothing);
    expect(find.text('الإعلانات'), findsNothing);
  });

  testWidgets('first-message dialog blocks blank and sends trimmed body', (
    tester,
  ) async {
    final messagingService = _FakeMessagingService();
    final router = GoRouter(
      initialLocation: '/teams/team-1',
      routes: [
        GoRoute(
          path: '/teams/:id',
          builder: (context, state) => TeamDetailScreen(
            authService: _FakeAuthService(),
            teamId: 'team-1',
            teamService: _FakeTeamService(detail: _ordinaryMemberDetail()),
            turnService: _FakeTurnService(state: _sampleTurnState()),
            shoppingService: _FakeTeamShoppingService(),
            messagingService: messagingService,
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
    await tester.tap(find.text('إرسال'));
    await tester.pumpAndSettle();
    expect(find.text('اكتب رسالة أولاً'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '  السلام عليكم  ');
    await tester.tap(find.text('إرسال'));
    await tester.pumpAndSettle();

    expect(messagingService.sendCalls, 1);
    expect(messagingService.lastBody, 'السلام عليكم');
    expect(find.text('conversation-conv-1'), findsOneWidget);
  });

  testWidgets('hero member counts isolate numeric fragments', (tester) async {
    await _pump(tester);

    expect(
      find.text(
        '${ltrFragment('3')} عضو '
        '(نشط ${ltrFragment('2')} · غير نشط ${ltrFragment('1')})',
      ),
      findsOneWidget,
    );
  });

  testWidgets('member phone caption isolates only the phone number', (
    tester,
  ) async {
    await _pump(tester, detail: _teamDetailWithManageableMember());
    await tester.scrollUntilVisible(
      find.text('سالم'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text(ltrFragment('22****88')), findsOneWidget);
    expect(find.text('بدون حساب'), findsNothing);
  });

  testWidgets('shopping card title shows تسوق اليوم', (tester) async {
    await _pump(tester);
    expect(find.text('تسوق اليوم'), findsOneWidget);
  });

  testWidgets('responsible member sees أنت مسؤول تسوق اليوم', (tester) async {
    await _pump(tester);
    expect(find.text('أنت مسؤول تسوق اليوم'), findsOneWidget);
    expect(find.textContaining('المسؤول اليوم:'), findsOneWidget);
  });

  testWidgets('empty list renders لم تتم إضافة عناصر بعد', (tester) async {
    await _pump(tester, overview: _sampleShoppingOverview(itemCount: 0));
    expect(find.text('لم تتم إضافة عناصر بعد'), findsOneWidget);
    expect(
      find.text('أضف عنصرًا واحدًا على الأقل قبل مشاركة القائمة'),
      findsOneWidget,
    );
  });

  testWidgets('empty list disables report submission with no service call', (
    tester,
  ) async {
    final coordinator = AppRefreshCoordinator.instance..resetForTesting();
    var notificationInvalidations = 0;
    final unsubscribe = coordinator.subscribe(
      AppRefreshScope.notifications,
      (_) => notificationInvalidations++,
    );
    addTearDown(() {
      unsubscribe();
      coordinator.resetForTesting();
    });
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(
        itemCount: 0,
        hasReportObject: true,
        report: const TeamShoppingReport(
          canSubmit: true,
          canReview: false,
          canEditMarks: true,
        ),
      ),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال القائمة للقائد'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('لا يمكن إرسال تقرير فارغ'), findsOneWidget);
    expect(shoppingService.submitCallCount, 0);
    await tester.pump();
    expect(notificationInvalidations, 0);
  });

  testWidgets('blank placeholder and invalid quantity do not make list valid', (
    tester,
  ) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        hasReportObject: true,
        report: const TeamShoppingReport(
          canSubmit: true,
          canReview: false,
          canEditMarks: true,
        ),
        items: const [
          TeamShoppingItem(
            id: 'blank',
            name: '  ',
            isRequired: true,
            position: 1,
            bought: true,
            status: 'bought',
          ),
          TeamShoppingItem(
            id: 'invalid-quantity',
            name: 'أرز',
            quantityValue: 2,
            isRequired: true,
            position: 2,
            bought: true,
            status: 'bought',
          ),
        ],
      ),
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال القائمة للقائد'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('لا يمكن إرسال تقرير فارغ'), findsOneWidget);
  });

  testWidgets('bought item renders تم الشراء', (tester) async {
    await _pump(tester);
    expect(find.text('تم الشراء'), findsOneWidget);
  });

  testWidgets('required item renders أساسي', (tester) async {
    await _pump(tester);
    expect(find.text('أساسي'), findsOneWidget);
  });

  testWidgets('optional item renders اختياري', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview().copyWith(
        items: [
          TeamShoppingItem(
            id: 'item-2',
            name: 'حليب',
            isRequired: false,
            position: 2,
            bought: false,
          ),
        ],
      ),
    );
    expect(find.text('اختياري'), findsOneWidget);
  });

  testWidgets('canMark=false hides checkbox', (tester) async {
    await _pump(tester, overview: _sampleShoppingOverview(canMark: false));
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('تسوق اليوم'), findsOneWidget);
  });

  testWidgets('canMark=true shows checkbox and toggles bought', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canMark: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsNWidgets(2));

    await _tapVisible(tester, find.byType(Checkbox));

    expect(shoppingService.lastMarkedItemId, 'item-0');
    expect(shoppingService.lastMarkedBought, true);
  });

  testWidgets(
    'available actions show اشتريت and لم أشترِ when can_edit_marks true',
    (tester) async {
      await _pump(tester, overview: _sampleShoppingOverview(canMark: true));
      expect(find.text('اشتريت'), findsWidgets);
      expect(find.text('لم أشترِ'), findsWidgets);
    },
  );

  testWidgets('tapping اشتريت calls mark with bought=true', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canMark: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('اشتريت'));
    expect(shoppingService.lastMarkedBought, true);
  });

  testWidgets('tapping لم أشترِ requires reason', (tester) async {
    await _pump(tester, overview: _sampleShoppingOverview(canMark: true));
    await _tapVisible(tester, find.text('لم أشترِ'));
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('السبب مطلوب'), findsOneWidget);
  });

  testWidgets(
    'not_bought with reason calls mark with bought=false and reason',
    (tester) async {
      final shoppingService = _FakeTeamShoppingService(
        overview: _sampleShoppingOverview(canMark: true),
      );
      await tester.pumpWidget(
        _buildTest(
          _FakeAuthService(),
          teamService: _FakeTeamService(detail: _sampleTeamDetail()),
          turnService: _FakeTurnService(state: _sampleTurnState()),
          shoppingService: shoppingService,
        ),
      );
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('لم أشترِ'));
      await tester.enterText(
        find.widgetWithText(TextField, 'السبب'),
        'غير موجود',
      );
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(shoppingService.lastMarkedBought, false);
      expect(shoppingService.lastMarkedReason, 'غير موجود');
    },
  );

  testWidgets('submit button disabled when required item not bought', (
    tester,
  ) async {
    final overview = _sampleShoppingOverview(
      hasReportObject: true,
      report: const TeamShoppingReport(
        canSubmit: true,
        canReview: false,
        canEditMarks: true,
      ),
    );
    await _pump(tester, overview: overview);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال القائمة للقائد'),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text('يجب شراء كل العناصر الأساسية قبل الإرسال'),
      findsOneWidget,
    );
  });

  testWidgets('submit button disabled when optional item untouched', (
    tester,
  ) async {
    final overview = _sampleShoppingOverview(
      hasReportObject: true,
      report: const TeamShoppingReport(
        canSubmit: true,
        canReview: false,
        canEditMarks: true,
      ),
      items: const [
        TeamShoppingItem(
          id: 'r',
          name: 'خبز',
          isRequired: true,
          position: 1,
          bought: true,
          status: 'bought',
        ),
        TeamShoppingItem(
          id: 'o',
          name: 'شاي',
          isRequired: false,
          position: 2,
          bought: false,
          status: 'untouched',
        ),
      ],
    );
    await _pump(tester, overview: overview);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال القائمة للقائد'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('يجب تحديد حالة كل العناصر الاختيارية'), findsOneWidget);
  });

  testWidgets(
    'submit button enabled when required bought and optional resolved',
    (tester) async {
      final overview = _sampleShoppingOverview(
        hasReportObject: true,
        report: const TeamShoppingReport(
          canSubmit: true,
          canReview: false,
          canEditMarks: true,
        ),
        items: const [
          TeamShoppingItem(
            id: 'r',
            name: 'خبز',
            isRequired: true,
            position: 1,
            bought: true,
            status: 'bought',
          ),
          TeamShoppingItem(
            id: 'o',
            name: 'شاي',
            isRequired: false,
            position: 2,
            bought: false,
            status: 'not_bought',
            reason: 'غير موجود',
          ),
        ],
      );
      await _pump(tester, overview: overview);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'إرسال القائمة للقائد'),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets('submit calls submitShoppingReport', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(
        hasReportObject: true,
        report: const TeamShoppingReport(
          canSubmit: true,
          canReview: false,
          canEditMarks: true,
        ),
        items: const [
          TeamShoppingItem(
            id: 'r',
            name: 'خبز',
            isRequired: true,
            position: 1,
            bought: true,
            status: 'bought',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('إرسال القائمة للقائد'));
    expect(shoppingService.submitCallCount, 1);
    expect(find.text('تم إرسال القائمة للقائد'), findsOneWidget);
  });

  testWidgets('double tap submits one shopping report request', (tester) async {
    final initial = _sampleShoppingOverview(
      hasReportObject: true,
      report: const TeamShoppingReport(
        canSubmit: true,
        canReview: false,
        canEditMarks: true,
      ),
      items: const [
        TeamShoppingItem(
          id: 'r',
          name: 'خبز',
          isRequired: true,
          position: 1,
          bought: true,
          status: 'bought',
        ),
      ],
    );
    final shoppingService = _FakeTeamShoppingService(overview: initial)
      ..pendingSubmit = Completer<TeamShoppingOverview>();
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'إرسال القائمة للقائد');
    await tester.scrollUntilVisible(
      submit,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final onPressed = tester.widget<FilledButton>(submit).onPressed!;
    onPressed();
    onPressed();
    await tester.pump();
    expect(shoppingService.submitCallCount, 1);
    expect(find.text('خبز'), findsOneWidget);

    shoppingService.pendingSubmit!.complete(initial);
    await tester.pumpAndSettle();
    expect(shoppingService.submitCallCount, 1);
  });

  testWidgets('empty pending report cannot be accepted or rejected', (
    tester,
  ) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(
        itemCount: 0,
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'pending',
          canSubmit: false,
          canReview: true,
          canEditMarks: false,
        ),
      ),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'قبول'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'رفض'))
          .onPressed,
      isNull,
    );
    expect(shoppingService.reviewCallCount, 0);
  });

  testWidgets('pending report disables marking/submitting', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        canMark: true,
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'pending',
          canSubmit: false,
          canReview: false,
          canEditMarks: false,
        ),
      ),
    );
    expect(find.text('في انتظار المراجعة'), findsOneWidget);
    expect(find.text('اشتريت'), findsNothing);
    expect(find.text('إرسال القائمة للقائد'), findsNothing);
  });

  testWidgets(
    'rejected report shows leader note and allows editing/resubmission',
    (tester) async {
      await _pump(
        tester,
        overview: _sampleShoppingOverview(
          hasReportObject: true,
          report: TeamShoppingReport(
            submittedAt: DateTime(2026, 7, 5),
            leaderStatus: 'rejected',
            leaderNote: 'راجع السوق',
            canSubmit: true,
            canReview: false,
            canEditMarks: true,
          ),
        ),
      );
      expect(find.textContaining('راجع السوق'), findsOneWidget);
      expect(find.text('اشتريت'), findsWidgets);
      expect(find.text('إرسال القائمة للقائد'), findsOneWidget);
    },
  );

  testWidgets('accepted report shows financial totals and deducted amount', (
    tester,
  ) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        canMark: false,
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'accepted',
          expectedTotal: 300,
          actualTotal: 270.5,
          expenseId: 'expense-secret-id',
          financialAppliedAt: DateTime(2026, 7, 5, 10),
          financialAppliedBy: 'leader-1',
          canSubmit: false,
          canReview: false,
          canEditMarks: false,
        ),
      ),
    );

    expect(find.text('التكلفة المتوقعة:'), findsOneWidget);
    expect(find.text('التكلفة الفعلية:'), findsOneWidget);
    expect(find.text('المخصوم من الميزانية:'), findsOneWidget);
    expect(find.textContaining('300 MRU'), findsOneWidget);
    expect(find.textContaining('270.50 MRU'), findsWidgets);
    expect(find.text('تم تطبيق الخصم'), findsOneWidget);
    expect(find.textContaining('expense-secret-id'), findsNothing);
  });

  testWidgets('responsible member sees budget deduction message', (
    tester,
  ) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        canMark: false,
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'accepted',
          expectedTotal: 300,
          actualTotal: 270,
          financialAppliedAt: DateTime(2026, 7, 5, 10),
          financialAppliedBy: 'leader-1',
          canSubmit: false,
          canReview: false,
          canEditMarks: false,
        ),
      ),
    );

    expect(find.text('تم قبول التقرير'), findsOneWidget);
    expect(find.textContaining('تم خصم'), findsOneWidget);
    expect(find.textContaining('270 MRU'), findsWidgets);
  });

  testWidgets('zero actual report shows no deduction message', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        canMark: false,
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'accepted',
          expectedTotal: 25,
          actualTotal: 0,
          financialAppliedAt: DateTime(2026, 7, 5, 10),
          financialAppliedBy: 'leader-1',
          canSubmit: false,
          canReview: false,
          canEditMarks: false,
        ),
      ),
    );

    expect(find.textContaining('0 MRU'), findsWidgets);
    expect(find.text('لم يتم خصم أي مبلغ من ميزانيتك'), findsOneWidget);
  });

  testWidgets('leader sees summary but no budget balance or expense history', (
    tester,
  ) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        canMark: false,
        canEditList: true,
        includeResponsible: false,
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'accepted',
          expectedTotal: 300,
          actualTotal: 270,
          financialAppliedAt: DateTime(2026, 7, 5, 10),
          financialAppliedBy: 'leader-1',
          canSubmit: false,
          canReview: false,
          canEditMarks: false,
        ),
      ),
    );

    expect(find.text('التكلفة المتوقعة:'), findsOneWidget);
    expect(find.text('تم تطبيق الخصم'), findsOneWidget);
    expect(find.textContaining('ميزانيتك'), findsNothing);
    expect(find.textContaining('الرصيد'), findsNothing);
    expect(find.textContaining('expense'), findsNothing);
  });

  testWidgets('pending and rejected reports do not show deduction summary', (
    tester,
  ) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'pending',
          canSubmit: false,
          canReview: true,
          canEditMarks: false,
        ),
      ),
    );
    expect(find.text('المخصوم من الميزانية:'), findsNothing);

    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'rejected',
          leaderNote: 'راجع السوق',
          canSubmit: true,
          canReview: false,
          canEditMarks: true,
        ),
      ),
    );
    expect(find.text('المخصوم من الميزانية:'), findsNothing);
  });

  testWidgets('historical accepted report shows legacy financial note', (
    tester,
  ) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        canMark: false,
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'accepted',
          canSubmit: false,
          canReview: false,
          canEditMarks: false,
        ),
      ),
    );

    expect(find.text('تقرير قديم بدون حسبة مالية'), findsOneWidget);
    expect(
      find.text('لم تُطبَّق الحسبة المالية على هذا التقرير القديم'),
      findsOneWidget,
    );
    expect(find.textContaining('0 MRU'), findsNothing);
  });

  testWidgets('leader sees pending report and قبول/رفض buttons', (
    tester,
  ) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'pending',
          canSubmit: false,
          canReview: true,
          canEditMarks: false,
        ),
      ),
    );
    expect(find.text('في انتظار المراجعة'), findsOneWidget);
    expect(find.text('قبول'), findsOneWidget);
    expect(find.text('رفض'), findsOneWidget);
  });

  testWidgets('reject requires note', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'pending',
          canSubmit: false,
          canReview: true,
          canEditMarks: false,
        ),
      ),
    );
    await _tapVisible(tester, find.text('رفض'));
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('السبب مطلوب'), findsOneWidget);
  });

  testWidgets('رفض opens a confirmation dialog with the required copy '
      'after the reason is entered', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'pending',
          canSubmit: false,
          canReview: true,
          canEditMarks: false,
        ),
      ),
    );
    await _tapVisible(tester, find.text('رفض'));
    await tester.enterText(find.byType(TextField).last, 'سبب الرفض');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('تأكيد رفض التقرير'), findsOneWidget);
    expect(find.text('هل أنت متأكد من رفض تقرير التسوق؟'), findsOneWidget);
    expect(find.text('إلغاء'), findsOneWidget);
    expect(find.text('تأكيد الرفض'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation performs zero reject RPC calls', (
    tester,
  ) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'pending',
          canSubmit: false,
          canReview: true,
          canEditMarks: false,
        ),
      ),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('رفض'));
    await tester.enterText(find.byType(TextField).last, 'سبب الرفض');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء').last);
    await tester.pumpAndSettle();

    expect(shoppingService.reviewCallCount, 0);
    expect(find.text('تأكيد رفض التقرير'), findsNothing);
    // Still pending — cancel never touched the report state.
    expect(find.text('في انتظار المراجعة'), findsOneWidget);
  });

  testWidgets('confirming rejection invokes reject exactly once and shows '
      'the success message', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'pending',
          canSubmit: false,
          canReview: true,
          canEditMarks: false,
        ),
      ),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('رفض'));
    await tester.enterText(find.byType(TextField).last, 'سبب الرفض');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد الرفض'));
    await tester.pumpAndSettle();

    expect(shoppingService.reviewCallCount, 1);
    expect(shoppingService.lastReviewStatus, 'rejected');
    expect(shoppingService.lastReviewNote, 'سبب الرفض');
    expect(find.text('تم رفض التقرير'), findsOneWidget);
  });

  testWidgets('double-tapping تأكيد الرفض does not duplicate the RPC call', (
    tester,
  ) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'pending',
          canSubmit: false,
          canReview: true,
          canEditMarks: false,
        ),
      ),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('رفض'));
    await tester.enterText(find.byType(TextField).last, 'سبب الرفض');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    final confirmButton = find.text('تأكيد الرفض');
    await tester.tap(confirmButton);
    // Second tap lands after the dialog's own guard has already disabled
    // the button — asserting that is the point of this test, so the
    // resulting missed-hit-test warning is expected, not a bug.
    await tester.tap(confirmButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(shoppingService.reviewCallCount, 1);
  });

  testWidgets('failed rejection does not show success and keeps the report '
      'pending', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'pending',
          canSubmit: false,
          canReview: true,
          canEditMarks: false,
        ),
      ),
    )..reviewError = Exception('تعذر تحديث حالة التقرير');
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('رفض'));
    await tester.enterText(find.byType(TextField).last, 'سبب الرفض');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد الرفض'));
    await tester.pumpAndSettle();

    expect(shoppingService.reviewCallCount, 1);
    expect(find.text('تم رفض التقرير'), findsNothing);
    expect(find.text('في انتظار المراجعة'), findsOneWidget);
    expect(find.text('قبول'), findsOneWidget);
    expect(find.text('رفض'), findsOneWidget);
  });

  testWidgets('accept calls reviewShoppingReport(status=accepted)', (
    tester,
  ) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(
        hasReportObject: true,
        report: TeamShoppingReport(
          submittedAt: DateTime(2026, 7, 5),
          leaderStatus: 'pending',
          canSubmit: false,
          canReview: true,
          canEditMarks: false,
        ),
      ),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('قبول'));
    expect(shoppingService.lastReviewStatus, 'accepted');
  });

  testWidgets('non-responsible member sees read-only view', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        canMark: false,
        includeResponsible: false,
      ),
    );
    expect(find.text('اشتريت'), findsNothing);
    expect(find.text('لم أشترِ'), findsNothing);
    expect(find.text('إرسال القائمة للقائد'), findsNothing);
    expect(find.text('خبز'), findsOneWidget);
  });

  testWidgets(
    'failed shopping load shows section-level error without crashing',
    (tester) async {
      await _pump(tester, shoppingError: 'Network error');

      expect(find.text('Network error'), findsOneWidget);
      expect(find.byType(TeamDetailScreen), findsOneWidget);
    },
  );

  testWidgets('shopping card renders at 320px without new overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester);

    expect(find.text('تسوق اليوم'), findsOneWidget);
    expect(find.text('خبز'), findsOneWidget);
    expect(find.text('حليب'), findsOneWidget);
  });

  testWidgets('empty list allows daily-role dispatch', (tester) async {
    final turnService = _FakeTurnService(state: _turnStateWithoutToday());
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: turnService,
        shoppingService: _FakeTeamShoppingService(
          overview: _sampleShoppingOverview(itemCount: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollToTurnCard(tester);

    final start = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'بدء دور اليوم'),
    );
    expect(start.onPressed, isNotNull);
    await tester.tap(find.widgetWithText(ElevatedButton, 'بدء دور اليوم'));
    await tester.pumpAndSettle();
    expect(turnService.startDailyRoleCallCount, 1);
  });

  testWidgets('empty list allows daily-role final completion', (tester) async {
    final turnService = _FakeTurnService(
      state: TeamTurnState(
        canManageTurns: true,
        todayTurn: TurnEntry(
          id: 'turn-1',
          turnDate: '2026-07-01',
          status: 'pending',
          memberId: 'mem-1',
          displayName: 'محمد',
          position: 1,
          memberCompletedAt: DateTime(2026, 7, 1, 9),
        ),
        history: const [],
      ),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: turnService,
        shoppingService: _FakeTeamShoppingService(
          overview: _sampleShoppingOverview(itemCount: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollToTurnCard(tester);
    final complete = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'اكتمل دور اليوم'),
    );
    expect(complete.onPressed, isNotNull);
  });

  testWidgets('shopping items do not change daily-role dispatch', (
    tester,
  ) async {
    final turnService = _FakeTurnService(state: _turnStateWithoutToday());
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: turnService,
        shoppingService: _FakeTeamShoppingService(
          overview: _sampleShoppingOverview(itemCount: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollToTurnCard(tester);

    final startFinder = find.widgetWithText(ElevatedButton, 'بدء دور اليوم');
    expect(tester.widget<ElevatedButton>(startFinder).onPressed, isNotNull);
    await tester.tap(startFinder);
    await tester.pumpAndSettle();
    expect(turnService.startDailyRoleCallCount, 1);
  });

  testWidgets('adding a shopping item keeps daily-role dispatch available', (
    tester,
  ) async {
    final turnService = _FakeTurnService(state: _turnStateWithoutToday());
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(itemCount: 0, canEditList: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: turnService,
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'اسم العنصر'), 'خبز');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    await _scrollToTurnCard(tester);

    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'بدء دور اليوم'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('removing final item keeps daily-role dispatch available', (
    tester,
  ) async {
    final turnService = _FakeTurnService(state: _turnStateWithoutToday());
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(itemCount: 1, canEditList: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: turnService,
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );
    await tester.tap(find.text('إزالة'));
    await tester.pumpAndSettle();
    await _scrollToTurnCard(tester);

    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'بدء دور اليوم'),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.text('لا يمكن إرسال تقرير فارغ'), findsOneWidget);
  });

  testWidgets('empty shopping state remains 320px safe', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        itemCount: 0,
        hasReportObject: true,
        report: const TeamShoppingReport(
          canSubmit: true,
          canReview: false,
          canEditMarks: true,
        ),
      ),
    );

    expect(
      find.text('أضف عنصرًا واحدًا على الأقل قبل مشاركة القائمة'),
      findsOneWidget,
    );
    expect(find.text('لا يمكن إرسال تقرير فارغ'), findsOneWidget);
  });

  testWidgets('skippable missed turn shows recovery panel details', (
    tester,
  ) async {
    await _pump(tester, turnState: _blockedTurnState());
    await _scrollToTurnCard(tester);

    expect(find.text('أكمل الدور السابق أولاً'), findsOneWidget);
    expect(find.text('يوجد دور سابق لم يبدأ بعد'), findsOneWidget);
    expect(find.text('العضو: سالم'), findsOneWidget);
    expect(find.text('التاريخ: ${ltrFragment('2026-07-04')}'), findsOneWidget);
    expect(find.text('تخطّي الدور السابق'), findsOneWidget);
    expect(find.text('بدء دور اليوم'), findsNothing);
  });

  testWidgets('started previous turn does not show skip button', (
    tester,
  ) async {
    await _pump(tester, turnState: _blockedTurnState(canSkip: false));
    await _scrollToTurnCard(tester);

    expect(find.text('أكمل الدور السابق أولاً'), findsOneWidget);
    expect(find.text('تخطّي الدور السابق'), findsNothing);
    expect(find.text('يوجد دور سابق لم يبدأ بعد'), findsNothing);
  });

  testWidgets('tapping missed-turn skip opens optional reason dialog', (
    tester,
  ) async {
    await _pump(tester, turnState: _blockedTurnState());
    await _scrollToTurnCard(tester);
    await _tapVisible(tester, find.text('تخطّي الدور السابق'));

    expect(find.text('سبب التخطي'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'سبب التخطي'), findsOneWidget);
  });

  testWidgets('empty missed-turn skip reason is allowed', (tester) async {
    final turnService = _FakeTurnService(state: _blockedTurnState());
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: turnService,
        shoppingService: _FakeTeamShoppingService(
          overview: _sampleShoppingOverview(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollToTurnCard(tester);

    await _tapVisible(tester, find.text('تخطّي الدور السابق'));
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(turnService.skipMissedTurnCallCount, 1);
    expect(turnService.lastSkipTeamId, 'team-1');
    expect(turnService.lastSkipTurnId, 'prev-turn');
    expect(turnService.lastSkipReason, '');
    expect(find.text('تم تخطّي الدور السابق'), findsOneWidget);
    expect(find.text('بدء دور اليوم'), findsOneWidget);
  });

  testWidgets('non-empty missed-turn skip reason is sent', (tester) async {
    final turnService = _FakeTurnService(state: _blockedTurnState());
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: turnService,
        shoppingService: _FakeTeamShoppingService(
          overview: _sampleShoppingOverview(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollToTurnCard(tester);

    await _tapVisible(tester, find.text('تخطّي الدور السابق'));
    await tester.enterText(
      find.widgetWithText(TextField, 'سبب التخطي'),
      'غائب',
    );
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(turnService.lastSkipReason, 'غائب');
  });

  testWidgets('missed-turn skip reason over 300 chars is rejected', (
    tester,
  ) async {
    final turnService = _FakeTurnService(state: _blockedTurnState());
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: turnService,
        shoppingService: _FakeTeamShoppingService(
          overview: _sampleShoppingOverview(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollToTurnCard(tester);

    await _tapVisible(tester, find.text('تخطّي الدور السابق'));
    await tester.enterText(
      find.widgetWithText(TextField, 'سبب التخطي'),
      List.filled(301, 'ا').join(),
    );
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('النص طويل جداً'), findsOneWidget);
    expect(turnService.skipMissedTurnCallCount, 0);
  });

  testWidgets('skipped turn history displays skipped status and reason', (
    tester,
  ) async {
    await _pump(
      tester,
      turnState: const TeamTurnState(
        canManageTurns: true,
        todayTurn: null,
        nextMember: null,
        lastCompletedTurn: null,
        history: [
          TurnEntry(
            id: 'skipped-turn',
            turnDate: '2026-07-04',
            status: 'skipped',
            memberId: 'mem-2',
            displayName: 'سالم',
            position: 2,
            skipReason: 'غائب',
          ),
        ],
      ),
    );
    await _scrollToTurnCard(tester);

    expect(find.text('تم التخطي'), findsOneWidget);
    expect(find.text('سبب التخطي: غائب'), findsOneWidget);
  });

  testWidgets('turn recovery panel renders at 320px without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, turnState: _blockedTurnState());
    await _scrollToTurnCard(tester);

    expect(find.text('تخطّي الدور السابق'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canEditList=false hides تعديل القائمة and إضافة عنصر', (
    tester,
  ) async {
    await _pump(tester, overview: _sampleShoppingOverview(canEditList: false));
    expect(find.text('تعديل القائمة'), findsNothing);
    expect(find.text('إضافة عنصر'), findsNothing);
  });

  testWidgets('canEditList=true shows تعديل القائمة', (tester) async {
    await _pump(tester, overview: _sampleShoppingOverview(canEditList: true));
    expect(find.text('تعديل القائمة'), findsOneWidget);
    expect(find.text('إضافة عنصر'), findsOneWidget);
  });

  testWidgets('leader can open add item form', (tester) async {
    await _pump(tester, overview: _sampleShoppingOverview(canEditList: true));
    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    expect(find.text('اسم العنصر'), findsOneWidget);
    expect(find.text('ملاحظة الكمية'), findsOneWidget);
    expect(find.text('أساسي'), findsWidgets);
    expect(find.text('اختياري'), findsWidgets);
    expect(find.text('حفظ'), findsOneWidget);
    expect(find.text('إلغاء'), findsOneWidget);
  });

  testWidgets('empty name validation works', (tester) async {
    await _pump(tester, overview: _sampleShoppingOverview(canEditList: true));
    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('اسم العنصر مطلوب'), findsOneWidget);
  });

  testWidgets('add item calls TeamShoppingService.addItem', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canEditList: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'اسم العنصر'), 'أرز');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastAddedName, 'أرز');
    expect(find.text('اسم العنصر'), findsNothing);
  });

  testWidgets('edit item calls TeamShoppingService.updateItem', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canEditList: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.widgetWithIcon(IconButton, Icons.edit_outlined),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'اسم العنصر'),
      'خبز محدث',
    );
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastUpdatedItemId, 'item-0');
    expect(shoppingService.lastUpdatedName, 'خبز محدث');
  });

  testWidgets('remove item calls TeamShoppingService.deactivateItem', (
    tester,
  ) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canEditList: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );

    expect(find.text('إزالة العنصر'), findsOneWidget);
    await tester.tap(find.text('إزالة'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastDeactivatedItemId, 'item-0');
  });

  testWidgets('normal member cannot see edit/remove controls', (tester) async {
    await _pump(tester, overview: _sampleShoppingOverview(canEditList: false));
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets(
    'permission matrix: canEditList=true, canMark=false shows edit controls, hides checkbox, no mark call',
    (tester) async {
      final shoppingService = _FakeTeamShoppingService(
        overview: _sampleShoppingOverview(canEditList: true, canMark: false),
      );
      await tester.pumpWidget(
        _buildTest(
          _FakeAuthService(),
          teamService: _FakeTeamService(detail: _sampleTeamDetail()),
          turnService: _FakeTurnService(state: _sampleTurnState()),
          shoppingService: shoppingService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('تعديل القائمة'), findsOneWidget);
      expect(find.text('إضافة عنصر'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsWidgets);
      expect(find.byIcon(Icons.delete_outline), findsWidgets);
      expect(find.byType(Checkbox), findsNothing);
      expect(shoppingService.lastMarkedItemId, isNull);
    },
  );

  testWidgets(
    'permission matrix: canEditList=false, canMark=true shows checkbox, hides edit controls, marks via service',
    (tester) async {
      final shoppingService = _FakeTeamShoppingService(
        overview: _sampleShoppingOverview(canEditList: false, canMark: true),
      );
      await tester.pumpWidget(
        _buildTest(
          _FakeAuthService(),
          teamService: _FakeTeamService(detail: _sampleTeamDetail()),
          turnService: _FakeTurnService(state: _sampleTurnState()),
          shoppingService: shoppingService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('تعديل القائمة'), findsNothing);
      expect(find.text('إضافة عنصر'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byType(Checkbox), findsWidgets);

      await _tapVisible(tester, find.text('اشتريت'));

      expect(shoppingService.lastMarkedItemId, 'item-0');
      expect(shoppingService.lastMarkedBought, true);
    },
  );

  testWidgets(
    'permission matrix: canEditList=true, canMark=true shows both, marks via service',
    (tester) async {
      final shoppingService = _FakeTeamShoppingService(
        overview: _sampleShoppingOverview(canEditList: true, canMark: true),
      );
      await tester.pumpWidget(
        _buildTest(
          _FakeAuthService(),
          teamService: _FakeTeamService(detail: _sampleTeamDetail()),
          turnService: _FakeTurnService(state: _sampleTurnState()),
          shoppingService: shoppingService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('تعديل القائمة'), findsOneWidget);
      expect(find.text('إضافة عنصر'), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);

      await _tapVisible(tester, find.text('اشتريت'));

      expect(shoppingService.lastMarkedItemId, 'item-0');
      expect(shoppingService.lastMarkedBought, true);
    },
  );

  testWidgets(
    'permission matrix: canEditList=false, canMark=false is fully read-only',
    (tester) async {
      await _pump(
        tester,
        overview: _sampleShoppingOverview(canEditList: false, canMark: false),
      );

      expect(find.text('تعديل القائمة'), findsNothing);
      expect(find.text('إضافة عنصر'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    },
  );

  testWidgets('existing TeamDetailScreen behavior still passes', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('فريق الغداء'), findsAtLeast(1));
    expect(find.byType(ZadSectionHeader), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('أعضاء الفريق'), findsOneWidget);
    expect(find.text('محمد'), findsWidgets);
  });

  testWidgets('total member count line isolates the number as LTR', (
    tester,
  ) async {
    await _pump(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    // _sampleTeamDetail() has exactly one member.
    expect(find.text('العدد الكلي: ${ltrFragment('1')}'), findsOneWidget);
  });

  testWidgets('item row shows price when available', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(firstItemPrice: 150.0),
    );
    expect(find.text('السعر: ${ltrFragment('150 MRU')}'), findsOneWidget);
  });

  testWidgets('item row shows no price text when price is null', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.textContaining('MRU'), findsNothing);
  });

  testWidgets('add sheet shows السعر field', (tester) async {
    await _pump(tester, overview: _sampleShoppingOverview(canEditList: true));
    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    expect(find.text('السعر'), findsOneWidget);
    // Two "MRU" texts now: the mru_value unit chip and the price suffix.
    expect(find.text('MRU'), findsNWidgets(2));
  });

  testWidgets('empty price submits null', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canEditList: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'اسم العنصر'), 'أرز');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastAddedPrice, isNull);
  });

  testWidgets('valid price submits numeric value', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canEditList: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'اسم العنصر'), 'أرز');
    await tester.enterText(find.widgetWithText(TextField, 'السعر'), '150');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastAddedPrice, 150.0);
  });

  testWidgets('invalid price shows أدخل سعرًا صحيحًا', (tester) async {
    await _pump(tester, overview: _sampleShoppingOverview(canEditList: true));
    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'اسم العنصر'), 'أرز');
    await tester.enterText(find.widgetWithText(TextField, 'السعر'), 'abc');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('أدخل سعرًا صحيحًا'), findsOneWidget);
  });

  testWidgets('edit sheet pre-fills existing price', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        canEditList: true,
        firstItemPrice: 150.0,
      ),
    );
    await _tapVisible(
      tester,
      find.widgetWithIcon(IconButton, Icons.edit_outlined),
    );

    expect(find.widgetWithText(TextField, '150'), findsOneWidget);
  });

  testWidgets('edit with cleared price submits null', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(
        canEditList: true,
        firstItemPrice: 150.0,
      ),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.widgetWithIcon(IconButton, Icons.edit_outlined),
    );

    await tester.enterText(find.widgetWithText(TextField, '150'), '');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastUpdatedPrice, isNull);
  });

  testWidgets('add sheet shows quantity field and exactly five unit labels', (
    tester,
  ) async {
    await _pump(tester, overview: _sampleShoppingOverview(canEditList: true));
    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'الكمية'), findsOneWidget);
    expect(find.text('كغ'), findsOneWidget);
    expect(find.text('بكط'), findsOneWidget);
    expect(find.text('بطة'), findsOneWidget);
    expect(find.text('MRU'), findsWidgets);
    expect(find.text('أخرى'), findsOneWidget);
    expect(find.text('وحدة'), findsNothing);
  });

  testWidgets('selecting أخرى shows the required custom-unit field', (
    tester,
  ) async {
    await _pump(tester, overview: _sampleShoppingOverview(canEditList: true));
    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'اسم الوحدة'), findsNothing);

    await tester.tap(find.text('أخرى'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'اسم الوحدة'), findsOneWidget);
  });

  testWidgets('blank custom unit is rejected', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canEditList: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'اسم العنصر'),
      'زيت زيتون',
    );
    await tester.enterText(find.widgetWithText(TextField, 'الكمية'), '1');
    await tester.tap(find.text('أخرى'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastAddedQuantityUnit, isNull);
    expect(find.text('أدخل اسم الوحدة'), findsOneWidget);
  });

  testWidgets('trimmed custom unit is submitted', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canEditList: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'اسم العنصر'),
      'زيت زيتون',
    );
    await tester.enterText(find.widgetWithText(TextField, 'الكمية'), '1');
    await tester.tap(find.text('أخرى'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'اسم الوحدة'),
      '  صندوق كبير  ',
    );
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastAddedQuantityUnit, 'صندوق كبير');
  });

  testWidgets('choosing a standard unit hides and clears the custom input', (
    tester,
  ) async {
    await _pump(tester, overview: _sampleShoppingOverview(canEditList: true));
    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('أخرى'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'اسم الوحدة'),
      'صندوق',
    );

    await tester.tap(find.text('كغ'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'اسم الوحدة'), findsNothing);

    await tester.tap(find.text('أخرى'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'اسم الوحدة'),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('editing preserves an existing custom unit', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(
        canEditList: true,
        firstItemQuantityValue: 3.0,
        firstItemQuantityUnit: 'صندوق كبير',
      ),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.widgetWithIcon(IconButton, Icons.edit_outlined),
    );

    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'أخرى'),
    );
    expect(chip.selected, isTrue);
    expect(find.widgetWithText(TextField, 'صندوق كبير'), findsOneWidget);

    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastUpdatedQuantityUnit, 'صندوق كبير');
  });

  testWidgets('historical unknown units display safely', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        items: [
          const TeamShoppingItem(
            id: 'legacy-1',
            name: 'سكر',
            quantityValue: 5,
            quantityUnit: 'piece',
            isRequired: true,
            position: 1,
            bought: false,
          ),
          const TeamShoppingItem(
            id: 'legacy-2',
            name: 'دقيق',
            quantityValue: 1,
            quantityUnit: 'litre',
            isRequired: false,
            position: 2,
            bought: false,
          ),
        ],
      ),
    );

    expect(find.text('الكمية: ${ltrFragment('5 وحدة')}'), findsOneWidget);
    expect(find.text('الكمية: ${ltrFragment('1 litre')}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shopping item sheet with custom unit fits at 320px in RTL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, overview: _sampleShoppingOverview(canEditList: true));
    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('أخرى'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'اسم الوحدة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'entering 2 and selecting كغ submits quantityValue=2 and quantityUnit=kg',
    (tester) async {
      final shoppingService = _FakeTeamShoppingService(
        overview: _sampleShoppingOverview(canEditList: true),
      );
      await tester.pumpWidget(
        _buildTest(
          _FakeAuthService(),
          teamService: _FakeTeamService(detail: _sampleTeamDetail()),
          turnService: _FakeTurnService(state: _sampleTurnState()),
          shoppingService: shoppingService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('إضافة عنصر'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'اسم العنصر'),
        'أرز',
      );
      await tester.enterText(find.widgetWithText(TextField, 'الكمية'), '2');
      await tester.tap(find.text('كغ'));
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(shoppingService.lastAddedQuantityValue, 2.0);
      expect(shoppingService.lastAddedQuantityUnit, 'kg');
    },
  );

  testWidgets('selecting MRU submits quantityUnit=mru_value', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canEditList: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'اسم العنصر'), 'زيت');
    await tester.enterText(find.widgetWithText(TextField, 'الكمية'), '10');
    await tester.tap(find.widgetWithText(ChoiceChip, 'MRU'));
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastAddedQuantityValue, 10.0);
    expect(shoppingService.lastAddedQuantityUnit, 'mru_value');
  });

  testWidgets('quantity note-only existing item still displays correctly', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('2 رغيف'), findsOneWidget);
  });

  testWidgets('structured quantity displays as الكمية: 2 كغ', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(
        firstItemQuantityValue: 2.0,
        firstItemQuantityUnit: 'kg',
      ),
    );
    // Exact match (label outside, LRI/PDI-wrapped fragment inside) proves
    // the fix directly: this string only matches if the isolate marks are
    // present exactly around "2 كغ" and nowhere else.
    expect(find.text('الكمية: ${ltrFragment('2 كغ')}'), findsOneWidget);
  });

  testWidgets(
    'mru_value quantity with price displays separately: الكمية and السعر',
    (tester) async {
      await _pump(
        tester,
        overview: _sampleShoppingOverview(
          firstItemQuantityValue: 10.0,
          firstItemQuantityUnit: 'mru_value',
          firstItemPrice: 10.0,
        ),
      );
      expect(find.text('الكمية: ${ltrFragment('10 MRU')}'), findsOneWidget);
      expect(find.text('السعر: ${ltrFragment('10 MRU')}'), findsOneWidget);
    },
  );

  testWidgets('clearing structured quantity submits null/null', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(
        canEditList: true,
        firstItemQuantityValue: 2.0,
        firstItemQuantityUnit: 'kg',
      ),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: _FakeTeamService(detail: _sampleTeamDetail()),
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.widgetWithIcon(IconButton, Icons.edit_outlined),
    );

    await tester.enterText(find.widgetWithText(TextField, '2'), '');
    await tester.pump();
    // deselect the pre-selected chip
    await tester.tap(find.widgetWithText(ChoiceChip, 'كغ'));
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastUpdatedQuantityValue, isNull);
    expect(shoppingService.lastUpdatedQuantityUnit, isNull);
  });

  testWidgets('validation rejects quantity number without unit', (
    tester,
  ) async {
    await _pump(tester, overview: _sampleShoppingOverview(canEditList: true));
    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'اسم العنصر'), 'أرز');
    await tester.enterText(find.widgetWithText(TextField, 'الكمية'), '2');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('اختر نوع الكمية'), findsOneWidget);
  });

  testWidgets('validation rejects unit without quantity number', (
    tester,
  ) async {
    await _pump(tester, overview: _sampleShoppingOverview(canEditList: true));
    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'اسم العنصر'), 'أرز');
    await tester.tap(find.text('كغ'));
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('أدخل رقم الكمية'), findsOneWidget);
  });

  testWidgets('validation rejects negative/invalid quantity value', (
    tester,
  ) async {
    await _pump(tester, overview: _sampleShoppingOverview(canEditList: true));
    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'اسم العنصر'), 'أرز');
    await tester.enterText(find.widgetWithText(TextField, 'الكمية'), '-1');
    await tester.tap(find.text('كغ'));
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('أدخل كمية صحيحة'), findsOneWidget);
  });

  // Gate 41.1: lock in that these actions already update local state from
  // the RPC's returned data instead of re-fetching the whole team/shopping
  // list (see Gate 41.0 plan). These assert call counts stay at whatever
  // they were right after initial load, not a hardcoded "1", so they don't
  // become brittle if a later gate legitimately adds another read.

  testWidgets('mark bought does not call full team/shopping reload', (
    tester,
  ) async {
    final teamService = _FakeTeamService(detail: _sampleTeamDetail());
    final turnService = _FakeTurnService(state: _sampleTurnState());
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canMark: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: teamService,
        turnService: turnService,
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    final teamDetailCalls = teamService.getTeamDetailCallCount;
    final shoppingListCalls = shoppingService.getShoppingListCallCount;

    await _tapVisible(tester, find.byType(Checkbox));

    expect(shoppingService.lastMarkedItemId, 'item-0');
    expect(shoppingService.lastMarkedBought, true);
    expect(find.byType(Checkbox), findsNWidgets(2));

    expect(teamService.getTeamDetailCallCount, teamDetailCalls);
    expect(shoppingService.getShoppingListCallCount, shoppingListCalls);
  });

  testWidgets('unmark bought does not call full team/shopping reload', (
    tester,
  ) async {
    final teamService = _FakeTeamService(detail: _sampleTeamDetail());
    final turnService = _FakeTurnService(state: _sampleTurnState());
    final shoppingService = _FakeTeamShoppingService(
      // item-1 ('حليب') is bought by default in _sampleShoppingOverview.
      overview: _sampleShoppingOverview(canMark: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: teamService,
        turnService: turnService,
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    final teamDetailCalls = teamService.getTeamDetailCallCount;
    final shoppingListCalls = shoppingService.getShoppingListCallCount;

    await _tapVisible(tester, find.byType(Checkbox).last);

    expect(shoppingService.lastMarkedItemId, 'item-1');
    expect(shoppingService.lastMarkedBought, false);

    expect(teamService.getTeamDetailCallCount, teamDetailCalls);
    expect(shoppingService.getShoppingListCallCount, shoppingListCalls);
  });

  testWidgets('add shopping item does not call full team/shopping reload', (
    tester,
  ) async {
    final teamService = _FakeTeamService(detail: _sampleTeamDetail());
    final turnService = _FakeTurnService(state: _sampleTurnState());
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canEditList: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: teamService,
        turnService: turnService,
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    final teamDetailCalls = teamService.getTeamDetailCallCount;
    final shoppingListCalls = shoppingService.getShoppingListCallCount;

    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'اسم العنصر'), 'أرز');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastAddedName, 'أرز');
    expect(find.text('اسم العنصر'), findsNothing);
    // itemCount 2 -> 3 in the fake's regenerated overview: the new item
    // is visibly reflected without a re-fetch.
    expect(find.byType(Checkbox), findsNWidgets(3));

    expect(teamService.getTeamDetailCallCount, teamDetailCalls);
    expect(shoppingService.getShoppingListCallCount, shoppingListCalls);
  });

  testWidgets('edit shopping item does not call full team/shopping reload', (
    tester,
  ) async {
    final teamService = _FakeTeamService(detail: _sampleTeamDetail());
    final turnService = _FakeTurnService(state: _sampleTurnState());
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canEditList: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: teamService,
        turnService: turnService,
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    final teamDetailCalls = teamService.getTeamDetailCallCount;
    final shoppingListCalls = shoppingService.getShoppingListCallCount;

    await _tapVisible(
      tester,
      find.widgetWithIcon(IconButton, Icons.edit_outlined),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'اسم العنصر'),
      'خبز محدث',
    );
    await tester.enterText(find.widgetWithText(TextField, 'الكمية'), '3');
    await tester.tap(find.text('بكط'));
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastUpdatedItemId, 'item-0');
    expect(shoppingService.lastUpdatedName, 'خبز محدث');
    expect(shoppingService.lastUpdatedQuantityValue, 3.0);
    expect(shoppingService.lastUpdatedQuantityUnit, 'packet');
    expect(find.text('تسوق اليوم'), findsOneWidget);

    expect(teamService.getTeamDetailCallCount, teamDetailCalls);
    expect(shoppingService.getShoppingListCallCount, shoppingListCalls);
  });

  testWidgets('remove shopping item does not call full team/shopping reload', (
    tester,
  ) async {
    final teamService = _FakeTeamService(detail: _sampleTeamDetail());
    final turnService = _FakeTurnService(state: _sampleTurnState());
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canEditList: true),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: teamService,
        turnService: turnService,
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    final teamDetailCalls = teamService.getTeamDetailCallCount;
    final shoppingListCalls = shoppingService.getShoppingListCallCount;

    await _tapVisible(
      tester,
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );

    expect(find.text('إزالة العنصر'), findsOneWidget);
    await tester.tap(find.text('إزالة'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastDeactivatedItemId, 'item-0');
    // itemCount 2 -> 1 in the fake's regenerated overview: the removed
    // item is visibly gone without a re-fetch.
    expect(find.byType(Checkbox), findsNWidgets(1));

    expect(teamService.getTeamDetailCallCount, teamDetailCalls);
    expect(shoppingService.getShoppingListCallCount, shoppingListCalls);
  });

  testWidgets('member deactivate updates locally without reloading shopping or '
      'team detail (turn state refresh is expected)', (tester) async {
    final teamService = _FakeTeamService(
      detail: _teamDetailWithManageableMember(),
    )..deactivateResult = _teamDetailWithManageableMember(memberActive: false);
    final turnService = _FakeTurnService(state: _sampleTurnState());
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: teamService,
        turnService: turnService,
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    final teamDetailCalls = teamService.getTeamDetailCallCount;
    final shoppingListCalls = shoppingService.getShoppingListCallCount;
    final turnStateCalls = turnService.getTurnStateCallCount;

    await _tapVisible(
      tester,
      find.widgetWithIcon(IconButton, Icons.person_off_outlined),
    );

    expect(find.text('تعطيل العضو'), findsOneWidget);
    await tester.tap(find.text('تعطيل'));
    await tester.pumpAndSettle();

    expect(teamService.lastDeactivatedMemberId, 'mem-2');
    expect(find.text('غير نشط'), findsOneWidget);

    // Local update from the RPC's returned TeamDetail: no re-fetch.
    expect(teamService.getTeamDetailCallCount, teamDetailCalls);
    expect(shoppingService.getShoppingListCallCount, shoppingListCalls);
    // _applyMemberUpdate deliberately calls _refreshTurnState() after a
    // member change, so this partial reload is expected, not a bug.
    expect(turnService.getTurnStateCallCount, turnStateCalls + 1);
  });

  testWidgets('member removal protects leaders and reconciles once', (
    tester,
  ) async {
    final teamService =
        _FakeTeamService(detail: _teamDetailWithManageableMember())
          ..removalResult = TeamMemberRemoval(
            removed: true,
            detail: _teamDetailAfterRemoval(),
          );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: teamService,
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: _FakeTeamShoppingService(
          overview: _sampleShoppingOverview(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(find.byTooltip('إخراج العضو'), findsOneWidget);
    await _tapVisible(tester, find.byTooltip('إخراج العضو'));
    expect(find.text('إخراج سالم'), findsOneWidget);
    expect(
      find.text(
        'سيتم إخراج العضو من الفريق مع الاحتفاظ بالسجل السابق للمشاركة والدور.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('remove-member-reason')), findsOneWidget);
    expect(find.text('محمد'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('remove-member-reason')),
      '  انتقل  ',
    );
    await _tapVisible(tester, find.widgetWithText(FilledButton, 'إخراج العضو'));
    await tester.pumpAndSettle();

    expect(teamService.removeCallCount, 1);
    expect(teamService.lastRemovedMemberId, 'mem-2');
    expect(teamService.lastRemovalReason, '  انتقل  ');
    expect(find.text('سالم'), findsNothing);
    expect(find.text('تم إخراج العضو من الفريق'), findsOneWidget);
    expect(find.byTooltip('إخراج العضو'), findsNothing);
  });

  testWidgets('member removal blocks invalid input and duplicate submit', (
    tester,
  ) async {
    final pending = Completer<TeamMemberRemoval>();
    final teamService = _FakeTeamService(
      detail: _teamDetailWithManageableMember(),
    )..pendingRemoval = pending;
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: teamService,
        turnService: _FakeTurnService(state: _sampleTurnState()),
        shoppingService: _FakeTeamShoppingService(
          overview: _sampleShoppingOverview(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byTooltip('إخراج العضو'));

    final confirm = find.widgetWithText(FilledButton, 'إخراج العضو');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('remove-member-reason')),
      List.filled(301, 'ا').join(),
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('remove-member-reason')),
      'سبب',
    );
    await tester.pump();
    await tester.tap(confirm);
    await tester.tap(confirm);
    await tester.pump();
    expect(teamService.removeCallCount, 1);
    pending.completeError(Exception('network'));
    await tester.pumpAndSettle();
    expect(find.text('تعذر إخراج العضو. حاول مرة أخرى.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('remove-member-reason')))
          .controller!
          .text,
      'سبب',
    );
  });

  testWidgets('member removal dialog fits at 320px in RTL', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: TeamDetailScreen(
          authService: _FakeAuthService(),
          teamId: 'team-1',
          teamService: _FakeTeamService(
            detail: _teamDetailWithManageableMember(),
          ),
          turnService: _FakeTurnService(state: _sampleTurnState()),
          shoppingService: _FakeTeamShoppingService(
            overview: _sampleShoppingOverview(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byTooltip('إخراج العضو'));

    await tester.enterText(
      find.byKey(const Key('remove-member-reason')),
      'سبب واضح',
    );
    await tester.pump();
    expect(find.text('إخراج سالم'), findsOneWidget);
    expect(find.byKey(const Key('remove-member-reason')), findsOneWidget);
    expect(find.textContaining('300'), findsOneWidget);
    expect(find.text('إلغاء'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'إخراج العضو'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(AlertDialog))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'external member has removal action and idempotent response does not remove twice',
    (tester) async {
      final detail = _teamDetailWithManageableMember();
      final external = TeamMember(
        memberId: 'mem-2',
        displayName: 'سالم',
        memberKind: 'external',
        hasAccount: false,
        role: 'member',
        position: 2,
        isActive: true,
        joinedAt: DateTime(2026, 7, 1),
      );
      final teamService = _FakeTeamService(
        detail: TeamDetail(
          team: detail.team,
          members: [detail.members.first, external],
          canEdit: true,
          isMember: true,
        ),
      )..removalResult = TeamMemberRemoval(removed: false, detail: detail);
      await tester.pumpWidget(
        _buildTest(
          _FakeAuthService(),
          teamService: teamService,
          turnService: _FakeTurnService(state: _sampleTurnState()),
          shoppingService: _FakeTeamShoppingService(
            overview: _sampleShoppingOverview(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(find.byTooltip('إخراج العضو'), findsOneWidget);
      await _tapVisible(tester, find.byTooltip('إخراج العضو'));
      await tester.enterText(
        find.byKey(const Key('remove-member-reason')),
        'سبب',
      );
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'إخراج العضو'),
      );
      await tester.pumpAndSettle();
      expect(teamService.removeCallCount, 1);
      expect(find.text('سالم'), findsWidgets);
      expect(find.text('تم إخراج العضو من الفريق'), findsNothing);
    },
  );

  // Gate 41.2: once data is on screen, a re-load (pull-to-refresh,
  // didPopNext) must not tear down and replace the visible content with
  // the full-page spinner. These tests hang the fake RPC on a Completer so
  // the in-flight state can be inspected before completing it.

  testWidgets(
    'pull-to-refresh keeps existing content visible while refreshing',
    (tester) async {
      final teamService = _FakeTeamService(detail: _sampleTeamDetail());
      final turnService = _FakeTurnService(state: _sampleTurnState());
      final shoppingService = _FakeTeamShoppingService(
        overview: _sampleShoppingOverview(),
      );
      await tester.pumpWidget(
        _buildTest(
          _FakeAuthService(),
          teamService: teamService,
          turnService: turnService,
          shoppingService: shoppingService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('فريق الغداء'), findsAtLeast(1));
      expect(find.text('خبز'), findsOneWidget);

      final teamDetailCalls = teamService.getTeamDetailCallCount;
      teamService.pendingDetail = Completer<TeamDetail>();

      // A downward fling at the top of the list is the same gesture Flutter's
      // own RefreshIndicator tests use to trigger a real pull-to-refresh.
      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pump();
      // Let the indicator snap to its "refreshing" position, which is what
      // actually invokes onRefresh (_load), before inspecting state.
      await tester.pump(const Duration(milliseconds: 300));

      // Refresh is in flight: existing content must remain, and only the
      // small non-blocking indicator (not the full-page spinner) shows.
      expect(find.text('فريق الغداء'), findsAtLeast(1));
      expect(find.text('خبز'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      teamService.pendingDetail!.complete(_sampleTeamDetail());
      await tester.pumpAndSettle();

      expect(find.text('فريق الغداء'), findsAtLeast(1));
      expect(teamService.getTeamDetailCallCount, teamDetailCalls + 1);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('didPopNext background refresh does not blank existing content', (
    tester,
  ) async {
    final teamService = _FakeTeamService(detail: _sampleTeamDetail());
    final turnService = _FakeTurnService(state: _sampleTurnState());
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(),
    );
    await tester.pumpWidget(
      _buildRoutedTest(
        _FakeAuthService(),
        teamService: teamService,
        turnService: turnService,
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('فريق الغداء'), findsAtLeast(1));

    final navigator = Navigator.of(
      tester.element(find.byType(TeamDetailScreen)),
    );
    navigator.push(
      MaterialPageRoute(
        builder: (_) =>
            const Scaffold(body: Center(child: Text('dummy route'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('dummy route'), findsOneWidget);

    final teamDetailCalls = teamService.getTeamDetailCallCount;
    // Make the didPopNext-triggered reload hang so the in-flight state
    // can be inspected before it resolves.
    teamService.pendingDetail = Completer<TeamDetail>();

    navigator.pop();
    await tester.pump(); // let the pop settle and didPopNext's _load() start

    // Background refresh in flight after returning to TeamDetailScreen:
    // existing content must still be visible, no full-page spinner.
    expect(find.text('فريق الغداء'), findsAtLeast(1));
    expect(find.text('خبز'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    teamService.pendingDetail!.complete(_sampleTeamDetail());
    await tester.pumpAndSettle();

    expect(teamService.getTeamDetailCallCount, teamDetailCalls + 1);
    expect(find.text('فريق الغداء'), findsAtLeast(1));
  });

  testWidgets('shopping list refresh keeps old items visible while pending', (
    tester,
  ) async {
    final teamService = _FakeTeamService(detail: _sampleTeamDetail());
    final turnService = _FakeTurnService(state: _sampleTurnState());
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(),
    );
    await tester.pumpWidget(
      _buildTest(
        _FakeAuthService(),
        teamService: teamService,
        turnService: turnService,
        shoppingService: shoppingService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('خبز'), findsOneWidget);
    expect(find.text('حليب'), findsOneWidget);

    final shoppingListCalls = shoppingService.getShoppingListCallCount;
    shoppingService.pendingShoppingList = Completer<TeamShoppingOverview>();

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // getTeamDetail/getTurnState already resolved; _loadShopping is now
    // the one pending call (confirmed by the call-count assertion below).
    // The old item list must remain visible, not replaced by the
    // shopping card's own spinner.
    expect(find.text('خبز'), findsOneWidget);
    expect(find.text('حليب'), findsOneWidget);
    expect(shoppingService.getShoppingListCallCount, shoppingListCalls + 1);

    shoppingService.pendingShoppingList!.complete(_sampleShoppingOverview());
    await tester.pumpAndSettle();

    expect(find.text('خبز'), findsOneWidget);
    expect(shoppingService.getShoppingListCallCount, shoppingListCalls + 1);
  });
}

extension on TeamShoppingOverview {
  TeamShoppingOverview copyWith({
    List<TeamShoppingItem>? items,
    TeamShoppingReport? report,
    bool? hasReportObject,
    bool? canMark,
  }) => TeamShoppingOverview(
    turnDate: turnDate,
    responsibleMember: responsibleMember,
    canMark: canMark ?? this.canMark,
    canEditList: canEditList,
    report: report ?? this.report,
    hasReportObject: hasReportObject ?? this.hasReportObject,
    items: items ?? this.items,
  );
}
