import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_shopping_models.dart';

void main() {
  group('TeamShoppingOverview.fromJson', () {
    test('parses full payload with responsible member and items', () {
      final ov = TeamShoppingOverview.fromJson({
        'turn_date': '2026-07-05',
        'responsible_member': {
          'id': 'mem-1',
          'display_name': 'محمد',
        },
        'can_mark': true,
        'can_edit_list': false,
        'items': [
          {
            'id': 'item-1',
            'name': 'خبز',
            'quantity_note': '2 رغيف',
            'is_required': true,
            'position': 1,
            'bought': false,
            'marked_by_name': null,
            'marked_at': null,
          },
          {
            'id': 'item-2',
            'name': 'حليب',
            'quantity_note': null,
            'is_required': false,
            'position': 2,
            'bought': true,
            'marked_by_name': 'أحمد',
            'marked_at': '2026-07-05T08:30:00Z',
          },
        ],
      });

      expect(ov.turnDate, DateTime(2026, 7, 5));
      expect(ov.responsibleMember, isNotNull);
      expect(ov.responsibleMember!.id, 'mem-1');
      expect(ov.responsibleMember!.displayName, 'محمد');
      expect(ov.canMark, true);
      expect(ov.canEditList, false);
      expect(ov.items.length, 2);

      expect(ov.items[0].name, 'خبز');
      expect(ov.items[0].quantityNote, '2 رغيف');
      expect(ov.items[0].isRequired, true);
      expect(ov.items[0].position, 1);
      expect(ov.items[0].bought, false);
      expect(ov.items[0].markedByName, isNull);
      expect(ov.items[0].markedAt, isNull);

      expect(ov.items[1].name, 'حليب');
      expect(ov.items[1].isRequired, false);
      expect(ov.items[1].position, 2);
      expect(ov.items[1].bought, true);
      expect(ov.items[1].markedByName, 'أحمد');
      expect(ov.items[1].markedAt, DateTime.utc(2026, 7, 5, 8, 30));
    });

    test('parses null responsibleMember', () {
      final ov = TeamShoppingOverview.fromJson({
        'turn_date': null,
        'responsible_member': null,
        'can_mark': false,
        'can_edit_list': true,
        'items': [],
      });

      expect(ov.turnDate, isNull);
      expect(ov.responsibleMember, isNull);
      expect(ov.canMark, false);
      expect(ov.canEditList, true);
      expect(ov.items, isEmpty);
    });

    test('parses empty items list', () {
      final ov = TeamShoppingOverview.fromJson({
        'turn_date': null,
        'responsible_member': null,
        'can_mark': false,
        'can_edit_list': false,
        'items': [],
      });

      expect(ov.items, isEmpty);
    });
  });

  group('TeamShoppingItem.fromJson', () {
    test('parses bought item with marked info', () {
      final item = TeamShoppingItem.fromJson({
        'id': 'item-1',
        'name': 'خبز',
        'quantity_note': null,
        'is_required': true,
        'position': 1,
        'bought': true,
        'marked_by_name': 'أحمد',
        'marked_at': '2026-07-05T08:30:00Z',
      });

      expect(item.bought, true);
      expect(item.markedByName, 'أحمد');
      expect(item.markedAt, DateTime.utc(2026, 7, 5, 8, 30));
    });

    test('parses unbought item without marked info', () {
      final item = TeamShoppingItem.fromJson({
        'id': 'item-2',
        'name': 'حليب',
        'quantity_note': '1 لتر',
        'is_required': false,
        'position': 2,
        'bought': false,
        'marked_by_name': null,
        'marked_at': null,
      });

      expect(item.bought, false);
      expect(item.markedByName, isNull);
      expect(item.markedAt, isNull);
      expect(item.quantityNote, '1 لتر');
    });

    test('defaults is_required to true when missing', () {
      final item = TeamShoppingItem.fromJson({
        'id': 'item-3',
        'name': 'ماء',
        'position': 3,
        'bought': false,
      });

      expect(item.isRequired, true);
      expect(item.bought, false);
    });

    test('defaults bought to false when missing', () {
      final item = TeamShoppingItem.fromJson({
        'id': 'item-4',
        'name': 'شاي',
        'position': 4,
      });

      expect(item.bought, false);
    });
  });

  group('toJson roundtrip', () {
    test('TeamShoppingResponsibleMember roundtrip', () {
      final original = TeamShoppingResponsibleMember(
        id: 'mem-1',
        displayName: 'محمد',
      );
      final json = original.toJson();
      final restored = TeamShoppingResponsibleMember.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.displayName, original.displayName);
    });

    test('TeamShoppingItem roundtrip with all fields', () {
      final original = TeamShoppingItem(
        id: 'item-1',
        name: 'خبز',
        quantityNote: '2 رغيف',
        isRequired: true,
        position: 1,
        bought: true,
        markedByName: 'أحمد',
        markedAt: DateTime(2026, 7, 5, 8, 30),
      );
      final json = original.toJson();
      final restored = TeamShoppingItem.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.quantityNote, original.quantityNote);
      expect(restored.isRequired, original.isRequired);
      expect(restored.position, original.position);
      expect(restored.bought, original.bought);
      expect(restored.markedByName, original.markedByName);
      expect(restored.markedAt, original.markedAt);
    });

    test('TeamShoppingItem roundtrip with null optionals', () {
      final original = TeamShoppingItem(
        id: 'item-2',
        name: 'حليب',
        isRequired: false,
        position: 2,
        bought: false,
      );
      final json = original.toJson();
      final restored = TeamShoppingItem.fromJson(json);
      expect(restored.quantityNote, isNull);
      expect(restored.markedByName, isNull);
      expect(restored.markedAt, isNull);
      expect(restored.isRequired, false);
    });

    test('TeamShoppingOverview roundtrip with full payload', () {
      final responsible = TeamShoppingResponsibleMember(
        id: 'mem-1',
        displayName: 'محمد',
      );
      final items = [
        TeamShoppingItem(
          id: 'item-1',
          name: 'خبز',
          isRequired: true,
          position: 1,
          bought: false,
        ),
      ];
      final original = TeamShoppingOverview(
        turnDate: DateTime(2026, 7, 5),
        responsibleMember: responsible,
        canMark: true,
        canEditList: false,
        items: items,
      );
      final json = original.toJson();
      final restored = TeamShoppingOverview.fromJson(json);
      expect(restored.turnDate, original.turnDate);
      expect(restored.responsibleMember, isNotNull);
      expect(restored.responsibleMember!.id, responsible.id);
      expect(restored.canMark, original.canMark);
      expect(restored.canEditList, original.canEditList);
      expect(restored.items.length, 1);
      expect(restored.items.first.name, 'خبز');
    });

    test('TeamShoppingOverview roundtrip with null turnDate and responsibleMember', () {
      final original = TeamShoppingOverview(
        turnDate: null,
        responsibleMember: null,
        canMark: false,
        canEditList: false,
        items: const [],
      );
      final json = original.toJson();
      final restored = TeamShoppingOverview.fromJson(json);
      expect(restored.turnDate, isNull);
      expect(restored.responsibleMember, isNull);
      expect(restored.items, isEmpty);
    });
  });
}
