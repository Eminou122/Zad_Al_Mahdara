String _str(dynamic value, [String fallback = '']) =>
    value is String ? value : fallback;

bool _bool(dynamic value, [bool fallback = false]) =>
    value is bool ? value : fallback;

Map<String, dynamic>? _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

List<T> _list<T>(dynamic value, T? Function(Map<String, dynamic>) parse) {
  if (value is! List) return const [];
  final items = <T>[];
  for (final raw in value) {
    final map = _map(raw);
    if (map == null) continue;
    final parsed = parse(map);
    if (parsed != null) items.add(parsed);
  }
  return items;
}

class PublicDirectoryTeam {
  final String teamId;
  final String teamName;
  final String teamType;
  final bool isCurrentLeader;
  final String role;

  const PublicDirectoryTeam({
    required this.teamId,
    required this.teamName,
    required this.teamType,
    required this.isCurrentLeader,
    required this.role,
  });

  factory PublicDirectoryTeam.fromJson(Map<String, dynamic> json) {
    final teamId = _str(json['team_id']);
    final teamName = _str(json['team_name']);
    if (teamId.isEmpty || teamName.isEmpty) {
      throw const FormatException('invalid public team');
    }
    return PublicDirectoryTeam(
      teamId: teamId,
      teamName: teamName,
      teamType: _str(json['team_type']),
      isCurrentLeader: _bool(json['is_current_leader']),
      role: _str(json['role'], 'member'),
    );
  }
}

class DirectoryContactTarget {
  final String teamId;
  final String teamName;
  final String teamType;
  final String label;

  const DirectoryContactTarget({
    required this.teamId,
    required this.teamName,
    required this.teamType,
    required this.label,
  });

  factory DirectoryContactTarget.fromJson(Map<String, dynamic> json) {
    final teamId = _str(json['team_id']);
    final teamName = _str(json['team_name']);
    if (teamId.isEmpty || teamName.isEmpty) {
      throw const FormatException('invalid contact target');
    }
    return DirectoryContactTarget(
      teamId: teamId,
      teamName: teamName,
      teamType: _str(json['team_type']),
      label: _str(json['label'], 'مراسلة قائد الفريق'),
    );
  }
}

class StudentDirectoryEntry {
  final String profileId;
  final String displayName;
  final List<PublicDirectoryTeam> publicTeams;
  final List<DirectoryContactTarget> contactTargets;

  const StudentDirectoryEntry({
    required this.profileId,
    required this.displayName,
    required this.publicTeams,
    required this.contactTargets,
  });

  factory StudentDirectoryEntry.fromJson(Map<String, dynamic> json) {
    final profileId = _str(json['profile_id']);
    if (profileId.isEmpty) {
      throw const FormatException('invalid directory profile');
    }
    return StudentDirectoryEntry(
      profileId: profileId,
      displayName: _str(json['display_name']),
      publicTeams: _list(json['public_teams'], (item) {
        try {
          return PublicDirectoryTeam.fromJson(item);
        } catch (_) {
          return null;
        }
      }),
      contactTargets: _list(json['contact_targets'], (item) {
        try {
          return DirectoryContactTarget.fromJson(item);
        } catch (_) {
          return null;
        }
      }),
    );
  }
}

class StudentDirectoryCursor {
  final String sortName;
  final String profileId;

  const StudentDirectoryCursor({
    required this.sortName,
    required this.profileId,
  });

  factory StudentDirectoryCursor.fromJson(Map<String, dynamic> json) {
    final sortName = _str(json['sort_name']);
    final profileId = _str(json['profile_id']);
    if (sortName.isEmpty || profileId.isEmpty) {
      throw const FormatException('invalid directory cursor');
    }
    return StudentDirectoryCursor(sortName: sortName, profileId: profileId);
  }
}

class StudentDirectoryPage {
  final List<StudentDirectoryEntry> items;
  final bool hasMore;
  final StudentDirectoryCursor? nextCursor;

  const StudentDirectoryPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  factory StudentDirectoryPage.fromJson(Map<String, dynamic> json) =>
      StudentDirectoryPage(
        items: _list(json['items'], (item) {
          try {
            return StudentDirectoryEntry.fromJson(item);
          } catch (_) {
            return null;
          }
        }),
        hasMore: _bool(json['has_more']),
        nextCursor: _map(json['next_cursor']) == null
            ? null
            : StudentDirectoryCursor.fromJson(_map(json['next_cursor'])!),
      );
}
