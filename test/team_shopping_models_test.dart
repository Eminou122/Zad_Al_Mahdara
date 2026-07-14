import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_shopping_models.dart';

void main() {
  group('TeamShoppingOverview.fromJson', () {
    test('parses full payload with responsible member and items', () {
      final ov = TeamShoppingOverview.fromJson({
        'turn_date': '2026-07-05',
        'responsible_member': {'id': 'mem-1', 'display_name': 'محمد'},
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

    test('parses price null', () {
      final item = TeamShoppingItem.fromJson({
        'id': 'item-5',
        'name': 'سكر',
        'position': 5,
        'bought': false,
        'price': null,
      });

      expect(item.price, isNull);
    });

    test('parses price 0', () {
      final item = TeamShoppingItem.fromJson({
        'id': 'item-6',
        'name': 'ملح',
        'position': 6,
        'bought': false,
        'price': 0,
      });

      expect(item.price, 0.0);
    });

    test('parses price positive', () {
      final item = TeamShoppingItem.fromJson({
        'id': 'item-7',
        'name': 'أرز',
        'position': 7,
        'bought': false,
        'price': 150.5,
      });

      expect(item.price, 150.5);
    });

    test('missing price key does not crash and defaults to null', () {
      final item = TeamShoppingItem.fromJson({
        'id': 'item-8',
        'name': 'زيت',
        'position': 8,
        'bought': false,
      });

      expect(item.price, isNull);
    });

    test('parses quantity_value and quantity_unit', () {
      final item = TeamShoppingItem.fromJson({
        'id': 'item-9',
        'name': 'أرز',
        'position': 9,
        'bought': false,
        'quantity_value': 2,
        'quantity_unit': 'kg',
      });

      expect(item.quantityValue, 2.0);
      expect(item.quantityUnit, 'kg');
    });

    test('handles null quantity_value and quantity_unit', () {
      final item = TeamShoppingItem.fromJson({
        'id': 'item-10',
        'name': 'سكر',
        'position': 10,
        'bought': false,
        'quantity_value': null,
        'quantity_unit': null,
      });

      expect(item.quantityValue, isNull);
      expect(item.quantityUnit, isNull);
    });

    test('missing quantity_value/quantity_unit keys do not crash', () {
      final item = TeamShoppingItem.fromJson({
        'id': 'item-11',
        'name': 'شاي',
        'position': 11,
        'bought': false,
      });

      expect(item.quantityValue, isNull);
      expect(item.quantityUnit, isNull);
    });
  });

  group('TeamShoppingReport financial fields', () {
    test(
      'parses expected_total, actual_total, expense_id and financial metadata',
      () {
        final report = TeamShoppingReport.fromJson({
          'submitted_at': '2026-07-05T09:00:00Z',
          'leader_status': 'accepted',
          'expected_total': '300',
          'actual_total': 270.5,
          'expense_id': 'expense-1',
          'financial_applied_at': '2026-07-05T10:00:00Z',
          'financial_applied_by': 'leader-1',
        });

        expect(report.expectedTotal, 300.0);
        expect(report.actualTotal, 270.5);
        expect(report.expenseId, 'expense-1');
        expect(report.financialAppliedAt, DateTime.utc(2026, 7, 5, 10));
        expect(report.financialAppliedBy, 'leader-1');
        expect(report.hasFinancialSummary, true);
        expect(report.financialApplied, true);
        expect(report.deductionAmount, 270.5);
        expect(report.hasExpenseLink, true);
      },
    );

    test(
      'historical accepted report with null financial fields parses safely',
      () {
        final report = TeamShoppingReport.fromJson({
          'submitted_at': '2026-07-05T09:00:00Z',
          'leader_status': 'accepted',
          'expected_total': null,
          'actual_total': null,
        });

        expect(report.isAccepted, true);
        expect(report.hasFinancialSummary, false);
        expect(report.financialApplied, false);
        expect(report.deductionAmount, isNull);
        expect(report.hasExpenseLink, false);
      },
    );

    test('zero actual_total is valid and does not require expense link', () {
      final report = TeamShoppingReport.fromJson({
        'submitted_at': '2026-07-05T09:00:00Z',
        'leader_status': 'accepted',
        'expected_total': 25,
        'actual_total': 0,
        'expense_id': null,
        'financial_applied_at': '2026-07-05T10:00:00Z',
        'financial_applied_by': 'leader-1',
      });

      expect(report.hasFinancialSummary, true);
      expect(report.actualTotal, 0.0);
      expect(report.deductionAmount, 0.0);
      expect(report.hasExpenseLink, false);
      expect(report.financialApplied, true);
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
        quantityValue: 2.0,
        quantityUnit: 'kg',
        isRequired: true,
        position: 1,
        bought: true,
        markedByName: 'أحمد',
        markedAt: DateTime(2026, 7, 5, 8, 30),
        price: 150.0,
      );
      final json = original.toJson();
      expect(json['price'], 150.0);
      expect(json['quantity_value'], 2.0);
      expect(json['quantity_unit'], 'kg');
      final restored = TeamShoppingItem.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.quantityNote, original.quantityNote);
      expect(restored.quantityValue, original.quantityValue);
      expect(restored.quantityUnit, original.quantityUnit);
      expect(restored.isRequired, original.isRequired);
      expect(restored.position, original.position);
      expect(restored.bought, original.bought);
      expect(restored.markedByName, original.markedByName);
      expect(restored.markedAt, original.markedAt);
      expect(restored.price, original.price);
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
      expect(restored.quantityValue, isNull);
      expect(restored.quantityUnit, isNull);
      expect(restored.markedByName, isNull);
      expect(restored.markedAt, isNull);
      expect(restored.isRequired, false);
      expect(restored.price, isNull);
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

    test(
      'TeamShoppingOverview roundtrip with null turnDate and responsibleMember',
      () {
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
      },
    );
  });
}
