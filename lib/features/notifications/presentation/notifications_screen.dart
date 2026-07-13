import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/ltr_fragment.dart';
import '../../../core/widgets/zad_bottom_nav.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_empty_state.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_logo_badge.dart';
import '../../../core/widgets/zad_notification_badge_scope.dart';
import '../../../services/auth_service.dart';
import '../data/notification_service.dart';
import '../domain/notification_models.dart';

const int _pageSize = 25;

class NotificationsScreen extends StatefulWidget {
  final AuthService authService;

  /// Injectable for widget tests (same pattern as TeamDetailScreen);
  /// production always uses the default [NotificationService].
  final NotificationService? service;

  const NotificationsScreen({
    super.key,
    required this.authService,
    this.service,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationService _svc;
  final ScrollController _scrollController = ScrollController();

  List<NotificationItem> _items = [];
  int _unreadCount = 0;
  bool _hasMore = false;
  NotificationCursor? _nextCursor;

  bool _hasLoadedOnce = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _markingAllRead = false;
  final Set<String> _busyIds = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? NotificationService(widget.authService);
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _pushBadge(int count) {
    ZadNotificationBadgeScope.maybeOf(context)?.setCount(count);
  }

  List<NotificationItem> _dedupe(List<NotificationItem> items) {
    final seen = <String>{};
    final out = <NotificationItem>[];
    for (final it in items) {
      if (seen.add(it.id)) out.add(it);
    }
    return out;
  }

  // Cold start (nothing loaded yet) takes over the whole screen with a
  // spinner/error; once a first load has succeeded, pull-to-refresh and
  // return-to-tab run as a silent background refresh instead (_refreshing),
  // so existing content never disappears mid-refresh — same split as
  // TeamDetailScreen.
  Future<void> _load() async {
    final isInitialLoad = !_hasLoadedOnce;
    setState(() {
      if (isInitialLoad) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });
    try {
      final page = await _svc.getNotifications(limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = _dedupe(page.items);
        _unreadCount = page.unreadCount;
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _hasLoadedOnce = true;
        _loading = false;
        _refreshing = false;
      });
      _pushBadge(page.unreadCount);
    } catch (e) {
      if (!mounted) return;
      if (isInitialLoad) {
        setState(() {
          _error = userErrorText(e);
          _loading = false;
        });
      } else {
        setState(() => _refreshing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final cursor = _nextCursor;
    if (cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _svc.getNotifications(
        limit: _pageSize,
        before: cursor.createdAt,
        beforeId: cursor.id,
      );
      if (!mounted) return;
      final existingIds = _items.map((e) => e.id).toSet();
      setState(() {
        _items = [
          ..._items,
          ...page.items.where((it) => !existingIds.contains(it.id)),
        ];
        _unreadCount = page.unreadCount;
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
      _pushBadge(page.unreadCount);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
    }
  }

  Future<void> _markRead(NotificationItem item) async {
    if (item.isRead) return;
    try {
      await _svc.markRead(item.id);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final it in _items) it.id == item.id ? it.markedRead() : it,
        ];
        _unreadCount = _unreadCount > 0 ? _unreadCount - 1 : 0;
      });
      _pushBadge(_unreadCount);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
    }
  }

  Future<void> _markAllRead() async {
    if (_unreadCount == 0 || _markingAllRead) return;
    setState(() => _markingAllRead = true);
    try {
      await _svc.markAllRead();
      if (!mounted) return;
      setState(() {
        _items = [for (final it in _items) it.isRead ? it : it.markedRead()];
        _unreadCount = 0;
        _markingAllRead = false;
      });
      _pushBadge(0);
    } catch (e) {
      if (!mounted) return;
      setState(() => _markingAllRead = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
    }
  }

  Future<void> _archive(NotificationItem item) async {
    if (_busyIds.contains(item.id)) return;
    setState(() => _busyIds.add(item.id));
    try {
      await _svc.archiveNotification(item.id);
      if (!mounted) return;
      setState(() {
        _items = _items.where((it) => it.id != item.id).toList();
        _busyIds.remove(item.id);
        if (item.isUnread) {
          _unreadCount = _unreadCount > 0 ? _unreadCount - 1 : 0;
        }
      });
      _pushBadge(_unreadCount);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم أرشفة الإشعار')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyIds.remove(item.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
    }
  }

  Future<void> _onTapItem(NotificationItem item) async {
    if (item.isUnread) {
      await _markRead(item);
    }
    if (!mounted) return;
    _navigateForAction(item);
  }

  void _navigateForAction(NotificationItem item) {
    switch (item.actionType) {
      case 'open_team':
      case 'open_team_shopping':
        final payloadTeamId = item.actionPayload?['team_id'];
        final teamId =
            item.teamId ?? (payloadTeamId is String ? payloadTeamId : null);
        if (teamId == null || teamId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر فتح الفريق المرتبط بهذا الإشعار')),
          );
          return;
        }
        context.push('/teams/$teamId');
      default:
        // Unknown or missing action_type: nothing to do, already marked
        // read above — stay on the notifications screen.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_hasLoadedOnce) {
      return _shell(body: const Center(child: CircularProgressIndicator()));
    }
    if (_error != null && !_hasLoadedOnce) {
      return _shell(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(ZadTokens.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
                const SizedBox(height: ZadTokens.s3),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final Widget body;
    if (_items.isEmpty) {
      body = LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: const Center(
              child: ZadEmptyState(
                icon: Icons.notifications_none_outlined,
                message: 'لا توجد إشعارات حالياً',
                big: true,
              ),
            ),
          ),
        ),
      );
    } else {
      body = ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          ZadTokens.s4,
          ZadTokens.s4,
          ZadTokens.s4,
          96,
        ),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: ZadTokens.s4),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final item = _items[index];
          return _NotificationCard(
            item: item,
            busy: _busyIds.contains(item.id),
            onTap: () => _onTapItem(item),
            onArchive: () => _archive(item),
          );
        },
      );
    }

    return _shell(body: RefreshIndicator(onRefresh: _load, child: body));
  }

  Widget _shell({required Widget body}) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ZadLogoBadge(size: 30),
            SizedBox(width: ZadTokens.s2 + 2),
            Flexible(
              child: Text('الإشعارات', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        bottom: _refreshing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
        actions: [
          TextButton(
            onPressed: (_unreadCount > 0 && !_markingAllRead)
                ? _markAllRead
                : null,
            child: const Text(
              'تحديد الكل كمقروء',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const ZadBottomNav(current: ZadTab.notifications),
      body: body,
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationItem item;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onArchive;

  const _NotificationCard({
    required this.item,
    required this.busy,
    required this.onTap,
    required this.onArchive,
  });

  static IconData _iconForType(String type) => switch (type) {
    'team_turn_today' => Icons.today_outlined,
    'team_turn_skipped' => Icons.skip_next_outlined,
    'shopping_report_submitted' => Icons.shopping_cart_outlined,
    'shopping_report_accepted' => Icons.check_circle_outline,
    'shopping_report_rejected' => Icons.cancel_outlined,
    _ => Icons.notifications_none_outlined,
  };

  static String _formatWhen(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final unread = item.isUnread;
    return ZadCard(
      margin: const EdgeInsets.only(bottom: ZadTokens.s3),
      highlighted: unread,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ZadTokens.s3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (unread ? ZadTokens.primary : ZadTokens.textMuted)
                      .withValues(alpha: 0.12),
                ),
                child: Icon(
                  _iconForType(item.type),
                  size: 20,
                  color: unread ? ZadTokens.primary : ZadTokens.textMuted,
                ),
              ),
              const SizedBox(width: ZadTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontWeight: unread
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: ZadTokens.text,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsetsDirectional.only(
                              start: ZadTokens.s2,
                            ),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: ZadTokens.gold,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.body,
                      style: const TextStyle(color: ZadTokens.textMuted),
                    ),
                    const SizedBox(height: ZadTokens.s1),
                    Text(
                      ltrFragment(_formatWhen(item.createdAt)),
                      style: const TextStyle(
                        fontSize: 11,
                        color: ZadTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              busy
                  ? const Padding(
                      padding: EdgeInsets.all(ZadTokens.s2),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'أرشفة',
                      icon: const Icon(Icons.archive_outlined, size: 20),
                      onPressed: onArchive,
                      color: ZadTokens.textMuted,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
