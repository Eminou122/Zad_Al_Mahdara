import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
          isRequired: i == 0,
          position: i + 1,
          bought: bought,
          markedByName: bought ? 'أحمد' : null,
          markedAt: bought ? DateTime(2026, 7, 5, 8, 30) : null,
          price: i == 0 ? firstItemPrice : null,
        );
      }),
    );

class _FakeTeamService extends TeamService {
  TeamDetail? detail;
  Object? error;

  _FakeTeamService({this.detail}) : super(AuthService());

  @override
  Future<TeamDetail> getTeamDetail(String teamId) async {
    if (error != null) throw error!;
    return detail ?? _sampleTeamDetail();
  }
}

class _FakeTurnService extends TeamTurnService {
  TeamTurnState? state;
  Object? error;

  _FakeTurnService({this.state}) : super(AuthService());

  @override
  Future<TeamTurnState> getTurnState(String teamId) async {
    if (error != null) throw error!;
    return state ?? _sampleTurnState();
  }
}

class _FakeTeamShoppingService extends TeamShoppingService {
  TeamShoppingOverview? overview;
  Object? error;

  String? lastMarkedItemId;
  bool? lastMarkedBought;

  String? lastAddedName;
  String? lastAddedQuantityNote;
  bool? lastAddedIsRequired;
  double? lastAddedPrice;

  String? lastUpdatedItemId;
  String? lastUpdatedName;
  double? lastUpdatedPrice;

  String? lastDeactivatedItemId;

  Object? actionError;

  _FakeTeamShoppingService({this.overview, this.error});

  @override
  Future<TeamShoppingOverview> getShoppingList({
    required String sessionToken,
    required String teamId,
    DateTime? date,
  }) async {
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
  }) async {
    if (actionError != null) throw actionError!;
    lastAddedName = name;
    lastAddedQuantityNote = quantityNote;
    lastAddedIsRequired = isRequired;
    lastAddedPrice = price;
    overview = _sampleShoppingOverview(
      canEditList: overview?.canEditList ?? true,
      itemCount: (overview?.items.length ?? 2) + 1,
      firstItemPrice: price,
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
  }) async {
    if (actionError != null) throw actionError!;
    lastUpdatedItemId = itemId;
    lastUpdatedName = name;
    lastUpdatedPrice = price;
    overview = _sampleShoppingOverview(
      canEditList: overview?.canEditList ?? true,
      itemCount: overview?.items.length ?? 2,
      firstItemPrice: price,
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

  testWidgets('item row shows price when available', (tester) async {
    await _pump(
      tester,
      overview: _sampleShoppingOverview(firstItemPrice: 150.0),
    );
    expect(find.text('150 MRU'), findsOneWidget);
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
    expect(find.text('MRU'), findsOneWidget);
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
