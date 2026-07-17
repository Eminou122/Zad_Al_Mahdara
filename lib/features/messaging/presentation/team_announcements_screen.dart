import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/refresh/app_refresh_coordinator.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/ltr_fragment.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_empty_state.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_messaging_badge_scope.dart';
import '../../../services/auth_service.dart';
import '../../teams/data/team_service.dart';
import '../../teams/domain/team_models.dart';
import '../data/team_messaging_service.dart';
import '../domain/team_messaging_models.dart';
import 'message_team_leader_dialog.dart';

const int _pageSize = 30;
const Duration _pollInterval = Duration(seconds: 12);

/// Team announcements list. [teamId] null = the aggregate "all my teams"
/// view used by the messaging home الإعلانات tab; a concrete [teamId] =
/// the team-scoped view reached from a team_detail leader link or an
/// open_team_announcements notification. [isLeader] gates the compose
/// entry point and is only meaningful together with a concrete [teamId].
class TeamAnnouncementsScreen extends StatefulWidget {
  final AuthService authService;
  final String? teamId;
  final String? teamName;
  final bool isLeader;
  final String? focusAnnouncementId;
  final TeamMessagingService? service;
  final TeamService? teamService;
  final bool showAppBar;
  final bool active;

  const TeamAnnouncementsScreen({
    super.key,
    required this.authService,
    this.teamId,
    this.teamName,
    this.isLeader = false,
    this.focusAnnouncementId,
    this.service,
    this.teamService,
    this.showAppBar = true,
    this.active = true,
  });

  @override
  State<TeamAnnouncementsScreen> createState() =>
      _TeamAnnouncementsScreenState();
}

class _TeamAnnouncementsScreenState extends State<TeamAnnouncementsScreen> {
  late final TeamMessagingService _svc;
  late final TeamService _teamSvc;
  final ScrollController _scrollController = ScrollController();

  List<TeamAnnouncement> _items = [];
  bool _hasMore = false;
  TeamAnnouncementCursor? _nextCursor;

  bool _hasLoadedOnce = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _refreshInFlight = false;
  bool _refreshAgain = false;
  bool _foreground = true;
  bool _rootVisible = true;
  bool _routeCovered = false;
  int _requestGeneration = 0;
  String? _error;
  final Set<String> _markingRead = {};
  bool _canMessageLeader = false;
  Timer? _pollTimer;
  VoidCallback? _unsubscribeRefresh;
  VoidCallback? _unsubscribeRoute;
  VoidCallback? _unsubscribeForeground;

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? TeamMessagingService(widget.authService);
    _teamSvc = widget.teamService ?? TeamService(widget.authService);
    _scrollController.addListener(_onScroll);
    _unsubscribeRefresh = AppRefreshCoordinator.instance.subscribe(
      AppRefreshScope.announcements,
      (_) => _refreshNow(),
    );
    _unsubscribeRoute = AppRefreshCoordinator.instance
        .subscribeRootRouteVisible(_onRootRouteVisible);
    _unsubscribeForeground = AppRefreshCoordinator.instance
        .subscribeAppForeground(_onForegroundChanged);
    _load();
    _loadEligibility();
    _startPolling();
  }

  @override
  void dispose() {
    _stopPolling();
    _unsubscribeRefresh?.call();
    _unsubscribeRoute?.call();
    _unsubscribeForeground?.call();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TeamAnnouncementsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (_visible) {
        _refreshNow();
      } else {
        _stopPolling();
      }
    }
    if (oldWidget.teamId == widget.teamId) return;
    _canMessageLeader = false;
    _loadEligibility();
  }

  bool get _usesRootVisibility => !widget.showAppBar && widget.teamId == null;

  bool get _visible =>
      widget.active && (!_usesRootVisibility || _rootVisible) && !_routeCovered;

  void _onForegroundChanged(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  void _onRootRouteVisible(String route) {
    if (!_usesRootVisibility) return;
    final visible = route == '/messages';
    if (_rootVisible == visible) return;
    _rootVisible = visible;
    if (visible) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  void _refreshNow() {
    if (!_foreground || !_visible) return;
    _startPolling(immediate: true);
  }

  void _startPolling({bool immediate = false}) {
    if (!_foreground || !_visible) return;
    _pollTimer?.cancel();
    if (immediate) unawaited(_load(silent: true));
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_load(silent: true));
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  bool _eligibleToMessageLeader(TeamDetail detail) {
    final profile = widget.authService.profile;
    if (profile == null || !profile.isActive || !detail.isMember) return false;
    for (final member in detail.members) {
      if (member.profileId == profile.id) {
        return member.isActive && member.hasAccount && member.role != 'leader';
      }
    }
    return false;
  }

  Future<void> _loadEligibility() async {
    final teamId = widget.teamId;
    if (teamId == null) return;
    try {
      final detail = await _teamSvc.getTeamDetail(teamId);
      if (!mounted) return;
      setState(() => _canMessageLeader = _eligibleToMessageLeader(detail));
    } catch (_) {
      if (mounted) setState(() => _canMessageLeader = false);
    }
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  List<TeamAnnouncement> _dedupe(List<TeamAnnouncement> items) {
    final seen = <String>{};
    final out = <TeamAnnouncement>[];
    for (final it in items) {
      if (seen.add(it.id)) out.add(it);
    }
    return out;
  }

  Future<void> _load({bool silent = false, bool showErrors = false}) async {
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
      final page = await _svc.getMyTeamAnnouncements(
        teamId: widget.teamId,
        limit: _pageSize,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _items = _dedupe(page.items);
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _hasLoadedOnce = true;
        _loading = false;
        _refreshing = false;
      });
      if (widget.focusAnnouncementId != null) {
        final match = _items
            .where((a) => a.id == widget.focusAnnouncementId)
            .toList();
        if (match.isNotEmpty && !match.first.isRead) {
          _markRead(match.first);
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (isInitialLoad) {
        setState(() {
          _error = userErrorText(e);
          _loading = false;
        });
      } else {
        setState(() => _refreshing = false);
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
        unawaited(_load(silent: true));
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
      final page = await _svc.getMyTeamAnnouncements(
        teamId: widget.teamId,
        limit: _pageSize,
        before: cursor,
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
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
    }
  }

  Future<void> _markRead(TeamAnnouncement item) async {
    if (item.isRead || _markingRead.contains(item.id)) return;
    setState(() => _markingRead.add(item.id));
    try {
      await _svc.markAnnouncementRead(item.id);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final a in _items)
            a.id == item.id
                ? TeamAnnouncement(
                    id: a.id,
                    teamId: a.teamId,
                    teamName: a.teamName,
                    authorProfileId: a.authorProfileId,
                    authorName: a.authorName,
                    title: a.title,
                    body: a.body,
                    createdAt: a.createdAt,
                    isRead: true,
                  )
                : a,
        ];
        _markingRead.remove(item.id);
      });
      ZadMessagingBadgeScope.maybeOf(context)?.refresh();
      AppRefreshCoordinator.instance.invalidate(AppRefreshScope.messagingBadge);
    } catch (_) {
      if (!mounted) return;
      setState(() => _markingRead.remove(item.id));
      // Read-state is best-effort UI sugar; a failure here is silent.
    }
  }

  Future<void> _openCompose() async {
    final teamId = widget.teamId;
    if (teamId == null) return;
    _routeCovered = true;
    _stopPolling();
    final created = await context.push<bool>(
      '/teams/$teamId/announcements/new',
      extra: widget.teamName,
    );
    if (!mounted) return;
    _routeCovered = false;
    if (created != true) {
      _startPolling();
      return;
    }
    AppRefreshCoordinator.instance.invalidateMany({
      AppRefreshScope.announcements,
      AppRefreshScope.messages,
      AppRefreshScope.messagingBadge,
      AppRefreshScope.notifications,
      AppRefreshScope.notificationBadge,
    });
    _refreshNow();
    ZadMessagingBadgeScope.maybeOf(context)?.refresh();
  }

  Future<void> _openMessageLeaderComposer(TeamAnnouncement item) async {
    if (!_canMessageLeader) return;
    final result = await showDialog<SentTeamMessage>(
      context: context,
      builder: (_) =>
          MessageTeamLeaderDialog(service: _svc, teamId: item.teamId),
    );
    if (result == null || !mounted) return;
    AppRefreshCoordinator.instance.invalidateMany({
      AppRefreshScope.messages,
      AppRefreshScope.messagingBadge,
    });
    ZadMessagingBadgeScope.maybeOf(context)?.refresh();
    _routeCovered = true;
    _stopPolling();
    await context.push(
      '/messages/conversation/${result.conversation.id}',
      extra: {
        'teamId': result.conversation.teamId,
        'teamName': item.teamName,
        'currentUserRole': 'member',
      },
    );
    if (!mounted) return;
    _routeCovered = false;
    _refreshNow();
  }

  @override
  Widget build(BuildContext context) {
    final body = _body();
    if (!widget.showAppBar) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.teamName ?? 'الإعلانات'),
        bottom: _refreshing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      floatingActionButton: (widget.teamId != null && widget.isLeader)
          ? FloatingActionButton.extended(
              onPressed: _openCompose,
              icon: const Icon(Icons.add),
              label: const Text('إعلان جديد'),
            )
          : null,
      body: SafeArea(child: body),
    );
  }

  Widget _body() {
    if (_loading && !_hasLoadedOnce) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && !_hasLoadedOnce) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ZadTokens.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ZadInfoBanner(
                'تعذر تحميل الإعلانات',
                kind: ZadBannerKind.danger,
              ),
              const SizedBox(height: ZadTokens.s3),
              OutlinedButton.icon(
                onPressed: () => _load(showErrors: true),
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    Widget content;
    if (_items.isEmpty) {
      content = LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: const Center(
              child: ZadEmptyState(
                icon: Icons.campaign_outlined,
                message: 'لا توجد إعلانات للفريق',
                big: true,
              ),
            ),
          ),
        ),
      );
    } else {
      content = ListView.builder(
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
          return _AnnouncementCard(
            item: item,
            busy: _markingRead.contains(item.id),
            showTeamName: widget.teamId == null,
            onMessageLeader: _canMessageLeader
                ? () => _openMessageLeaderComposer(item)
                : null,
            onTap: () => _markRead(item),
          );
        },
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(showErrors: true),
      child: content,
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final TeamAnnouncement item;
  final bool busy;
  final bool showTeamName;
  final VoidCallback? onMessageLeader;
  final VoidCallback onTap;

  const _AnnouncementCard({
    required this.item,
    required this.busy,
    required this.showTeamName,
    this.onMessageLeader,
    required this.onTap,
  });

  static String _formatWhen(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final unread = !item.isRead;
    return ZadCard(
      margin: const EdgeInsets.only(bottom: ZadTokens.s3),
      highlighted: unread,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ZadTokens.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title ?? 'إعلان',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: unread ? FontWeight.bold : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (unread)
                    const SizedBox(
                      width: 8,
                      height: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ZadTokens.gold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (showTeamName)
                Text(
                  item.teamName,
                  style: const TextStyle(
                    fontSize: 11,
                    color: ZadTokens.textMuted,
                  ),
                ),
              const SizedBox(height: 4),
              Text(item.body, style: const TextStyle(color: ZadTokens.text)),
              const SizedBox(height: ZadTokens.s1),
              Text(
                '${item.authorName} · ${ltrFragment(_formatWhen(item.createdAt))}',
                style: const TextStyle(
                  fontSize: 11,
                  color: ZadTokens.textMuted,
                ),
              ),
              if (onMessageLeader != null) ...[
                const SizedBox(height: ZadTokens.s2),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: onMessageLeader,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('مراسلة قائد الفريق'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
