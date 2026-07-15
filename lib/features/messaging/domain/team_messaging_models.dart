DateTime? _date(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v);
}

int _int(dynamic v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

bool _bool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  return fallback;
}

String _str(dynamic v, [String fallback = '']) => v is String ? v : fallback;

String? _strOrNull(dynamic v) => v is String && v.isNotEmpty ? v : null;

/// (updated_at, id) cursor for get_my_team_conversations.
class TeamConversationCursor {
  final DateTime updatedAt;
  final String id;

  const TeamConversationCursor({required this.updatedAt, required this.id});

  factory TeamConversationCursor.fromJson(Map<String, dynamic> j) =>
      TeamConversationCursor(
        updatedAt: _date(j['updated_at']) ?? DateTime.now(),
        id: _str(j['id']),
      );
}

/// (created_at, id) cursor for get_team_conversation_messages.
class TeamMessageCursor {
  final DateTime createdAt;
  final String id;

  const TeamMessageCursor({required this.createdAt, required this.id});

  factory TeamMessageCursor.fromJson(Map<String, dynamic> j) =>
      TeamMessageCursor(
        createdAt: _date(j['created_at']) ?? DateTime.now(),
        id: _str(j['id']),
      );
}

/// (created_at, id) cursor for get_my_team_announcements.
class TeamAnnouncementCursor {
  final DateTime createdAt;
  final String id;

  const TeamAnnouncementCursor({required this.createdAt, required this.id});

  factory TeamAnnouncementCursor.fromJson(Map<String, dynamic> j) =>
      TeamAnnouncementCursor(
        createdAt: _date(j['created_at']) ?? DateTime.now(),
        id: _str(j['id']),
      );
}

/// One row of get_my_team_conversations — a member<->current-leader thread.
class TeamConversationSummary {
  final String id;
  final String teamId;
  final String teamName;
  final String memberProfileId;
  final String memberName;
  final String? latestMessagePreview;
  final DateTime? latestMessageAt;
  final int unreadCount;
  final String currentUserRole;

  const TeamConversationSummary({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.memberProfileId,
    required this.memberName,
    this.latestMessagePreview,
    this.latestMessageAt,
    required this.unreadCount,
    required this.currentUserRole,
  });

  bool get isLeaderView => currentUserRole == 'leader';
  bool get isMemberView => currentUserRole == 'member';
  bool get hasUnread => unreadCount > 0;
  String get displayName => memberName;
  String get latestPreviewText => latestMessagePreview ?? '';

  factory TeamConversationSummary.fromJson(Map<String, dynamic> j) =>
      TeamConversationSummary(
        id: _str(j['id']),
        teamId: _str(j['team_id']),
        teamName: _str(j['team_name']),
        memberProfileId: _str(j['member_profile_id']),
        memberName: _str(j['member_name']),
        latestMessagePreview: _strOrNull(j['latest_message_preview']),
        latestMessageAt: _date(j['latest_message_at']),
        unreadCount: _int(j['unread_count']),
        currentUserRole: _str(j['current_user_role'], 'member'),
      );
}

class TeamConversationsPage {
  final List<TeamConversationSummary> items;
  final bool hasMore;
  final TeamConversationCursor? nextCursor;

  const TeamConversationsPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  factory TeamConversationsPage.fromJson(Map<String, dynamic> j) =>
      TeamConversationsPage(
        items: (j['items'] as List? ?? [])
            .map(
              (e) => TeamConversationSummary.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        hasMore: j['has_more'] as bool? ?? false,
        nextCursor: j['next_cursor'] != null
            ? TeamConversationCursor.fromJson(
                Map<String, dynamic>.from(j['next_cursor'] as Map),
              )
            : null,
      );
}

/// A single message inside a private team conversation.
class TeamMessage {
  final String id;
  final String conversationId;
  final String senderProfileId;
  final String senderName;
  final String senderRole;
  final String body;
  final DateTime createdAt;
  final bool isRead;

  const TeamMessage({
    required this.id,
    required this.conversationId,
    required this.senderProfileId,
    required this.senderName,
    required this.senderRole,
    required this.body,
    required this.createdAt,
    required this.isRead,
  });

  bool isSentBy(String? currentProfileId) =>
      currentProfileId != null && senderProfileId == currentProfileId;
  bool get isLeaderMessage => senderRole == 'leader';
  bool get isMemberMessage => senderRole == 'member';

  factory TeamMessage.fromJson(Map<String, dynamic> j) => TeamMessage(
    id: _str(j['id']),
    conversationId: _str(j['conversation_id']),
    senderProfileId: _str(j['sender_profile_id']),
    senderName: _str(j['sender_name']),
    senderRole: _str(j['sender_role'], 'member'),
    body: _str(j['body']),
    createdAt: _date(j['created_at']) ?? DateTime.now(),
    isRead: j['is_read'] as bool? ?? false,
  );
}

class TeamMessagesPage {
  final String conversationId;
  final List<TeamMessage> items;
  final bool hasMore;
  final TeamMessageCursor? nextCursor;

  const TeamMessagesPage({
    required this.conversationId,
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  factory TeamMessagesPage.fromJson(Map<String, dynamic> j) => TeamMessagesPage(
    conversationId: _str(j['conversation_id']),
    items: (j['items'] as List? ?? [])
        .map((e) => TeamMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    hasMore: j['has_more'] as bool? ?? false,
    nextCursor: j['next_cursor'] != null
        ? TeamMessageCursor.fromJson(
            Map<String, dynamic>.from(j['next_cursor'] as Map),
          )
        : null,
  );
}

class ConversationLiveState {
  final String? otherProfileId;
  final String? displayName;
  final bool isOnline;
  final DateTime? lastActiveAt;
  final bool isTyping;
  final DateTime? typingUntil;

  const ConversationLiveState({
    this.otherProfileId,
    this.displayName,
    required this.isOnline,
    this.lastActiveAt,
    required this.isTyping,
    this.typingUntil,
  });

  static const unknown = ConversationLiveState(
    isOnline: false,
    isTyping: false,
  );

  bool get hasKnownPresence => lastActiveAt != null;

  bool get typingIsActive =>
      isTyping &&
      typingUntil != null &&
      typingUntil!.isAfter(DateTime.now().toUtc());

  String? get statusLabel {
    if (isOnline) return 'متصل الآن';
    final seen = lastActiveAt;
    if (seen == null) return null;
    final diff = DateTime.now().difference(seen.toLocal());
    if (diff.inMinutes < 1) return 'آخر ظهور منذ أقل من دقيقة';
    if (diff.inHours < 1) return 'آخر ظهور منذ ${diff.inMinutes} دقيقة';
    if (diff.inDays < 1) return 'آخر ظهور منذ ${diff.inHours} ساعة';
    return 'آخر ظهور منذ ${diff.inDays} يوم';
  }

  factory ConversationLiveState.fromJson(Map<String, dynamic> j) {
    final participant = j['other_participant'];
    if (participant is! Map || participant.isEmpty) {
      return ConversationLiveState.unknown;
    }
    final p = Map<String, dynamic>.from(participant);
    return ConversationLiveState(
      otherProfileId: _strOrNull(p['profile_id']),
      displayName: _strOrNull(p['display_name']),
      isOnline: _bool(p['is_online']),
      lastActiveAt: _date(p['last_active_at']),
      isTyping: _bool(p['is_typing']),
      typingUntil: _date(p['typing_until']),
    );
  }
}

class ConversationUpdates {
  final String conversationId;
  final List<TeamMessage> messages;
  final TeamMessageCursor? newestCursor;
  final int unreadCount;
  final ConversationLiveState? liveState;

  const ConversationUpdates({
    required this.conversationId,
    required this.messages,
    this.newestCursor,
    required this.unreadCount,
    this.liveState,
  });

  factory ConversationUpdates.fromJson(Map<String, dynamic> j) =>
      ConversationUpdates(
        conversationId: _str(j['conversation_id']),
        messages: (j['items'] as List? ?? [])
            .map(
              (e) => TeamMessage.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(),
        newestCursor: j['newest_cursor'] is Map
            ? TeamMessageCursor.fromJson(
                Map<String, dynamic>.from(j['newest_cursor'] as Map),
              )
            : null,
        unreadCount: _int(j['unread_count']),
        liveState: j['live_state'] is Map
            ? ConversationLiveState.fromJson(
                Map<String, dynamic>.from(j['live_state'] as Map),
              )
            : null,
      );
}

/// Minimal conversation identity returned by send/reply, enough to
/// navigate straight to the conversation screen after a first message.
class TeamConversationRef {
  final String id;
  final String teamId;
  final String memberProfileId;

  const TeamConversationRef({
    required this.id,
    required this.teamId,
    required this.memberProfileId,
  });

  factory TeamConversationRef.fromJson(Map<String, dynamic> j) =>
      TeamConversationRef(
        id: _str(j['id']),
        teamId: _str(j['team_id']),
        memberProfileId: _str(j['member_profile_id']),
      );
}

/// send_team_leader_message / leader_reply_team_message response.
class SentTeamMessage {
  final TeamConversationRef conversation;
  final TeamMessage message;

  const SentTeamMessage({required this.conversation, required this.message});

  factory SentTeamMessage.fromJson(Map<String, dynamic> j) => SentTeamMessage(
    conversation: TeamConversationRef.fromJson(
      Map<String, dynamic>.from(j['conversation'] as Map),
    ),
    message: TeamMessage.fromJson(
      Map<String, dynamic>.from(j['message'] as Map),
    ),
  );
}

/// A team-wide leader announcement.
class TeamAnnouncement {
  final String id;
  final String teamId;
  final String teamName;
  final String authorProfileId;
  final String authorName;
  final String? title;
  final String body;
  final DateTime createdAt;
  final bool isRead;

  const TeamAnnouncement({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.authorProfileId,
    required this.authorName,
    this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
  });

  factory TeamAnnouncement.fromJson(Map<String, dynamic> j) => TeamAnnouncement(
    id: _str(j['id']),
    teamId: _str(j['team_id']),
    teamName: _str(j['team_name']),
    authorProfileId: _str(j['author_profile_id']),
    authorName: _str(j['author_name']),
    title: _strOrNull(j['title']),
    body: _str(j['body']),
    createdAt: _date(j['created_at']) ?? DateTime.now(),
    isRead: j['is_read'] as bool? ?? false,
  );
}

class TeamAnnouncementsPage {
  final List<TeamAnnouncement> items;
  final bool hasMore;
  final TeamAnnouncementCursor? nextCursor;

  const TeamAnnouncementsPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  factory TeamAnnouncementsPage.fromJson(Map<String, dynamic> j) =>
      TeamAnnouncementsPage(
        items: (j['items'] as List? ?? [])
            .map(
              (e) => TeamAnnouncement.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        hasMore: j['has_more'] as bool? ?? false,
        nextCursor: j['next_cursor'] != null
            ? TeamAnnouncementCursor.fromJson(
                Map<String, dynamic>.from(j['next_cursor'] as Map),
              )
            : null,
      );
}

/// get_my_messaging_unread_count response.
class MessagingUnreadCount {
  final int privateMessageUnreadCount;
  final int announcementUnreadCount;
  final int totalUnreadCount;

  const MessagingUnreadCount({
    required this.privateMessageUnreadCount,
    required this.announcementUnreadCount,
    required this.totalUnreadCount,
  });

  static const zero = MessagingUnreadCount(
    privateMessageUnreadCount: 0,
    announcementUnreadCount: 0,
    totalUnreadCount: 0,
  );

  factory MessagingUnreadCount.fromJson(Map<String, dynamic> j) =>
      MessagingUnreadCount(
        privateMessageUnreadCount: _int(j['private_message_unread_count']),
        announcementUnreadCount: _int(j['announcement_unread_count']),
        totalUnreadCount: _int(j['total_unread_count']),
      );
}
