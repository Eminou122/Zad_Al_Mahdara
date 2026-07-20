class AvailablePublicTeam {
  final String teamId;
  final String name;
  final String teamType;
  final String? note;
  final String? leaderDisplayName;
  final int memberCount;
  final bool isCurrentMember;

  const AvailablePublicTeam({
    required this.teamId,
    required this.name,
    required this.teamType,
    required this.note,
    required this.leaderDisplayName,
    required this.memberCount,
    required this.isCurrentMember,
  });

  factory AvailablePublicTeam.fromJson(Map<String, dynamic> json) {
    final teamId = json['team_id'];
    final name = json['name'];
    if (teamId is! String ||
        teamId.isEmpty ||
        name is! String ||
        name.isEmpty) {
      throw const FormatException('invalid available team');
    }
    final count = json['member_count'];
    return AvailablePublicTeam(
      teamId: teamId,
      name: name,
      teamType: json['team_type'] is String ? json['team_type'] as String : '',
      note: json['note'] is String && (json['note'] as String).trim().isNotEmpty
          ? (json['note'] as String).trim()
          : null,
      leaderDisplayName:
          json['leader_display_name'] is String &&
              (json['leader_display_name'] as String).trim().isNotEmpty
          ? (json['leader_display_name'] as String).trim()
          : null,
      memberCount: count is num && count >= 0 ? count.toInt() : 0,
      isCurrentMember: json['is_current_member'] is bool
          ? json['is_current_member'] as bool
          : false,
    );
  }
}

class AvailablePublicTeamsResult {
  final List<AvailablePublicTeam> items;
  const AvailablePublicTeamsResult(this.items);

  factory AvailablePublicTeamsResult.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    if (raw is! List) return const AvailablePublicTeamsResult([]);
    final items = <AvailablePublicTeam>[];
    for (final value in raw) {
      if (value is! Map) continue;
      try {
        items.add(
          AvailablePublicTeam.fromJson(Map<String, dynamic>.from(value)),
        );
      } on FormatException {
        // A malformed item must not break the available-teams screen.
      }
    }
    return AvailablePublicTeamsResult(items);
  }
}
