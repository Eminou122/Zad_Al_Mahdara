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
        memberId:    j['member_id'] as String,
        position:    (j['position'] as num).toInt(),
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

  const TurnEntry({
    required this.id,
    required this.turnDate,
    required this.status,
    required this.memberId,
    required this.displayName,
    required this.position,
    this.completedAt,
  });

  factory TurnEntry.fromJson(Map<String, dynamic> j) => TurnEntry(
        id:          j['id'] as String,
        turnDate:    j['turn_date'] as String,
        status:      j['status'] as String,
        memberId:    j['member_id'] as String,
        displayName: j['display_name'] as String,
        position:    (j['position'] as num).toInt(),
        completedAt: j['completed_at'] != null
            ? DateTime.parse(j['completed_at'] as String)
            : null,
      );
}

class TeamTurnState {
  final bool canManageTurns;
  final TurnEntry? todayTurn;
  final TurnMemberRef? nextMember;
  final TurnEntry? lastCompletedTurn;
  final List<TurnEntry> history;

  const TeamTurnState({
    required this.canManageTurns,
    this.todayTurn,
    this.nextMember,
    this.lastCompletedTurn,
    required this.history,
  });

  factory TeamTurnState.fromJson(Map<String, dynamic> j) => TeamTurnState(
        canManageTurns: j['can_manage_turns'] as bool,
        todayTurn: j['today_turn'] != null
            ? TurnEntry.fromJson(Map<String, dynamic>.from(j['today_turn'] as Map))
            : null,
        nextMember: j['next_member'] != null
            ? TurnMemberRef.fromJson(Map<String, dynamic>.from(j['next_member'] as Map))
            : null,
        lastCompletedTurn: j['last_completed_turn'] != null
            ? TurnEntry.fromJson(Map<String, dynamic>.from(j['last_completed_turn'] as Map))
            : null,
        history: (j['history'] as List? ?? [])
            .map((e) => TurnEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
