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

class TeamShoppingReport {
  final DateTime? submittedAt;
  final String? submittedBy;
  final String? submittedByName;
  final String? leaderStatus;
  final DateTime? leaderReviewedAt;
  final String? leaderReviewedBy;
  final String? leaderReviewedByName;
  final String? leaderNote;
  final bool canSubmit;
  final bool canReview;
  final bool canEditMarks;
  final String? completionBlockingReason;

  const TeamShoppingReport({
    this.submittedAt,
    this.submittedBy,
    this.submittedByName,
    this.leaderStatus,
    this.leaderReviewedAt,
    this.leaderReviewedBy,
    this.leaderReviewedByName,
    this.leaderNote,
    required this.canSubmit,
    required this.canReview,
    required this.canEditMarks,
    this.completionBlockingReason,
  });

  factory TeamShoppingReport.empty() => const TeamShoppingReport(
        canSubmit: false,
        canReview: false,
        canEditMarks: false,
      );

  factory TeamShoppingReport.fromJson(Map<String, dynamic>? j) {
    if (j == null) return TeamShoppingReport.empty();
    return TeamShoppingReport(
      submittedAt: j['submitted_at'] != null
          ? DateTime.parse(j['submitted_at'] as String)
          : null,
      submittedBy: j['submitted_by'] as String?,
      submittedByName: j['submitted_by_name'] as String?,
      leaderStatus: j['leader_status'] as String?,
      leaderReviewedAt: j['leader_reviewed_at'] != null
          ? DateTime.parse(j['leader_reviewed_at'] as String)
          : null,
      leaderReviewedBy: j['leader_reviewed_by'] as String?,
      leaderReviewedByName: j['leader_reviewed_by_name'] as String?,
      leaderNote: j['leader_note'] as String?,
      canSubmit: j['can_submit'] as bool? ?? false,
      canReview: j['can_review'] as bool? ?? false,
      canEditMarks: j['can_edit_marks'] as bool? ?? false,
      completionBlockingReason: j['completion_blocking_reason'] as String?,
    );
  }

  bool get isPending => submittedAt != null && leaderStatus == 'pending';
  bool get isAccepted => submittedAt != null && leaderStatus == 'accepted';
  bool get isRejected => submittedAt != null && leaderStatus == 'rejected';

  Map<String, dynamic> toJson() => {
        'submitted_at': submittedAt?.toIso8601String(),
        'submitted_by': submittedBy,
        'submitted_by_name': submittedByName,
        'leader_status': leaderStatus,
        'leader_reviewed_at': leaderReviewedAt?.toIso8601String(),
        'leader_reviewed_by': leaderReviewedBy,
        'leader_reviewed_by_name': leaderReviewedByName,
        'leader_note': leaderNote,
        'can_submit': canSubmit,
        'can_review': canReview,
        'can_edit_marks': canEditMarks,
        'completion_blocking_reason': completionBlockingReason,
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
  final String status;
  final String? reason;
  final String? markedBy;
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
    this.status = 'untouched',
    this.reason,
    this.markedBy,
    this.markedByName,
    this.markedAt,
    this.price,
  });

  bool get isUntouched => status == 'untouched';
  bool get isBought => status == 'bought' || bought;
  bool get isNotBought => status == 'not_bought';

  factory TeamShoppingItem.fromJson(Map<String, dynamic> j) {
    final status = j['status'] as String? ??
        ((j['bought'] as bool? ?? false) ? 'bought' : 'untouched');
    return TeamShoppingItem(
      id: j['id'] as String,
      name: j['name'] as String,
      quantityNote: j['quantity_note'] as String?,
      quantityValue: (j['quantity_value'] as num?)?.toDouble(),
      quantityUnit: j['quantity_unit'] as String?,
      isRequired: j['is_required'] as bool? ?? true,
      position: (j['position'] as num).toInt(),
      bought: j['bought'] as bool? ?? status == 'bought',
      status: status,
      reason: j['reason'] as String?,
      markedBy: j['marked_by'] as String?,
      markedByName: j['marked_by_name'] as String?,
      markedAt: j['marked_at'] != null
          ? DateTime.parse(j['marked_at'] as String)
          : null,
      price: (j['price'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity_note': quantityNote,
        'quantity_value': quantityValue,
        'quantity_unit': quantityUnit,
        'is_required': isRequired,
        'position': position,
        'bought': bought,
        'status': status,
        'reason': reason,
        'marked_by': markedBy,
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
  final TeamShoppingReport report;
  final bool hasReportObject;

  const TeamShoppingOverview({
    this.turnDate,
    this.responsibleMember,
    required this.canMark,
    required this.canEditList,
    required this.items,
    this.report = const TeamShoppingReport(
      canSubmit: false,
      canReview: false,
      canEditMarks: false,
    ),
    this.hasReportObject = false,
  });

  bool get reportIsPending => report.isPending;
  bool get reportAccepted => report.isAccepted;
  bool get reportRejected => report.isRejected;
  bool get canSubmit => hasReportObject ? report.canSubmit : canMark;
  bool get canReview => report.canReview;
  bool get canEditMarks => hasReportObject ? report.canEditMarks : canMark;

  factory TeamShoppingOverview.fromJson(Map<String, dynamic> j) {
    final reportJson = j['report'] == null
        ? null
        : Map<String, dynamic>.from(j['report'] as Map);
    return TeamShoppingOverview(
        turnDate: j['turn_date'] != null
            ? DateTime.parse(j['turn_date'] as String)
            : null,
        responsibleMember: j['responsible_member'] != null
            ? TeamShoppingResponsibleMember.fromJson(
                Map<String, dynamic>.from(j['responsible_member'] as Map))
            : null,
        canMark: j['can_mark'] as bool? ?? false,
        canEditList: j['can_edit_list'] as bool? ?? false,
        report: TeamShoppingReport.fromJson(reportJson),
        hasReportObject: reportJson != null,
        items: (j['items'] as List)
            .map((e) =>
                TeamShoppingItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
  }

  Map<String, dynamic> toJson() => {
        'turn_date': turnDate?.toIso8601String(),
        'responsible_member': responsibleMember?.toJson(),
        'can_mark': canMark,
        'can_edit_list': canEditList,
        'report': report.toJson(),
        'items': items.map((e) => e.toJson()).toList(),
      };
}
