class TeamShoppingResponsibleMember {
  final String id;
  final String displayName;

  const TeamShoppingResponsibleMember({
    required this.id,
    required this.displayName,
  });

  factory TeamShoppingResponsibleMember.fromJson(Map<String, dynamic> j) =>
      TeamShoppingResponsibleMember(
        id: j['id'] as String,
        displayName: j['display_name'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
      };
}

class TeamShoppingItem {
  final String id;
  final String name;
  final String? quantityNote;
  final double? quantityValue;
  final String? quantityUnit;
  final bool isRequired;
  final int position;
  final bool bought;
  final String? markedByName;
  final DateTime? markedAt;
  final double? price;

  const TeamShoppingItem({
    required this.id,
    required this.name,
    this.quantityNote,
    this.quantityValue,
    this.quantityUnit,
    required this.isRequired,
    required this.position,
    required this.bought,
    this.markedByName,
    this.markedAt,
    this.price,
  });

  factory TeamShoppingItem.fromJson(Map<String, dynamic> j) =>
      TeamShoppingItem(
        id: j['id'] as String,
        name: j['name'] as String,
        quantityNote: j['quantity_note'] as String?,
        quantityValue: (j['quantity_value'] as num?)?.toDouble(),
        quantityUnit: j['quantity_unit'] as String?,
        isRequired: j['is_required'] as bool? ?? true,
        position: (j['position'] as num).toInt(),
        bought: j['bought'] as bool? ?? false,
        markedByName: j['marked_by_name'] as String?,
        markedAt: j['marked_at'] != null
            ? DateTime.parse(j['marked_at'] as String)
            : null,
        price: (j['price'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity_note': quantityNote,
        'quantity_value': quantityValue,
        'quantity_unit': quantityUnit,
        'is_required': isRequired,
        'position': position,
        'bought': bought,
        'marked_by_name': markedByName,
        'marked_at': markedAt?.toIso8601String(),
        'price': price,
      };
}

class TeamShoppingOverview {
  final DateTime? turnDate;
  final TeamShoppingResponsibleMember? responsibleMember;
  final bool canMark;
  final bool canEditList;
  final List<TeamShoppingItem> items;

  const TeamShoppingOverview({
    this.turnDate,
    this.responsibleMember,
    required this.canMark,
    required this.canEditList,
    required this.items,
  });

  factory TeamShoppingOverview.fromJson(Map<String, dynamic> j) =>
      TeamShoppingOverview(
        turnDate: j['turn_date'] != null
            ? DateTime.parse(j['turn_date'] as String)
            : null,
        responsibleMember: j['responsible_member'] != null
            ? TeamShoppingResponsibleMember.fromJson(
                Map<String, dynamic>.from(j['responsible_member'] as Map))
            : null,
        canMark: j['can_mark'] as bool,
        canEditList: j['can_edit_list'] as bool,
        items: (j['items'] as List)
            .map((e) =>
                TeamShoppingItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'turn_date': turnDate?.toIso8601String(),
        'responsible_member': responsibleMember?.toJson(),
        'can_mark': canMark,
        'can_edit_list': canEditList,
        'items': items.map((e) => e.toJson()).toList(),
      };
}
