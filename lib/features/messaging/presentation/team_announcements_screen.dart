import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/ltr_fragment.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_empty_state.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_messaging_badge_scope.dart';
import '../../../services/auth_service.dart';
import '../data/team_messaging_service.dart';
import '../domain/team_messaging_models.dart';

const int _pageSize = 30;

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
  final bool showAppBar;

  const TeamAnnouncementsScreen({
    super.key,
    required this.authService,
    this.teamId,
    this.teamName,
    this.isLeader = false,
    this.focusAnnouncementId,
    this.service,
    this.showAppBar = true,
  });

  @override
  State<TeamAnnouncementsScreen> createState() =>
      _TeamAnnouncementsScreenState();
}

class _TeamAnnouncementsScreenState extends State<TeamAnnouncementsScreen> {
  late final TeamMessagingService _svc;
  final ScrollController _scrollController = ScrollController();

  List<TeamAnnouncement> _items = [];
  bool _hasMore = false;
  TeamAnnouncementCursor? _nextCursor;

  bool _hasLoadedOnce = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  String? _error;
  final Set<String> _markingRead = {};

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? TeamMessagingService(widget.authService);
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

  List<TeamAnnouncement> _dedupe(List<TeamAnnouncement> items) {
    final seen = <String>{};
    final out = <TeamAnnouncement>[];
    for (final it in items) {
      if (seen.add(it.id)) out.add(it);
    }
    return out;
  }

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
      final page = await _svc.getMyTeamAnnouncements(
        teamId: widget.teamId,
        limit: _pageSize,
      );
      if (!mounted) return;
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
      final page = await _svc.getMyTeamAnnouncements(
        teamId: widget.teamId,
        limit: _pageSize,
        before: cursor,
      );
      if (!mounted) return;
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _markingRead.remove(item.id));
      // Read-state is best-effort UI sugar; a failure here is silent.
    }
  }

  Future<void> _openCompose() async {
    final teamId = widget.teamId;
    if (teamId == null) return;
    final created = await context.push<bool>(
      '/teams/$teamId/announcements/new',
      extra: widget.teamName,
    );
    if (!mounted || created != true) return;
    _load();
    ZadMessagingBadgeScope.maybeOf(context)?.refresh();
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
                onPressed: _load,
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
            onTap: () => _markRead(item),
          );
        },
      );
    }

    return RefreshIndicator(onRefresh: _load, child: content);
  }
}

class _AnnouncementCard extends StatelessWidget {
  final TeamAnnouncement item;
  final bool busy;
  final bool showTeamName;
  final VoidCallback onTap;

  const _AnnouncementCard({
    required this.item,
    required this.busy,
    required this.showTeamName,
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
            ],
          ),
        ),
      ),
    );
  }
}
