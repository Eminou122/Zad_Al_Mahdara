import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/refresh/app_refresh_coordinator.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/ltr_fragment.dart';
import '../../../core/widgets/zad_bottom_nav.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_empty_state.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_logo_badge.dart';
import '../../../core/widgets/zad_messaging_badge_scope.dart';
import '../../../core/widgets/zad_permanent_delete_confirm.dart';
import '../../../core/widgets/zad_nested_swipe_scope.dart';
import '../../../services/auth_service.dart';
import '../../teams/data/team_service.dart';
import '../data/team_messaging_service.dart';
import '../domain/team_messaging_models.dart';
import 'team_announcements_screen.dart';

const int _pageSize = 30;

class MessagingHomeScreen extends StatefulWidget {
  final AuthService authService;
  final TeamMessagingService? service;
  final TeamService? teamService;
  final Duration inboxRefreshInterval;

  const MessagingHomeScreen({
    super.key,
    required this.authService,
    this.service,
    this.teamService,
    this.inboxRefreshInterval = const Duration(seconds: 10),
  });

  @override
  State<MessagingHomeScreen> createState() => _MessagingHomeScreenState();
}

/// Same segmented-control + [PageController] + [PageView] pattern as
/// TeamsScreen's فرقي/الفرق العامة sections — not a [TabController]/
/// [TabBarView], which owns its [PageController] internally and can't
/// register it with the root [ZadSwipeNav]. Registering our own controller
/// via [PageControllerRegistration] lets the root swipe detector defer to
/// this page's own horizontal drag whenever it still has room to move, so
/// swiping between المحادثات/الإعلانات never fights with (or accidentally
/// triggers) a root tab change.
class _MessagingHomeScreenState extends State<MessagingHomeScreen> {
  late final TeamMessagingService _svc;
  late final TeamService _teamSvc;
  late final PageController _pageController;
  int _messagesPage = 0;

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? TeamMessagingService(widget.authService);
    _teamSvc = widget.teamService ?? TeamService(widget.authService);
    _pageController = PageController();
    _pageController.addListener(_onPageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PageControllerRegistration(_pageController).dispatch(context);
      }
    });
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page ?? 0;
    final rounded = page.round();
    if (rounded != _messagesPage) {
      setState(() => _messagesPage = rounded);
    }
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ZadLogoBadge(size: 30),
            SizedBox(width: ZadTokens.s2 + 2),
            Flexible(child: Text('الرسائل', overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      bottomNavigationBar: const ZadBottomNav(current: ZadTab.messages),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(
                ZadTokens.s3,
                ZadTokens.s3,
                ZadTokens.s3,
                ZadTokens.s1,
              ),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                maxWidth: ZadTokens.contentMaxWidth,
              ),
              decoration: BoxDecoration(
                color: ZadTokens.surfaceContainer,
                borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
              ),
              child: Row(
                children: [
                  _tab('المحادثات', _messagesPage == 0, () => _goToPage(0)),
                  _tab('الإعلانات', _messagesPage == 1, () => _goToPage(1)),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                scrollDirection: Axis.horizontal,
                children: [
                  _ConversationsTab(
                    authService: widget.authService,
                    service: _svc,
                    teamService: _teamSvc,
                    refreshInterval: widget.inboxRefreshInterval,
                    active: _messagesPage == 0,
                  ),
                  TeamAnnouncementsScreen(
                    authService: widget.authService,
                    service: _svc,
                    showAppBar: false,
                    active: _messagesPage == 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? ZadTokens.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(ZadTokens.radiusSm + 2),
          boxShadow: selected ? ZadTokens.cardShadow : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : ZadTokens.textMuted,
          ),
        ),
      ),
    ),
  );
}

class _ConversationsTab extends StatefulWidget {
  final AuthService authService;
  final TeamMessagingService service;
  final TeamService teamService;
  final Duration refreshInterval;
  final bool active;

  const _ConversationsTab({
    required this.authService,
    required this.service,
    required this.teamService,
    required this.refreshInterval,
    required this.active,
  });

  @override
  State<_ConversationsTab> createState() => _ConversationsTabState();
}

class _ConversationsTabState extends State<_ConversationsTab> {
  final ScrollController _scrollController = ScrollController();

  List<TeamConversationSummary> _items = [];
  bool _hasMore = false;
  TeamConversationCursor? _nextCursor;

  bool _hasLoadedOnce = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _foreground = true;
  bool _rootVisible = true;
  bool _routeCovered = false;
  bool _refreshInFlight = false;
  bool _refreshAgain = false;
  int _requestGeneration = 0;
  String? _error;
  Timer? _refreshTimer;
  VoidCallback? _unsubscribeRefresh;
  VoidCallback? _unsubscribeRoute;
  VoidCallback? _unsubscribeForeground;

  // Only used to pick between the member/leader empty-state copy when the
  // conversation list itself is empty (an empty page carries no
  // current_user_role to read). Best-effort: defaults to the member copy
  // on failure.
  bool _isLeaderOfAnyTeam = false;
  final Set<String> _selectedIds = {};

  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty ||
        !await zadPermanentDeleteConfirm(context, count: ids.length)) {
      return;
    }
    try {
      for (final id in ids) {
        await widget.service.deleteConversation(id);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _items = _items.where((item) => !ids.contains(item.id)).toList();
        _selectedIds.clear();
      });
      ZadMessagingBadgeScope.maybeOf(context)?.refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  void _toggle(String id) => setState(
    () => _selectedIds.contains(id)
        ? _selectedIds.remove(id)
        : _selectedIds.add(id),
  );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _unsubscribeRefresh = AppRefreshCoordinator.instance.subscribe(
      AppRefreshScope.messages,
      (_) => _refreshNow(),
    );
    _unsubscribeRoute = AppRefreshCoordinator.instance
        .subscribeRootRouteVisible(_onRootRouteVisible);
    _unsubscribeForeground = AppRefreshCoordinator.instance
        .subscribeAppForeground(_onForegroundChanged);
    _load();
    _loadLeadershipHint();
  }

  @override
  void didUpdateWidget(covariant _ConversationsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (_visible) {
      _refreshNow();
    } else {
      _stopAutoRefresh();
    }
  }

  Future<void> _loadLeadershipHint() async {
    try {
      final teams = await widget.teamService.getMyTeams();
      if (!mounted) return;
      if (teams.any((t) => t.isLeader ?? false)) {
        setState(() => _isLeaderOfAnyTeam = true);
      }
    } catch (_) {
      // Best-effort; keeps the member-oriented empty state on failure.
    }
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    _unsubscribeRefresh?.call();
    _unsubscribeRoute?.call();
    _unsubscribeForeground?.call();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onForegroundChanged(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      _startAutoRefresh();
    } else {
      _stopAutoRefresh();
    }
  }

  void _onRootRouteVisible(String route) {
    final visible = route == '/messages';
    if (_rootVisible == visible) return;
    _rootVisible = visible;
    if (visible) {
      _startAutoRefresh();
    } else {
      _stopAutoRefresh();
    }
  }

  bool get _visible => widget.active && _rootVisible && !_routeCovered;

  void _refreshNow() {
    if (!_foreground || !_visible) return;
    _startAutoRefresh(immediate: true);
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  List<TeamConversationSummary> _dedupe(List<TeamConversationSummary> items) {
    final seen = <String>{};
    final out = <TeamConversationSummary>[];
    for (final it in items) {
      if (seen.add(it.id)) out.add(it);
    }
    return out;
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshInFlight) {
      _refreshAgain = true;
      return;
    }
    if (silent && !_hasLoadedOnce) return;
    _refreshInFlight = true;
    final generation = ++_requestGeneration;
    final isInitialLoad = !_hasLoadedOnce;
    if (!silent) {
      setState(() {
        if (isInitialLoad) {
          _loading = true;
        } else {
          _refreshing = true;
        }
        _error = null;
      });
    }
    try {
      final page = await widget.service.getMyTeamConversations(
        limit: _pageSize,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _items = silent
            ? _dedupe([
                ...page.items,
                ..._items.where(
                  (old) => !page.items.any((fresh) => fresh.id == old.id),
                ),
              ])
            : _dedupe(page.items);
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _hasLoadedOnce = true;
        _loading = false;
        _refreshing = false;
      });
      ZadMessagingBadgeScope.maybeOf(context)?.refresh();
      _startAutoRefresh();
    } catch (e) {
      if (!mounted) return;
      if (silent) {
        return;
      }
      if (isInitialLoad) {
        setState(() {
          _error = userErrorText(e);
          _loading = false;
        });
      } else {
        setState(() => _refreshing = false);
      }
    } finally {
      _refreshInFlight = false;
      if (_refreshAgain && mounted) {
        _refreshAgain = false;
        unawaited(_load(silent: _hasLoadedOnce));
      }
    }
  }

  void _startAutoRefresh({bool immediate = false}) {
    if (!_foreground || !_visible || !_hasLoadedOnce) return;
    _refreshTimer?.cancel();
    if (immediate) unawaited(_load(silent: true));
    _refreshTimer = Timer(widget.refreshInterval, () {
      unawaited(_load(silent: true));
      _startAutoRefresh();
    });
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _refreshInFlight || !_hasMore) return;
    final cursor = _nextCursor;
    if (cursor == null) return;
    final generation = ++_requestGeneration;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.service.getMyTeamConversations(
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

  void _openConversation(TeamConversationSummary c) {
    _routeCovered = true;
    _stopAutoRefresh();
    context
        .push(
          '/messages/conversation/${c.id}',
          extra: {
            'teamId': c.teamId,
            'teamName': c.teamName,
            'otherPartyName': c.isLeaderView ? c.memberName : null,
            'currentUserRole': c.currentUserRole,
          },
        )
        .then((_) {
          if (mounted) {
            _routeCovered = false;
            _refreshNow();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
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
      );
    }

    final isLeaderAnywhere =
        _items.any((c) => c.isLeaderView) || _isLeaderOfAnyTeam;

    Widget content;
    if (_items.isEmpty) {
      content = LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ZadEmptyState(
                icon: Icons.forum_outlined,
                title: isLeaderAnywhere ? null : 'لا توجد محادثات حتى الآن',
                message: isLeaderAnywhere
                    ? 'لا توجد رسائل من أعضاء الفريق'
                    : 'يمكنك مراسلة قائد فريقك من صفحة الفريق',
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
          return _ConversationCard(
            item: item,
            selecting: _selectedIds.isNotEmpty,
            selected: _selectedIds.contains(item.id),
            onSelect: () => _toggle(item.id),
            onTap: _selectedIds.isNotEmpty
                ? () => _toggle(item.id)
                : () => _openConversation(item),
          );
        },
      );
    }

    return Column(
      children: [
        if (_selectedIds.isNotEmpty)
          Row(
            children: [
              Text('تم تحديد ${_selectedIds.length}'),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _selectedIds.clear()),
                child: const Text('إلغاء التحديد'),
              ),
              IconButton(
                onPressed: _deleteSelected,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          )
        else
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: IconButton(
              onPressed: _items.isEmpty
                  ? null
                  : () => setState(
                      () => _selectedIds.addAll(_items.map((e) => e.id)),
                    ),
              icon: const Icon(Icons.checklist),
              tooltip: 'تحديد',
            ),
          ),
        if (_refreshing) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(onRefresh: _load, child: content),
        ),
      ],
    );
  }
}

class _ConversationCard extends StatelessWidget {
  final TeamConversationSummary item;
  final VoidCallback onTap;
  final bool selecting;
  final bool selected;
  final VoidCallback onSelect;

  const _ConversationCard({
    required this.item,
    required this.onTap,
    required this.selecting,
    required this.selected,
    required this.onSelect,
  });

  static String _formatWhen(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return ZadCard(
      margin: const EdgeInsets.only(bottom: ZadTokens.s3),
      highlighted: item.hasUnread,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ZadTokens.s3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selecting)
                Checkbox(value: selected, onChanged: (_) => onSelect()),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.isLeaderView
                                ? item.displayName
                                : item.teamName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: item.hasUnread
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (item.hasUnread)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: ZadTokens.danger,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              item.unreadCount > 99
                                  ? '99+'
                                  : '${item.unreadCount}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.isLeaderView ? item.teamName : item.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: ZadTokens.textMuted,
                      ),
                    ),
                    if (item.latestPreviewText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.latestPreviewText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: ZadTokens.text),
                      ),
                    ],
                    if (item.latestMessageAt != null) ...[
                      const SizedBox(height: ZadTokens.s1),
                      Text(
                        ltrFragment(_formatWhen(item.latestMessageAt!)),
                        style: const TextStyle(
                          fontSize: 11,
                          color: ZadTokens.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
