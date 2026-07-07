import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

TeamShoppingOverview _sampleShoppingOverview({
  bool canMark = true,
  bool canEditList = false,
  bool includeResponsible = true,
  int itemCount = 2,
  double? firstItemPrice,
  double? firstItemQuantityValue,
  String? firstItemQuantityUnit,
}) =>
    TeamShoppingOverview(
      turnDate: DateTime(2026, 7, 5),
      responsibleMember: includeResponsible
          ? TeamShoppingResponsibleMember(
              id: 'mem-1',
              displayName: 'محمد',
            )
          : null,
      canMark: canMark,
      canEditList: canEditList,
      items: List.generate(itemCount, (i) {
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
}

class _FakeTurnService extends TeamTurnService {
  TeamTurnState? state;
  Object? error;
  int getTurnStateCallCount = 0;

  _FakeTurnService({this.state}) : super(AuthService());

  @override
  Future<TeamTurnState> getTurnState(String teamId) async {
    getTurnStateCallCount++;
    if (error != null) throw error!;
    return state ?? _sampleTurnState();
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
  }) async {
    if (error != null) throw error!;
    lastMarkedItemId = itemId;
    lastMarkedBought = bought;
    overview = _sampleShoppingOverview(
      canMark: overview?.canMark ?? true,
      itemCount: overview?.items.length ?? 2,
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

class _FakeAuthService extends AuthService {
  @override
  String? get currentToken => 'test-token';
}

Widget _buildTest(
  AuthService authService, {
  TeamService? teamService,
  TeamTurnService? turnService,
  TeamShoppingService? shoppingService,
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
      turnService:
          _FakeTurnService(state: turnState ?? _sampleTurnState()),
      shoppingService: _FakeTeamShoppingService(
        overview: overview,
        error: shoppingError,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shopping section renders title قائمة المشتريات', (tester) async {
    await _pump(tester);
    expect(find.text('قائمة المشتريات'), findsOneWidget);
  });

  testWidgets('responsible member line renders', (tester) async {
    await _pump(tester);
    expect(find.textContaining('محمد'), findsWidgets);
    expect(find.textContaining('المسؤول اليوم:'), findsOneWidget);
  });

  testWidgets('empty list renders لم تتم إضافة عناصر بعد', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(itemCount: 0),
    );
    expect(find.text('لم تتم إضافة عناصر بعد'), findsOneWidget);
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
    await _pump(
      tester,
      overview: _sampleShoppingOverview(canMark: false),
    );
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('قائمة المشتريات'), findsOneWidget);
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

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(shoppingService.lastMarkedItemId, 'item-0');
    expect(shoppingService.lastMarkedBought, true);
  });

  testWidgets(
    'failed shopping load shows section-level error without crashing',
    (tester) async {
      await _pump(
        tester,
        shoppingError: 'Network error',
      );

      expect(find.text('Network error'), findsOneWidget);
      expect(find.byType(TeamDetailScreen), findsOneWidget);
    },
  );

  testWidgets(
    'shopping card renders at 320px without new overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(tester);

      expect(find.text('قائمة المشتريات'), findsOneWidget);
      expect(find.text('خبز'), findsOneWidget);
      expect(find.text('حليب'), findsOneWidget);
    },
  );

  testWidgets(
    'canEditList=false hides تعديل القائمة and إضافة عنصر',
    (tester) async {
      await _pump(
        tester,
        overview: _sampleShoppingOverview(canEditList: false),
      );
      expect(find.text('تعديل القائمة'), findsNothing);
      expect(find.text('إضافة عنصر'), findsNothing);
    },
  );

  testWidgets('canEditList=true shows تعديل القائمة', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(canEditList: true),
    );
    expect(find.text('تعديل القائمة'), findsOneWidget);
    expect(find.text('إضافة عنصر'), findsOneWidget);
  });

  testWidgets('leader can open add item form', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(canEditList: true),
    );
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
    await _pump(
      tester,
      overview: _sampleShoppingOverview(canEditList: true),
    );
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

    await tester.tap(find.widgetWithIcon(IconButton, Icons.edit_outlined).first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'اسم العنصر'),
      'خبز محدث',
    );
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastUpdatedItemId, 'item-0');
    expect(shoppingService.lastUpdatedName, 'خبز محدث');
  });

  testWidgets('remove item calls TeamShoppingService.deactivateItem', (tester) async {
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

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline).first);
    await tester.pumpAndSettle();

    expect(find.text('إزالة العنصر'), findsOneWidget);
    await tester.tap(find.text('إزالة'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastDeactivatedItemId, 'item-0');
  });

  testWidgets('normal member cannot see edit/remove controls', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(canEditList: false),
    );
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

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

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

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

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

  testWidgets('existing TeamDetailScreen behavior still passes', (tester) async {
    await _pump(tester);

    expect(find.text('فريق الغداء'), findsAtLeast(1));
    expect(find.byType(ZadSectionHeader), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('أعضاء الفريق'), findsOneWidget);
    expect(find.text('محمد'), findsWidgets);
  });

  testWidgets('total member count line isolates the number as LTR',
      (tester) async {
    await _pump(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
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

  testWidgets('item row shows no price text when price is null', (tester) async {
    await _pump(tester);
    expect(find.textContaining('MRU'), findsNothing);
  });

  testWidgets('add sheet shows السعر field', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(canEditList: true),
    );
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
    await _pump(
      tester,
      overview: _sampleShoppingOverview(canEditList: true),
    );
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
      overview: _sampleShoppingOverview(canEditList: true, firstItemPrice: 150.0),
    );
    await tester.tap(find.widgetWithIcon(IconButton, Icons.edit_outlined).first);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '150'), findsOneWidget);
  });

  testWidgets('edit with cleared price submits null', (tester) async {
    final shoppingService = _FakeTeamShoppingService(
      overview: _sampleShoppingOverview(canEditList: true, firstItemPrice: 150.0),
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

    await tester.tap(find.widgetWithIcon(IconButton, Icons.edit_outlined).first);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '150'), '');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastUpdatedPrice, isNull);
  });

  testWidgets('add sheet shows quantity field and all six unit labels',
      (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(canEditList: true),
    );
    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'الكمية'), findsOneWidget);
    expect(find.text('كغ'), findsOneWidget);
    expect(find.text('بكط'), findsOneWidget);
    expect(find.text('بطة'), findsOneWidget);
    expect(find.text('وحدة'), findsOneWidget);
    expect(find.text('MRU'), findsWidgets);
    expect(find.text('أخرى'), findsOneWidget);
  });

  testWidgets('entering 2 and selecting كغ submits quantityValue=2 and quantityUnit=kg',
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

    await tester.enterText(find.widgetWithText(TextField, 'اسم العنصر'), 'أرز');
    await tester.enterText(find.widgetWithText(TextField, 'الكمية'), '2');
    await tester.tap(find.text('كغ'));
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(shoppingService.lastAddedQuantityValue, 2.0);
    expect(shoppingService.lastAddedQuantityUnit, 'kg');
  });

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

  testWidgets('quantity note-only existing item still displays correctly',
      (tester) async {
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
  });

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

    await tester.tap(find.widgetWithIcon(IconButton, Icons.edit_outlined).first);
    await tester.pumpAndSettle();

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

  testWidgets('validation rejects quantity number without unit', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(canEditList: true),
    );
    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'اسم العنصر'), 'أرز');
    await tester.enterText(find.widgetWithText(TextField, 'الكمية'), '2');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('اختر نوع الكمية'), findsOneWidget);
  });

  testWidgets('validation rejects unit without quantity number', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(canEditList: true),
    );
    await tester.tap(find.text('إضافة عنصر'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'اسم العنصر'), 'أرز');
    await tester.tap(find.text('كغ'));
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('أدخل رقم الكمية'), findsOneWidget);
  });

  testWidgets('validation rejects negative/invalid quantity value',
      (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(canEditList: true),
    );
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

  testWidgets('mark bought does not call full team/shopping reload',
      (tester) async {
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

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(shoppingService.lastMarkedItemId, 'item-0');
    expect(shoppingService.lastMarkedBought, true);
    expect(find.byType(Checkbox), findsNWidgets(2));

    expect(teamService.getTeamDetailCallCount, teamDetailCalls);
    expect(shoppingService.getShoppingListCallCount, shoppingListCalls);
  });

  testWidgets('unmark bought does not call full team/shopping reload',
      (tester) async {
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

    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();

    expect(shoppingService.lastMarkedItemId, 'item-1');
    expect(shoppingService.lastMarkedBought, false);

    expect(teamService.getTeamDetailCallCount, teamDetailCalls);
    expect(shoppingService.getShoppingListCallCount, shoppingListCalls);
  });

  testWidgets('add shopping item does not call full team/shopping reload',
      (tester) async {
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

  testWidgets('edit shopping item does not call full team/shopping reload',
      (tester) async {
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

    await tester.tap(find.widgetWithIcon(IconButton, Icons.edit_outlined).first);
    await tester.pumpAndSettle();

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
    expect(find.text('قائمة المشتريات'), findsOneWidget);

    expect(teamService.getTeamDetailCallCount, teamDetailCalls);
    expect(shoppingService.getShoppingListCallCount, shoppingListCalls);
  });

  testWidgets('remove shopping item does not call full team/shopping reload',
      (tester) async {
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

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline).first);
    await tester.pumpAndSettle();

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

  testWidgets(
    'member deactivate updates locally without reloading shopping or '
    'team detail (turn state refresh is expected)',
    (tester) async {
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
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      final teamDetailCalls = teamService.getTeamDetailCallCount;
      final shoppingListCalls = shoppingService.getShoppingListCallCount;
      final turnStateCalls = turnService.getTurnStateCallCount;

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.person_off_outlined).first,
      );
      await tester.pumpAndSettle();

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
    },
  );

  // removeTeamMember/reactivateTeamMember share the exact same
  // _applyMemberUpdate code path exercised above (verified by reading
  // team_detail_screen.dart), so this one test covers the pattern for all
  // three member actions without duplicating near-identical fakes/tests.

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

  testWidgets(
    'didPopNext background refresh does not blank existing content',
    (tester) async {
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

      final navigator =
          Navigator.of(tester.element(find.byType(TeamDetailScreen)));
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
    },
  );

  testWidgets(
    'shopping list refresh keeps old items visible while pending',
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
    },
  );
}

extension on TeamShoppingOverview {
  TeamShoppingOverview copyWith({
    List<TeamShoppingItem>? items,
  }) =>
      TeamShoppingOverview(
        turnDate: turnDate,
        responsibleMember: responsibleMember,
        canMark: canMark,
        canEditList: canEditList,
        items: items ?? this.items,
      );
}
