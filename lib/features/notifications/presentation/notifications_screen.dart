import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/refresh/app_refresh_coordinator.dart';
import '../../../core/routing/route_observer.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/ltr_fragment.dart';
import '../../../core/widgets/zad_bottom_nav.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_empty_state.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_logo_badge.dart';
import '../../../core/widgets/zad_messaging_badge_scope.dart';
import '../../../core/widgets/zad_notification_badge_scope.dart';
import '../../../core/widgets/zad_permanent_delete_confirm.dart';
import '../../../services/auth_service.dart';
import '../data/notification_service.dart';
import '../domain/notification_models.dart';

const int _pageSize = 25;
const Duration _pollInterval = Duration(seconds: 10);

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

class _NotificationsScreenState extends State<NotificationsScreen>
    with RouteAware {
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
  bool _refreshInFlight = false;
  bool _refreshAgain = false;
  bool _rootVisible = false;
  bool _ignoreInitialMatchingRouteSignal = false;
  bool _foreground = true;
  bool _routeCovered = false;
  int _requestGeneration = 0;
  int _pollFailures = 0;
  Timer? _pollTimer;
  VoidCallback? _unsubscribeRefresh;
  VoidCallback? _unsubscribeRoute;
  VoidCallback? _unsubscribeForeground;
  ModalRoute<dynamic>? _observedRoute;
  final Set<String> _busyIds = {};
  final Set<String> _selectedIds = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? NotificationService(widget.authService);
    final currentRootRoute = AppRefreshCoordinator.instance.currentRootRoute;
    _rootVisible =
        currentRootRoute == null || currentRootRoute == '/notifications';
    _ignoreInitialMatchingRouteSignal = currentRootRoute == '/notifications';
    AppRefreshCoordinator.instance.markDirty(
      AppRefreshScope.notifications,
      notify: false,
    );
    _scrollController.addListener(_onScroll);
    _unsubscribeRefresh = AppRefreshCoordinator.instance.subscribe(
      AppRefreshScope.notifications,
      (_) => _onInvalidated(),
    );
    _unsubscribeRoute = AppRefreshCoordinator.instance
        .subscribeRootRouteVisible(_onRootRouteVisible);
    _unsubscribeForeground = AppRefreshCoordinator.instance
        .subscribeAppForeground(_onForegroundChanged);
    _refresh(showErrors: true);
    _startPolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _observedRoute) return;
    if (_observedRoute != null) {
      appRouteObserver.unsubscribe(this);
    }
    _observedRoute = route;
    if (route != null) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _routeCovered = true;
    _stopPolling();
  }

  @override
  void didPopNext() {
    if (!_routeCovered) return;
    final currentRootRoute = AppRefreshCoordinator.instance.currentRootRoute;
    if (currentRootRoute != null && currentRootRoute != '/notifications') {
      return;
    }
    _routeCovered = false;
    _activate();
  }

  @override
  void dispose() {
    _unsubscribeRefresh?.call();
    _unsubscribeRoute?.call();
    _unsubscribeForeground?.call();
    appRouteObserver.unsubscribe(this);
    _stopPolling();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onRootRouteVisible(String route) {
    final visible = route == '/notifications';
    _rootVisible = visible;
    if (visible) {
      _routeCovered = false;
      if (_ignoreInitialMatchingRouteSignal) {
        _ignoreInitialMatchingRouteSignal = false;
        _startPolling();
      } else {
        _activate();
      }
    } else {
      _ignoreInitialMatchingRouteSignal = false;
      _stopPolling();
    }
  }

  void _onForegroundChanged(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  bool get _visible => _rootVisible && !_routeCovered;

  void _onInvalidated() {
    if (!_foreground || !_visible) return;
    _startPolling(immediate: true);
  }

  void _activate() {
    AppRefreshCoordinator.instance.markDirty(
      AppRefreshScope.notifications,
      notify: false,
    );
    _startPolling(immediate: true);
  }

  void _startPolling({bool immediate = false}) {
    if (!_foreground || !_visible) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (immediate) {
      unawaited(_refresh(silent: true).whenComplete(_scheduleNextPoll));
    } else {
      _scheduleNextPoll();
    }
  }

  void _scheduleNextPoll() {
    if (!mounted || !_foreground || !_visible) return;
    _pollTimer?.cancel();
    final multiplier = 1 << _pollFailures.clamp(0, 3).toInt();
    _pollTimer = Timer(_pollInterval * multiplier, () async {
      await _refresh(silent: true);
      _scheduleNextPoll();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _pushBadge(int count) {
    ZadNotificationBadgeScope.maybeOf(
      context,
    )?.setCount(count, markNotificationsDirtyOnIncrease: false);
  }

  List<NotificationItem> _dedupe(List<NotificationItem> items) {
    final seen = <String>{};
    final out = <NotificationItem>[];
    for (final it in items) {
      if (seen.add(it.id)) out.add(it);
    }
    return out;
  }

  List<NotificationItem> _mergeFirstPage(NotificationsPage page) {
    final fresh = _dedupe(page.items);
    if (!_hasLoadedOnce || !page.hasMore || page.nextCursor == null) {
      return fresh;
    }

    final freshIds = fresh.map((item) => item.id).toSet();
    final cursor = page.nextCursor!;
    bool isOlderThanFirstPage(NotificationItem item) {
      final timeOrder = item.createdAt.compareTo(cursor.createdAt);
      return timeOrder < 0 ||
          (timeOrder == 0 && item.id.compareTo(cursor.id) < 0);
    }

    return [
      ...fresh,
      ..._items.where(
        (item) => !freshIds.contains(item.id) && isOlderThanFirstPage(item),
      ),
    ];
  }

  // Cold start (nothing loaded yet) takes over the whole screen with a
  // spinner/error; once a first load has succeeded, pull-to-refresh and
  // return-to-tab run as a silent background refresh instead (_refreshing),
  // so existing content never disappears mid-refresh — same split as
  // TeamDetailScreen.
  Future<void> _refresh({bool silent = false, bool showErrors = false}) async {
    if (_refreshInFlight) {
      _refreshAgain = true;
      return;
    }
    _refreshInFlight = true;
    final generation = ++_requestGeneration;
    final isInitialLoad = !_hasLoadedOnce;
    if (!silent || isInitialLoad) {
      setState(() {
        if (isInitialLoad) {
          _loading = true;
        } else {
          _refreshing = true;
        }
        _error = null;
      });
    } else if (_hasLoadedOnce) {
      setState(() => _refreshing = true);
    }
    try {
      final page = await _svc.getNotifications(limit: _pageSize);
      if (!mounted || generation != _requestGeneration) {
        if (mounted) setState(() => _loadingMore = false);
        return;
      }
      setState(() {
        _items = _mergeFirstPage(page);
        _unreadCount = page.unreadCount;
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _hasLoadedOnce = true;
        _loading = false;
        _refreshing = false;
      });
      _pushBadge(page.unreadCount);
      AppRefreshCoordinator.instance.markSynchronized(
        AppRefreshScope.notifications,
      );
      _pollFailures = 0;
    } catch (e) {
      if (!mounted) return;
      if (isInitialLoad) {
        setState(() {
          _error = userErrorText(e);
          _loading = false;
        });
      } else {
        setState(() => _refreshing = false);
        _pollFailures++;
        if (showErrors) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
        }
      }
    } finally {
      _refreshInFlight = false;
      if (_refreshAgain && mounted) {
        _refreshAgain = false;
        unawaited(_refresh(silent: true));
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _refreshInFlight || !_hasMore) return;
    final cursor = _nextCursor;
    if (cursor == null) return;
    final generation = ++_requestGeneration;
    setState(() => _loadingMore = true);
    try {
      final page = await _svc.getNotifications(
        limit: _pageSize,
        before: cursor.createdAt,
        beforeId: cursor.id,
      );
      if (!mounted || generation != _requestGeneration) {
        if (mounted) setState(() => _loadingMore = false);
        return;
      }
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
      AppRefreshCoordinator.instance.invalidate(
        AppRefreshScope.notificationBadge,
      );
      unawaited(_refresh(silent: true));
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
      AppRefreshCoordinator.instance.invalidate(
        AppRefreshScope.notificationBadge,
      );
      unawaited(_refresh(silent: true));
    } catch (e) {
      if (!mounted) return;
      setState(() => _markingAllRead = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
    }
  }

  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty ||
        !await zadPermanentDeleteConfirm(context, count: ids.length)) {
      return;
    }
    try {
      final unread = await _svc.deleteNotifications(ids);
      if (!mounted) return;
      setState(() {
        _items = _items.where((it) => !ids.contains(it.id)).toList();
        _selectedIds.clear();
        _unreadCount = unread;
      });
      _pushBadge(_unreadCount);
      AppRefreshCoordinator.instance.invalidate(
        AppRefreshScope.notificationBadge,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
    }
  }

  void _toggleSelection(String id) => setState(() {
    _selectedIds.contains(id) ? _selectedIds.remove(id) : _selectedIds.add(id);
  });

  Future<void> _onTapItem(NotificationItem item) async {
    if (item.isUnread) {
      await _markRead(item);
    }
    if (!mounted) return;
    await _navigateForAction(item);
  }

  Future<T?> _pushActionRoute<T>(String route, {Object? extra}) async {
    _routeCovered = true;
    _stopPolling();
    final result = await context.push<T>(route, extra: extra);
    if (!mounted) return result;
    if (_routeCovered) {
      _routeCovered = false;
      _activate();
    }
    return result;
  }

  Future<void> _navigateForAction(NotificationItem item) async {
    switch (item.actionType) {
      case 'open_team':
      case 'open_team_shopping':
        final payloadTeamId = item.actionPayload?['team_id'];
        final teamId =
            item.teamId ?? (payloadTeamId is String ? payloadTeamId : null);
        if (teamId == null || teamId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر فتح الفريق المرتبط بهذا الإشعار'),
            ),
          );
          return;
        }
        await _pushActionRoute<void>('/teams/$teamId');
      case 'open_team_conversation':
        final payload = item.actionPayload;
        final teamId = payload?['team_id'] is String
            ? payload!['team_id'] as String
            : item.teamId;
        final conversationId = payload?['conversation_id'];
        if (teamId == null ||
            teamId.isEmpty ||
            conversationId is! String ||
            conversationId.isEmpty) {
          if (teamId != null && teamId.isNotEmpty) {
            await _pushActionRoute<void>('/teams/$teamId');
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر فتح المحادثة المرتبطة بهذا الإشعار'),
            ),
          );
          return;
        }
        await _pushActionRoute<void>(
          '/messages/conversation/$conversationId',
          extra: {'teamId': teamId},
        );
        if (mounted) {
          ZadMessagingBadgeScope.maybeOf(context)?.refresh();
          AppRefreshCoordinator.instance.invalidateMany({
            AppRefreshScope.messages,
            AppRefreshScope.messagingBadge,
          });
        }
      case 'open_team_announcements':
        final payload = item.actionPayload;
        final teamId = payload?['team_id'] is String
            ? payload!['team_id'] as String
            : item.teamId;
        if (teamId == null || teamId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر فتح الإعلانات المرتبطة بهذا الإشعار'),
            ),
          );
          return;
        }
        final announcementId = payload?['announcement_id'];
        await _pushActionRoute<void>(
          '/teams/$teamId/announcements',
          extra: {
            if (announcementId is String) 'announcementId': announcementId,
          },
        );
        if (mounted) {
          ZadMessagingBadgeScope.maybeOf(context)?.refresh();
          AppRefreshCoordinator.instance.invalidateMany({
            AppRefreshScope.announcements,
            AppRefreshScope.messagingBadge,
          });
        }
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
                  onPressed: () => _refresh(showErrors: true),
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
            selected: _selectedIds.contains(item.id),
            selecting: _selectedIds.isNotEmpty,
            onTap: _selectedIds.isNotEmpty
                ? () => _toggleSelection(item.id)
                : () => _onTapItem(item),
            onSelect: () => _toggleSelection(item.id),
          );
        },
      );
    }

    return _shell(
      body: RefreshIndicator(
        onRefresh: () => _refresh(showErrors: true),
        child: body,
      ),
    );
  }

  Widget _shell({required Widget body}) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ZadLogoBadge(size: 30),
            SizedBox(width: ZadTokens.s2 + 2),
            Flexible(child: Text('الإشعارات', overflow: TextOverflow.ellipsis)),
          ],
        ),
        bottom: _refreshing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
        actions: [
          if (_selectedIds.isNotEmpty) ...[
            IconButton(
              onPressed: () => setState(() => _selectedIds.clear()),
              icon: const Icon(Icons.close),
              tooltip: 'إلغاء التحديد',
            ),
            IconButton(
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'حذف المحدد',
            ),
          ] else ...[
            IconButton(
              onPressed: _items.isEmpty
                  ? null
                  : () => setState(
                      () => _selectedIds.addAll(_items.map((e) => e.id)),
                    ),
              icon: const Icon(Icons.checklist),
              tooltip: 'تحديد',
            ),
            IconButton(
              onPressed: (_unreadCount > 0 && !_markingAllRead)
                  ? _markAllRead
                  : null,
              icon: const Icon(Icons.done_all),
              tooltip: 'تحديد الكل كمقروء',
            ),
          ],
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
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSelect;

  const _NotificationCard({
    required this.item,
    required this.busy,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onSelect,
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
              selecting
                  ? Checkbox(value: selected, onChanged: (_) => onSelect())
                  : busy
                  ? const Padding(
                      padding: EdgeInsets.all(ZadTokens.s2),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'حذف نهائياً',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: onSelect,
                      color: ZadTokens.textMuted,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
