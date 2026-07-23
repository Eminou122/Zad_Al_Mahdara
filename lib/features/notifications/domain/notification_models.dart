class NotificationCursor {
  final DateTime createdAt;
  final String id;

  const NotificationCursor({required this.createdAt, required this.id});

  factory NotificationCursor.fromJson(Map<String, dynamic> j) =>
      NotificationCursor(
        createdAt: DateTime.parse(j['created_at'] as String),
        id: j['id'] as String,
      );
}

class NotificationItem {
  final String id;
  final String type;
  final String title;
  final String body;
  final String? teamId;
  final String? turnId;
  final String? shoppingReportId;
  final String? actionType;
  final Map<String, dynamic>? actionPayload;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.teamId,
    this.turnId,
    this.shoppingReportId,
    this.actionType,
    this.actionPayload,
    required this.isRead,
    this.readAt,
    required this.createdAt,
  });

  bool get isUnread => !isRead;
  bool get hasAction => actionType != null && actionType!.isNotEmpty;

  factory NotificationItem.fromJson(Map<String, dynamic> j) => NotificationItem(
    id: j['id'] as String,
    type: j['type'] as String? ?? 'unknown',
    title: j['title'] as String? ?? '',
    body: j['body'] as String? ?? '',
    teamId: j['team_id'] as String?,
    turnId: j['turn_id'] as String?,
    shoppingReportId: j['shopping_report_id'] as String?,
    actionType: j['action_type'] as String?,
    actionPayload: j['action_payload'] != null
        ? Map<String, dynamic>.from(j['action_payload'] as Map)
        : null,
    isRead: j['is_read'] as bool? ?? false,
    readAt: j['read_at'] != null
        ? DateTime.parse(j['read_at'] as String)
        : null,
    createdAt: DateTime.parse(j['created_at'] as String),
  );

  /// Local-only "now read" copy, applied after a successful mark-read RPC
  /// so the list updates without a full reload (no copyWith convention
  /// exists in this codebase — matches sibling models' plain-constructor
  /// style).
  NotificationItem markedRead({DateTime? at}) => NotificationItem(
    id: id,
    type: type,
    title: title,
    body: body,
    teamId: teamId,
    turnId: turnId,
    shoppingReportId: shoppingReportId,
    actionType: actionType,
    actionPayload: actionPayload,
    isRead: true,
    readAt: readAt ?? at ?? DateTime.now(),
    createdAt: createdAt,
  );
}

class NotificationsPage {
  final List<NotificationItem> items;
  final int unreadCount;
  final bool hasMore;
  final NotificationCursor? nextCursor;

  const NotificationsPage({
    required this.items,
    required this.unreadCount,
    required this.hasMore,
    this.nextCursor,
  });

  factory NotificationsPage.fromJson(Map<String, dynamic> j) =>
      NotificationsPage(
        items: (j['items'] as List? ?? [])
            .map(
              (e) => NotificationItem.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        unreadCount: (j['unread_count'] as num?)?.toInt() ?? 0,
        hasMore: j['has_more'] as bool? ?? false,
        nextCursor: j['next_cursor'] != null
            ? NotificationCursor.fromJson(
                Map<String, dynamic>.from(j['next_cursor'] as Map),
              )
            : null,
      );
}
