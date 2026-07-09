class TurnMemberRef {
  final String memberId;
  final int position;
  final String displayName;

  const TurnMemberRef({
    required this.memberId,
    required this.position,
    required this.displayName,
  });

  factory TurnMemberRef.fromJson(Map<String, dynamic> j) => TurnMemberRef(
    memberId: j['member_id'] as String,
    position: (j['position'] as num).toInt(),
    displayName: j['display_name'] as String,
  );
}

class TurnEntry {
  final String id;
  final String turnDate;
  final String status;
  final String memberId;
  final String displayName;
  final int position;
  final DateTime? completedAt;
  final DateTime? startedAt;
  final String? startedBy;
  final DateTime? skippedAt;
  final String? skippedBy;
  final String? skipReason;

  const TurnEntry({
    required this.id,
    required this.turnDate,
    required this.status,
    required this.memberId,
    required this.displayName,
    required this.position,
    this.completedAt,
    this.startedAt,
    this.startedBy,
    this.skippedAt,
    this.skippedBy,
    this.skipReason,
  });

  factory TurnEntry.fromJson(Map<String, dynamic> j) => TurnEntry(
    id: j['id'] as String,
    turnDate: j['turn_date'] as String,
    status: j['status'] as String,
    memberId: j['member_id'] as String,
    displayName: j['display_name'] as String,
    position: (j['position'] as num).toInt(),
    completedAt: _parseDateTime(j['completed_at']),
    startedAt: _parseDateTime(j['started_at']),
    startedBy: j['started_by'] as String?,
    skippedAt: _parseDateTime(j['skipped_at']),
    skippedBy: j['skipped_by'] as String?,
    skipReason: j['skip_reason'] as String?,
  );
}

class TeamTurnState {
  final bool canManageTurns;
  final TurnEntry? todayTurn;
  final TurnMemberRef? nextMember;
  final TurnEntry? lastCompletedTurn;
  final List<TurnEntry> history;
  final bool blockingPreviousTurn;
  final bool canSkipPreviousTurn;
  final String? blockingReason;
  final String? previousTurnId;
  final String? previousTurnMemberName;
  final String? previousTurnDate;
  final String? previousTurnStatus;

  const TeamTurnState({
    required this.canManageTurns,
    this.todayTurn,
    this.nextMember,
    this.lastCompletedTurn,
    required this.history,
    this.blockingPreviousTurn = false,
    this.canSkipPreviousTurn = false,
    this.blockingReason,
    this.previousTurnId,
    this.previousTurnMemberName,
    this.previousTurnDate,
    this.previousTurnStatus,
  });

  factory TeamTurnState.fromJson(Map<String, dynamic> j) => TeamTurnState(
    canManageTurns: j['can_manage_turns'] as bool,
    todayTurn: j['today_turn'] != null
        ? TurnEntry.fromJson(Map<String, dynamic>.from(j['today_turn'] as Map))
        : null,
    nextMember: j['next_member'] != null
        ? TurnMemberRef.fromJson(
            Map<String, dynamic>.from(j['next_member'] as Map),
          )
        : null,
    lastCompletedTurn: j['last_completed_turn'] != null
        ? TurnEntry.fromJson(
            Map<String, dynamic>.from(j['last_completed_turn'] as Map),
          )
        : null,
    history: (j['history'] as List? ?? [])
        .map((e) => TurnEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    blockingPreviousTurn: j['blocking_previous_turn'] as bool? ?? false,
    canSkipPreviousTurn: j['can_skip_previous_turn'] as bool? ?? false,
    blockingReason: j['blocking_reason'] as String?,
    previousTurnId: j['previous_turn_id'] as String?,
    previousTurnMemberName: j['previous_turn_member_name'] as String?,
    previousTurnDate: j['previous_turn_date'] as String?,
    previousTurnStatus: j['previous_turn_status'] as String?,
  );
}

DateTime? _parseDateTime(dynamic value) =>
    value == null ? null : DateTime.parse(value as String);
