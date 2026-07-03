class AdminDashboard {
  final int activeUsersCount;
  final int inactiveUsersCount;
  final int publicTeamsCount;
  final int pendingPinResetRequestsCount;

  const AdminDashboard({
    required this.activeUsersCount,
    required this.inactiveUsersCount,
    required this.publicTeamsCount,
    required this.pendingPinResetRequestsCount,
  });

  factory AdminDashboard.fromJson(Map<String, dynamic> j) => AdminDashboard(
    activeUsersCount: _int(j['active_users_count']),
    inactiveUsersCount: _int(j['inactive_users_count']),
    publicTeamsCount: _int(j['public_teams_count']),
    pendingPinResetRequestsCount: _int(j['pending_pin_reset_requests_count']),
  );
}

class AdminUserSummary {
  final String id;
  final String displayName;
  final String phoneMasked;
  final bool isActive;
  final bool isAdmin;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  const AdminUserSummary({
    required this.id,
    required this.displayName,
    required this.phoneMasked,
    required this.isActive,
    required this.isAdmin,
    required this.createdAt,
    required this.lastLoginAt,
  });

  factory AdminUserSummary.fromJson(Map<String, dynamic> j) => AdminUserSummary(
    id: j['id'] as String,
    displayName: j['display_name'] as String? ?? '',
    phoneMasked: j['phone_masked'] as String? ?? '',
    isActive: j['is_active'] as bool? ?? true,
    isAdmin: j['is_admin'] as bool? ?? false,
    createdAt: _date(j['created_at']),
    lastLoginAt: _date(j['last_login_at']),
  );
}

class AdminUserDetail extends AdminUserSummary {
  final int failedLoginCount;
  final DateTime? lockedUntil;

  const AdminUserDetail({
    required super.id,
    required super.displayName,
    required super.phoneMasked,
    required super.isActive,
    required super.isAdmin,
    required super.createdAt,
    required super.lastLoginAt,
    required this.failedLoginCount,
    required this.lockedUntil,
  });

  factory AdminUserDetail.fromJson(Map<String, dynamic> j) => AdminUserDetail(
    id: j['id'] as String,
    displayName: j['display_name'] as String? ?? '',
    phoneMasked: j['phone_masked'] as String? ?? '',
    isActive: j['is_active'] as bool? ?? true,
    isAdmin: j['is_admin'] as bool? ?? false,
    createdAt: _date(j['created_at']),
    lastLoginAt: _date(j['last_login_at']),
    failedLoginCount: _int(j['failed_login_count']),
    lockedUntil: _date(j['locked_until']),
  );
}

class AdminPublicTeam {
  final String id;
  final String name;
  final String teamType;
  final String leaderName;
  final int memberCount;
  final int activeMemberCount;
  final int inactiveMemberCount;
  final String status;
  final DateTime? createdAt;

  const AdminPublicTeam({
    required this.id,
    required this.name,
    required this.teamType,
    required this.leaderName,
    required this.memberCount,
    required this.activeMemberCount,
    required this.inactiveMemberCount,
    required this.status,
    required this.createdAt,
  });

  factory AdminPublicTeam.fromJson(Map<String, dynamic> j) => AdminPublicTeam(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    teamType: j['team_type'] as String? ?? '',
    leaderName: j['leader_name'] as String? ?? '',
    memberCount: _int(j['member_count']),
    activeMemberCount: _int(j['active_member_count']),
    inactiveMemberCount: _int(j['inactive_member_count']),
    status: j['status'] as String? ?? '',
    createdAt: _date(j['created_at']),
  );
}

int _int(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v');
