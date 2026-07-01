const teamTypeLabels = {
  'lunch': 'الغداء',
  'breakfast': 'الفطور',
  'dinner': 'العشاء',
  'tea': 'الشاي',
  'other': 'أخرى',
};

const teamStatusLabels = {'open': 'مفتوح', 'closed': 'مغلق', 'full': 'مكتمل'};

class TeamSummary {
  final String id;
  final String name;
  final String teamType;
  final bool isPublic;
  final String status;
  final String leaderName;
  final int memberCount;
  final int activeMemberCount;
  final int inactiveMemberCount;
  final String? myRole;
  final bool? isLeader;

  const TeamSummary({
    required this.id,
    required this.name,
    required this.teamType,
    required this.isPublic,
    required this.status,
    required this.leaderName,
    required this.memberCount,
    required this.activeMemberCount,
    required this.inactiveMemberCount,
    this.myRole,
    this.isLeader,
  });

  factory TeamSummary.fromJson(Map<String, dynamic> j) => TeamSummary(
    id: j['id'] as String,
    name: j['name'] as String,
    teamType: j['team_type'] as String,
    isPublic: j['is_public'] as bool? ?? true,
    status: j['status'] as String,
    leaderName: j['leader_name'] as String,
    memberCount: (j['member_count'] as num).toInt(),
    activeMemberCount:
        (j['active_member_count'] as num? ?? j['member_count'] as num).toInt(),
    inactiveMemberCount: (j['inactive_member_count'] as num? ?? 0).toInt(),
    myRole: j['my_role'] as String?,
    isLeader: j['is_leader'] as bool?,
  );
}

class TeamMember {
  final String memberId;
  final String profileId;
  final String displayName;
  final String role;
  final int position;
  final bool isActive;
  final DateTime joinedAt;

  const TeamMember({
    required this.memberId,
    required this.profileId,
    required this.displayName,
    required this.role,
    required this.position,
    required this.isActive,
    required this.joinedAt,
  });

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
    memberId: j['member_id'] as String,
    profileId: j['profile_id'] as String,
    displayName: j['display_name'] as String,
    role: j['role'] as String,
    position: (j['position'] as num).toInt(),
    isActive: j['is_active'] as bool? ?? true,
    joinedAt: DateTime.parse(j['joined_at'] as String),
  );
}

class TeamInfo {
  final String id;
  final String name;
  final String teamType;
  final bool isPublic;
  final String status;
  final String? note;
  final String leaderId;
  final String leaderName;
  final int memberCount;
  final int activeMemberCount;
  final int inactiveMemberCount;
  final DateTime createdAt;

  const TeamInfo({
    required this.id,
    required this.name,
    required this.teamType,
    required this.isPublic,
    required this.status,
    this.note,
    required this.leaderId,
    required this.leaderName,
    required this.memberCount,
    required this.activeMemberCount,
    required this.inactiveMemberCount,
    required this.createdAt,
  });

  factory TeamInfo.fromJson(Map<String, dynamic> j) => TeamInfo(
    id: j['id'] as String,
    name: j['name'] as String,
    teamType: j['team_type'] as String,
    isPublic: j['is_public'] as bool? ?? true,
    status: j['status'] as String,
    note: j['note'] as String?,
    leaderId: j['leader_id'] as String,
    leaderName: j['leader_name'] as String,
    memberCount: (j['member_count'] as num).toInt(),
    activeMemberCount:
        (j['active_member_count'] as num? ?? j['member_count'] as num).toInt(),
    inactiveMemberCount: (j['inactive_member_count'] as num? ?? 0).toInt(),
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

class TeamDetail {
  final TeamInfo team;
  final List<TeamMember> members;
  final bool canEdit;
  final bool isMember;

  const TeamDetail({
    required this.team,
    required this.members,
    required this.canEdit,
    required this.isMember,
  });

  factory TeamDetail.fromJson(Map<String, dynamic> j) => TeamDetail(
    team: TeamInfo.fromJson(Map<String, dynamic>.from(j['team'] as Map)),
    members: (j['members'] as List)
        .map((e) => TeamMember.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    canEdit: j['can_edit'] as bool,
    isMember: j['is_member'] as bool,
  );
}

class StudentResult {
  final String profileId;
  final String displayName;
  final String phoneMasked;

  const StudentResult({
    required this.profileId,
    required this.displayName,
    required this.phoneMasked,
  });

  factory StudentResult.fromJson(Map<String, dynamic> j) => StudentResult(
    profileId: j['profile_id'] as String,
    displayName: j['display_name'] as String,
    phoneMasked: j['phone_masked'] as String,
  );
}
