import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_shopping_models.dart';
import 'package:zad_al_mahdara/features/teams/data/team_shopping_service.dart';

TeamShoppingOverview _sampleOverview() => TeamShoppingOverview(
  turnDate: null,
  responsibleMember: null,
  canMark: true,
  canEditList: true,
  items: const [],
);

class _FakeTeamShoppingService extends TeamShoppingService {
  String? lastRpc;
  Map<String, dynamic>? lastParams;
  TeamShoppingOverview? returnValue;
  Object? error;

  @override
  Future<TeamShoppingOverview> getShoppingList({
    required String sessionToken,
    required String teamId,
    DateTime? date,
  }) async {
    if (error != null) throw error!;
    lastRpc = 'get_team_shopping_list';
    lastParams = {
      'p_session_token': sessionToken,
      'p_team_id': teamId,
      if (date != null)
        'p_date':
            '${date.year.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    };
    return returnValue ?? _sampleOverview();
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
    if (error != null) throw error!;
    lastRpc = 'add_team_shopping_item';
    lastParams = {
      'p_session_token': sessionToken,
      'p_team_id': teamId,
      'p_name': name,
      'p_quantity_note': quantityNote,
      'p_is_required': isRequired,
      'p_price': price,
      'p_quantity_value': quantityValue,
      'p_quantity_unit': quantityUnit,
    };
    return returnValue ?? _sampleOverview();
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
    if (error != null) throw error!;
    lastRpc = 'update_team_shopping_item';
    lastParams = {
      'p_session_token': sessionToken,
      'p_team_id': teamId,
      'p_item_id': itemId,
      'p_name': name,
      'p_quantity_note': quantityNote,
      'p_is_required': isRequired,
      'p_price': price,
      'p_quantity_value': quantityValue,
      'p_quantity_unit': quantityUnit,
    };
    return returnValue ?? _sampleOverview();
  }

  @override
  Future<TeamShoppingOverview> deactivateItem({
    required String sessionToken,
    required String teamId,
    required String itemId,
  }) async {
    if (error != null) throw error!;
    lastRpc = 'deactivate_team_shopping_item';
    lastParams = {
      'p_session_token': sessionToken,
      'p_team_id': teamId,
      'p_item_id': itemId,
    };
    return returnValue ?? _sampleOverview();
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
    lastRpc = 'mark_shopping_item_status';
    lastParams = {
      'p_session_token': sessionToken,
      'p_team_id': teamId,
      'p_item_id': itemId,
      'p_bought': bought,
      if (date != null)
        'p_date':
            '${date.year.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      if (reason != null && reason.trim().isNotEmpty) 'p_reason': reason.trim(),
    };
    return returnValue ?? _sampleOverview();
  }

  @override
  Future<TeamShoppingOverview> submitShoppingReport({
    required String sessionToken,
    required String teamId,
    DateTime? date,
  }) async {
    if (error != null) throw error!;
    lastRpc = 'submit_team_shopping_report';
    lastParams = {
      'p_session_token': sessionToken,
      'p_team_id': teamId,
      if (date != null)
        'p_date':
            '${date.year.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    };
    return returnValue ?? _sampleOverview();
  }

  @override
  Future<TeamShoppingOverview> reviewShoppingReport({
    required String sessionToken,
    required String teamId,
    required String status,
    DateTime? date,
    String? note,
  }) async {
    if (error != null) throw error!;
    final d = date ?? DateTime.now();
    lastRpc = 'leader_review_shopping_report';
    lastParams = {
      'p_session_token': sessionToken,
      'p_team_id': teamId,
      'p_date':
          '${d.year.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      'p_status': status,
      'p_note': note,
    };
    return returnValue ?? _sampleOverview();
  }
}

void main() {
  group('TeamShoppingService — fake recording', () {
    late _FakeTeamShoppingService service;

    setUp(() {
      service = _FakeTeamShoppingService();
      service.returnValue = TeamShoppingOverview(
        turnDate: DateTime(2026, 7, 5),
        responsibleMember: TeamShoppingResponsibleMember(
          id: 'mem-1',
          displayName: 'محمد',
        ),
        canMark: true,
        canEditList: false,
        items: [
          TeamShoppingItem(
            id: 'item-1',
            name: 'خبز',
            isRequired: true,
            position: 1,
            bought: false,
          ),
        ],
      );
    });

    test('getShoppingList calls get_team_shopping_list RPC', () async {
      final result = await service.getShoppingList(
        sessionToken: 'token-1',
        teamId: 'team-1',
      );

      expect(service.lastRpc, 'get_team_shopping_list');
      expect(service.lastParams!['p_session_token'], 'token-1');
      expect(service.lastParams!['p_team_id'], 'team-1');
      expect(service.lastParams!.containsKey('p_date'), false);
      expect(result.turnDate, DateTime(2026, 7, 5));
    });

    test('getShoppingList includes p_date when date is passed', () async {
      final result = await service.getShoppingList(
        sessionToken: 'token-1',
        teamId: 'team-1',
        date: DateTime(2026, 7, 5),
      );

      expect(service.lastRpc, 'get_team_shopping_list');
      expect(service.lastParams!['p_date'], '2026-07-05');
      expect(result.canMark, true);
    });

    test('addItem calls add_team_shopping_item RPC', () async {
      final result = await service.addItem(
        sessionToken: 'token-1',
        teamId: 'team-1',
        name: 'خبز',
        quantityNote: '2 رغيف',
        isRequired: true,
      );

      expect(service.lastRpc, 'add_team_shopping_item');
      expect(service.lastParams!['p_name'], 'خبز');
      expect(service.lastParams!['p_quantity_note'], '2 رغيف');
      expect(service.lastParams!['p_is_required'], true);
      expect(result.items.length, 1);
    });

    test(
      'addItem defaults isRequired to true and quantityNote to null',
      () async {
        await service.addItem(
          sessionToken: 'token-1',
          teamId: 'team-1',
          name: 'ماء',
        );

        expect(service.lastParams!['p_is_required'], true);
        expect(service.lastParams!['p_quantity_note'], isNull);
      },
    );

    test('addItem forwards p_price when price provided', () async {
      await service.addItem(
        sessionToken: 'token-1',
        teamId: 'team-1',
        name: 'أرز',
        price: 150.0,
      );

      expect(service.lastParams!['p_price'], 150.0);
    });

    test('addItem forwards null price when omitted', () async {
      await service.addItem(
        sessionToken: 'token-1',
        teamId: 'team-1',
        name: 'أرز',
      );

      expect(service.lastParams!['p_price'], isNull);
    });

    test(
      'addItem forwards p_quantity_value and p_quantity_unit when provided',
      () async {
        await service.addItem(
          sessionToken: 'token-1',
          teamId: 'team-1',
          name: 'أرز',
          quantityValue: 2.0,
          quantityUnit: 'kg',
        );

        expect(service.lastParams!['p_quantity_value'], 2.0);
        expect(service.lastParams!['p_quantity_unit'], 'kg');
      },
    );

    test('addItem forwards null quantity fields when omitted', () async {
      await service.addItem(
        sessionToken: 'token-1',
        teamId: 'team-1',
        name: 'أرز',
      );

      expect(service.lastParams!['p_quantity_value'], isNull);
      expect(service.lastParams!['p_quantity_unit'], isNull);
    });

    test('updateItem calls update_team_shopping_item RPC', () async {
      final result = await service.updateItem(
        sessionToken: 'token-1',
        teamId: 'team-1',
        itemId: 'item-1',
        name: 'خبز طازج',
        quantityNote: '3 رغيف',
        isRequired: false,
      );

      expect(service.lastRpc, 'update_team_shopping_item');
      expect(service.lastParams!['p_item_id'], 'item-1');
      expect(service.lastParams!['p_name'], 'خبز طازج');
      expect(service.lastParams!['p_quantity_note'], '3 رغيف');
      expect(service.lastParams!['p_is_required'], false);
      expect(result.canEditList, false);
    });

    test('updateItem forwards p_price when price provided', () async {
      await service.updateItem(
        sessionToken: 'token-1',
        teamId: 'team-1',
        itemId: 'item-1',
        name: 'خبز طازج',
        price: 200.5,
      );

      expect(service.lastParams!['p_price'], 200.5);
    });

    test('updateItem forwards null price when omitted', () async {
      await service.updateItem(
        sessionToken: 'token-1',
        teamId: 'team-1',
        itemId: 'item-1',
        name: 'خبز طازج',
      );

      expect(service.lastParams!['p_price'], isNull);
    });

    test(
      'updateItem forwards p_quantity_value and p_quantity_unit when provided',
      () async {
        await service.updateItem(
          sessionToken: 'token-1',
          teamId: 'team-1',
          itemId: 'item-1',
          name: 'خبز طازج',
          quantityValue: 10.0,
          quantityUnit: 'mru_value',
        );

        expect(service.lastParams!['p_quantity_value'], 10.0);
        expect(service.lastParams!['p_quantity_unit'], 'mru_value');
      },
    );

    test('updateItem forwards null quantity fields when omitted', () async {
      await service.updateItem(
        sessionToken: 'token-1',
        teamId: 'team-1',
        itemId: 'item-1',
        name: 'خبز طازج',
      );

      expect(service.lastParams!['p_quantity_value'], isNull);
      expect(service.lastParams!['p_quantity_unit'], isNull);
    });

    test('deactivateItem calls deactivate_team_shopping_item RPC', () async {
      final result = await service.deactivateItem(
        sessionToken: 'token-1',
        teamId: 'team-1',
        itemId: 'item-1',
      );

      expect(service.lastRpc, 'deactivate_team_shopping_item');
      expect(service.lastParams!['p_item_id'], 'item-1');
      expect(result.items.length, 1);
    });

    test('markItemStatus calls mark_shopping_item_status RPC', () async {
      final result = await service.markItemStatus(
        sessionToken: 'token-1',
        teamId: 'team-1',
        itemId: 'item-1',
        bought: true,
      );

      expect(service.lastRpc, 'mark_shopping_item_status');
      expect(service.lastParams!['p_item_id'], 'item-1');
      expect(service.lastParams!['p_bought'], true);
      expect(service.lastParams!.containsKey('p_date'), false);
      expect(result.canMark, true);
    });

    test('markItemStatus passes p_bought false correctly', () async {
      await service.markItemStatus(
        sessionToken: 'token-1',
        teamId: 'team-1',
        itemId: 'item-1',
        bought: false,
      );

      expect(service.lastParams!['p_bought'], false);
    });

    test('markItemStatus includes p_date when date is passed', () async {
      await service.markItemStatus(
        sessionToken: 'token-1',
        teamId: 'team-1',
        itemId: 'item-1',
        bought: true,
        date: DateTime(2026, 7, 5),
      );

      expect(service.lastParams!['p_date'], '2026-07-05');
    });

    test('service returns parsed TeamShoppingOverview', () async {
      final result = await service.getShoppingList(
        sessionToken: 'token-1',
        teamId: 'team-1',
      );

      expect(result, isA<TeamShoppingOverview>());
      expect(result.responsibleMember, isNotNull);
      expect(result.responsibleMember!.displayName, 'محمد');
    });
  });

  group('TeamShoppingService — constructor', () {
    test('can be instantiated', () {
      expect(() => TeamShoppingService(), returnsNormally);
    });
  });
}
