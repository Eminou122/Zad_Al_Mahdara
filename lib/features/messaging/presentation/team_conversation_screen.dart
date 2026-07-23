import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import '../../../core/refresh/app_refresh_coordinator.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/ltr_fragment.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_messaging_badge_scope.dart';
import '../../../core/widgets/zad_permanent_delete_confirm.dart';
import '../../../services/auth_service.dart';
import '../data/team_messaging_service.dart';
import '../domain/team_messaging_models.dart';

const int _pageSize = 50;
const int _maxBodyLength = 2000;

class TeamConversationScreen extends StatefulWidget {
  final AuthService authService;
  final String conversationId;

  /// Best-effort display/authorization hints carried from wherever the
  /// caller navigated from (conversation list row, a just-sent first
  /// message, or a notification payload). None are required — every one
  /// is re-derived defensively when missing, and the composer simply
  /// disables itself if the role can never be resolved (section 11).
  final String? teamId;
  final String? teamName;
  final String? otherPartyName;
  final String? currentUserRole;

  final TeamMessagingService? service;
  final Duration syncInterval;
  final Duration relaxedSyncInterval;
  final Duration typingDebounce;
  final Duration typingRefreshInterval;
  final Duration typingIdleTimeout;
  final Duration onlineWindow;
  final DateTime Function() currentTime;

  const TeamConversationScreen({
    super.key,
    required this.authService,
    required this.conversationId,
    this.teamId,
    this.teamName,
    this.otherPartyName,
    this.currentUserRole,
    this.service,
    this.syncInterval = const Duration(seconds: 2),
    this.relaxedSyncInterval = const Duration(seconds: 5),
    this.typingDebounce = const Duration(milliseconds: 400),
    this.typingRefreshInterval = const Duration(seconds: 3),
    this.typingIdleTimeout = const Duration(seconds: 3),
    this.onlineWindow = const Duration(seconds: 60),
    DateTime Function()? currentTime,
  }) : currentTime = currentTime ?? DateTime.now;

  @override
  State<TeamConversationScreen> createState() => _TeamConversationScreenState();
}

class _TeamConversationScreenState extends State<TeamConversationScreen>
    with WidgetsBindingObserver {
  late final TeamMessagingService _svc;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _composerCtrl = TextEditingController();

  List<TeamMessage> _messages = [];
  bool _hasMore = false;
  TeamMessageCursor? _nextCursor;

  bool _hasLoadedOnce = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _sending = false;
  String? _error;
  String? _composerError;
  bool _syncing = false;
  int _emptySyncs = 0;
  int _syncFailures = 0;
  bool _syncErrorVisible = false;
  bool _showNewMessages = false;
  bool _foreground = true;

  Timer? _syncTimer;
  Timer? _liveStateTimer;
  Timer? _typingDebounceTimer;
  Timer? _typingIdleTimer;
  DateTime? _lastTypingSentAt;
  bool _typingActive = false;

  String? _teamId;
  String? _teamName;
  String? _otherPartyName;
  String? _role;
  bool _roleTrusted = false;
  TeamMessageCursor? _newestCursor;
  ConversationLiveState? _liveState;
  final Set<String> _selectedMessageIds = {};

  String? get _myProfileId => widget.authService.profile?.id;
  String? get _myDisplayName => widget.authService.profile?.displayName;

  bool get _canCompose =>
      _roleTrusted &&
      (_role == 'leader' || (_role == 'member' && _teamId != null));

  void _toggleMessage(String id) => setState(
    () => _selectedMessageIds.contains(id)
        ? _selectedMessageIds.remove(id)
        : _selectedMessageIds.add(id),
  );

  Future<void> _deleteSelectedMessages() async {
    final ids = _selectedMessageIds.toList();
    if (ids.isEmpty ||
        !await zadPermanentDeleteConfirm(context, count: ids.length)) {
      return;
    }
    try {
      await _svc.deleteMessages(widget.conversationId, ids);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = _messages
            .where((message) => !ids.contains(message.id))
            .toList();
        _selectedMessageIds.clear();
      });
      AppRefreshCoordinator.instance.invalidateMany({
        AppRefreshScope.messages,
        AppRefreshScope.messagingBadge,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? TeamMessagingService(widget.authService);
    _teamId = widget.teamId;
    _teamName = widget.teamName;
    _otherPartyName = widget.otherPartyName == _myDisplayName
        ? null
        : widget.otherPartyName;
    _role = widget.currentUserRole;
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _composerCtrl.addListener(_onComposerChanged);
    _load();
  }

  @override
  void dispose() {
    AppRefreshCoordinator.instance.invalidateMany({
      AppRefreshScope.messages,
      AppRefreshScope.messagingBadge,
    });
    _stopSync();
    _stopLiveStateTimer();
    _clearTypingBestEffort();
    _typingDebounceTimer?.cancel();
    _typingIdleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _composerCtrl.removeListener(_onComposerChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _composerCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      _scheduleSync(immediate: true);
      _scheduleLiveStateTimer();
    } else {
      _stopSync();
      _stopLiveStateTimer();
      _clearTypingBestEffort();
    }
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  List<TeamMessage> _dedupe(List<TeamMessage> items) {
    final seen = <String>{};
    final out = <TeamMessage>[];
    for (final it in items) {
      if (seen.add(it.id)) out.add(it);
    }
    return out;
  }

  TeamMessageCursor? _cursorFromNewest(List<TeamMessage> items) {
    if (items.isEmpty) return null;
    final sorted = [...items]..sort(_newestFirst);
    final newest = sorted.first;
    return TeamMessageCursor(createdAt: newest.createdAt, id: newest.id);
  }

  int _newestFirst(TeamMessage a, TeamMessage b) {
    final byDate = b.createdAt.compareTo(a.createdAt);
    if (byDate != 0) return byDate;
    return b.id.compareTo(a.id);
  }

  bool get _nearNewest {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels <= 80;
  }

  DateTime get _now => widget.currentTime();

  /// Best-effort context hydration for the deep-link case (opened from a
  /// notification, so no list-row/send-result hints exist): reuses
  /// get_my_team_conversations (already one of the nine RPCs) to find this
  /// exact conversation's team/name/role. Silently ignored on failure —
  /// message loading below is the path with real error handling.
  Future<void> _hydrateContextIfNeeded() async {
    if (_roleTrusted && _teamId != null && _teamName != null) return;
    try {
      final page = await _svc.getMyTeamConversations(limit: 50);
      TeamConversationSummary? match;
      for (final c in page.items) {
        if (c.id == widget.conversationId) {
          match = c;
          break;
        }
      }
      if (match == null) return;
      _teamId ??= match.teamId;
      _teamName ??= match.teamName;
      if (match.isLeaderView && match.memberName != _myDisplayName) {
        _otherPartyName ??= match.memberName;
      }
      _role = match.currentUserRole;
      _roleTrusted = true;
    } catch (_) {
      // Best-effort only.
    }
  }

  void _deriveRoleFromMessages(List<TeamMessage> items) {
    if (_roleTrusted) return;
    final myId = _myProfileId;
    if (myId == null) return;
    for (final m in items) {
      if (m.senderProfileId == myId) {
        _role = m.senderRole;
        _roleTrusted = true;
        return;
      }
    }
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
      await _hydrateContextIfNeeded();
      final page = await _svc.getTeamConversationMessages(
        conversationId: widget.conversationId,
        limit: _pageSize,
      );
      if (!mounted) return;
      _deriveRoleFromMessages(page.items);
      setState(() {
        _messages = _dedupe(page.items)..sort(_newestFirst);
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _newestCursor = _cursorFromNewest(_messages);
        _hasLoadedOnce = true;
        _loading = false;
        _refreshing = false;
      });
      unawaited(_markReadAndRefreshBadge());
      _scheduleSync(immediate: true);
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

  Future<void> _markReadAndRefreshBadge() async {
    try {
      await _svc.markConversationRead(widget.conversationId);
    } catch (_) {
      // Best-effort; unread state simply stays as-is on failure.
    }
    if (!mounted) return;
    ZadMessagingBadgeScope.maybeOf(context)?.refresh();
    AppRefreshCoordinator.instance.invalidateMany({
      AppRefreshScope.messages,
      AppRefreshScope.messagingBadge,
    });
  }

  void _scheduleSync({bool immediate = false}) {
    if (!_foreground || !_hasLoadedOnce || _error != null) return;
    _syncTimer?.cancel();
    final interval = _emptySyncs >= 3
        ? widget.relaxedSyncInterval
        : widget.syncInterval;
    if (immediate) {
      unawaited(_syncNow());
    }
    _syncTimer = Timer(interval, () {
      unawaited(_syncNow());
      _scheduleSync();
    });
  }

  void _stopSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  void _stopLiveStateTimer() {
    _liveStateTimer?.cancel();
    _liveStateTimer = null;
  }

  void _scheduleLiveStateTimer() {
    _stopLiveStateTimer();
    final live = _liveState;
    if (!_foreground || live == null) return;

    final now = _now.toUtc();
    final wakeups = <DateTime>[];
    final seen = live.lastActiveAt?.toUtc();
    if (seen != null) {
      wakeups.add(seen.add(widget.onlineWindow));
    }
    final typingUntil = live.typingUntil?.toUtc();
    if (typingUntil != null && live.isTyping) {
      wakeups.add(typingUntil);
    }
    wakeups.removeWhere((t) => !t.isAfter(now));
    if (wakeups.isEmpty) return;
    wakeups.sort();
    _liveStateTimer = Timer(wakeups.first.difference(now), () {
      if (mounted) setState(() {});
      _scheduleLiveStateTimer();
    });
  }

  void _applyLiveState(ConversationLiveState? live) {
    if (live == null) return;
    final myId = _myProfileId;
    if (myId != null && live.otherProfileId == myId) {
      _liveState = ConversationLiveState.unknown;
      if (_otherPartyName == _myDisplayName) _otherPartyName = null;
      return;
    }
    _liveState = live;
    final name = live.displayName;
    if (name != null && name != _myDisplayName) {
      _otherPartyName = name;
    }
  }

  Future<void> _syncNow() async {
    if (_syncing || !_foreground || !_hasLoadedOnce) return;
    _syncing = true;
    try {
      final updates = await _svc.getConversationUpdates(
        conversationId: widget.conversationId,
        after: _newestCursor,
        limit: _pageSize,
      );
      if (!mounted) return;
      final wasNearNewest = _nearNewest;
      final existing = _messages.map((m) => m.id).toSet();
      final incoming = updates.messages
          .where((m) => existing.add(m.id))
          .toList(growable: false);
      setState(() {
        if (incoming.isNotEmpty) {
          _messages = _dedupe([...incoming, ..._messages])..sort(_newestFirst);
          _emptySyncs = 0;
          _showNewMessages = !wasNearNewest;
        } else {
          _emptySyncs++;
        }
        _newestCursor = updates.newestCursor ?? _cursorFromNewest(_messages);
        _applyLiveState(updates.liveState);
        _syncFailures = 0;
        _syncErrorVisible = false;
      });
      _scheduleLiveStateTimer();
      if (incoming.isNotEmpty) {
        unawaited(_markReadAndRefreshBadge());
        if (wasNearNewest) _scrollToNewest();
      }
    } catch (e) {
      if (!mounted) return;
      final text = userErrorText(e);
      final denied = text.contains('صلاحية') || text.contains('لم يعد');
      setState(() {
        _syncFailures++;
        _syncErrorVisible = _syncFailures >= 3;
        if (denied) _error = text;
      });
      if (denied) _stopSync();
    } finally {
      _syncing = false;
    }
  }

  void _scrollToNewest() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final cursor = _nextCursor;
    if (cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _svc.getTeamConversationMessages(
        conversationId: widget.conversationId,
        limit: _pageSize,
        before: cursor,
      );
      if (!mounted) return;
      final existingIds = _messages.map((e) => e.id).toSet();
      setState(() {
        _messages = [
          ..._messages,
          ...page.items.where((it) => !existingIds.contains(it.id)),
        ];
        _messages.sort(_newestFirst);
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

  Future<void> _send() async {
    if (_sending || !_canCompose) return;
    final text = _composerCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _composerError = 'اكتب رسالة أولاً');
      return;
    }
    if (text.length > _maxBodyLength) {
      setState(() => _composerError = 'الرسالة طويلة جداً');
      return;
    }
    setState(() {
      _sending = true;
      _composerError = null;
    });
    try {
      final result = _role == 'leader'
          ? await _svc.replyToTeamConversation(
              conversationId: widget.conversationId,
              body: text,
            )
          : await _svc.sendMessageToTeamLeader(teamId: _teamId!, body: text);
      if (!mounted) return;
      setState(() {
        _messages = _dedupe([result.message, ..._messages])..sort(_newestFirst);
        _newestCursor = _cursorFromNewest(_messages);
        _composerCtrl.clear();
        _sending = false;
        _showNewMessages = false;
        _emptySyncs = 0;
      });
      _clearTypingBestEffort();
      _scrollToNewest();
      ZadMessagingBadgeScope.maybeOf(context)?.refresh();
      AppRefreshCoordinator.instance.invalidateMany({
        AppRefreshScope.messages,
        AppRefreshScope.messagingBadge,
      });
      _scheduleSync(immediate: true);
    } catch (e) {
      if (!mounted) return;
      // Preserve the typed draft on failure (section 10).
      setState(() {
        _sending = false;
        _composerError = userErrorText(e);
      });
    }
  }

  void _onComposerChanged() {
    if (!_canCompose) return;
    final hasText = _composerCtrl.text.trim().isNotEmpty;
    _typingDebounceTimer?.cancel();
    _typingIdleTimer?.cancel();
    if (!hasText) {
      _clearTypingBestEffort();
      return;
    }
    final now = _now;
    final shouldRefresh =
        !_typingActive ||
        _lastTypingSentAt == null ||
        now.difference(_lastTypingSentAt!) >= widget.typingRefreshInterval;
    if (shouldRefresh) {
      _typingDebounceTimer = Timer(widget.typingDebounce, () {
        unawaited(_sendTyping(true));
      });
    }
    _typingIdleTimer = Timer(widget.typingIdleTimeout, _clearTypingBestEffort);
  }

  Future<void> _sendTyping(bool isTyping) async {
    try {
      await _svc.setConversationTyping(
        widget.conversationId,
        isTyping: isTyping,
      );
      _typingActive = isTyping;
      _lastTypingSentAt = isTyping ? _now : null;
    } catch (_) {
      // Draft text stays local; typing is best-effort comfort UI.
    }
  }

  void _clearTypingBestEffort() {
    _typingDebounceTimer?.cancel();
    _typingIdleTimer?.cancel();
    if (!_typingActive) return;
    _typingActive = false;
    _lastTypingSentAt = null;
    unawaited(_sendTyping(false));
  }

  @override
  Widget build(BuildContext context) {
    final liveState = _liveState;
    final now = _now;
    final isTyping = liveState?.typingIsActiveAt(now) ?? false;
    final statusLabel = isTyping
        ? null
        : liveState?.statusLabelAt(now, onlineWindow: widget.onlineWindow);

    return Scaffold(
      appBar: AppBar(
        title: Text(_teamName ?? 'المحادثة', overflow: TextOverflow.ellipsis),
        actions: _selectedMessageIds.isNotEmpty
            ? [
                TextButton(
                  onPressed: () => setState(() => _selectedMessageIds.clear()),
                  child: const Text('إلغاء التحديد'),
                ),
                IconButton(
                  onPressed: _deleteSelectedMessages,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'حذف المحدد',
                ),
              ]
            : [
                IconButton(
                  onPressed: () => setState(
                    () => _selectedMessageIds.addAll(
                      _messages
                          .where((m) => m.isSentBy(_myProfileId))
                          .map((m) => m.id),
                    ),
                  ),
                  icon: const Icon(Icons.checklist),
                  tooltip: 'تحديد',
                ),
              ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight - 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_otherPartyName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    children: [
                      Text(
                        _otherPartyName!,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      if (isTyping)
                        const Text(
                          'يكتب الآن...',
                          style: TextStyle(
                            fontSize: 11,
                            color: ZadTokens.primary,
                          ),
                        )
                      else if (statusLabel != null)
                        Text(
                          statusLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            color: ZadTokens.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              if (_refreshing) const LinearProgressIndicator(minHeight: 2),
            ],
          ),
        ),
      ),
      body: SafeArea(child: _body()),
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
              ZadInfoBanner(
                'تعذر تحميل الرسائل\n$_error',
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

    return Column(
      children: [
        if (_syncErrorVisible)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZadTokens.s3),
            child: Row(
              children: [
                const Expanded(
                  child: ZadInfoBanner(
                    'تعذر تحديث الرسائل',
                    kind: ZadBannerKind.warning,
                  ),
                ),
                const SizedBox(width: ZadTokens.s2),
                OutlinedButton(
                  onPressed: () => _scheduleSync(immediate: true),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              RefreshIndicator(
                onRefresh: _load,
                child: _messages.isEmpty
                    ? LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(ZadTokens.s4),
                                    child: Text(
                                      'لا توجد رسائل بعد',
                                      style: TextStyle(
                                        color: ZadTokens.textMuted,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(ZadTokens.s3),
                        itemCount: _messages.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _messages.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: ZadTokens.s3,
                              ),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final m = _messages[index];
                          return _MessageBubble(
                            message: m,
                            isMine: m.isSentBy(_myProfileId),
                            selecting: _selectedMessageIds.isNotEmpty,
                            selected: _selectedMessageIds.contains(m.id),
                            onSelect: () => _toggleMessage(m.id),
                          );
                        },
                      ),
              ),
              if (_showNewMessages)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: ZadTokens.s2,
                  child: Center(
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        setState(() => _showNewMessages = false);
                        _scrollToNewest();
                      },
                      icon: const Icon(Icons.arrow_downward),
                      label: const Text('رسائل جديدة'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _composer(),
      ],
    );
  }

  Widget _composer() {
    return Padding(
      padding: EdgeInsets.only(
        left: ZadTokens.s3,
        right: ZadTokens.s3,
        top: ZadTokens.s2,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0
            ? ZadTokens.s2
            : ZadTokens.s3,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_composerError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: ZadTokens.s2),
                child: Text(
                  _composerError!,
                  style: const TextStyle(color: ZadTokens.danger, fontSize: 12),
                ),
              ),
            if (!_canCompose)
              const Padding(
                padding: EdgeInsets.only(bottom: ZadTokens.s2),
                child: Text(
                  'تعذر تحديد صلاحيتك في هذه المحادثة',
                  style: TextStyle(color: ZadTokens.textMuted, fontSize: 12),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _composerCtrl,
                    enabled: _canCompose && !_sending,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: _maxBodyLength,
                    decoration: const InputDecoration(
                      hintText: 'اكتب رسالتك',
                      isDense: true,
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: ZadTokens.s2),
                IconButton.filled(
                  onPressed: (_canCompose && !_sending) ? _send : null,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final TeamMessage message;
  final bool isMine;
  final bool selecting;
  final bool selected;
  final VoidCallback onSelect;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.selecting,
    required this.selected,
    required this.onSelect,
  });

  static String _formatWhen(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: isMine ? onSelect : null,
        onTap: selecting && isMine ? onSelect : null,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          margin: const EdgeInsets.symmetric(vertical: ZadTokens.s1),
          padding: const EdgeInsets.symmetric(
            horizontal: ZadTokens.s3,
            vertical: ZadTokens.s2,
          ),
          decoration: BoxDecoration(
            color: isMine
                ? ZadTokens.primary.withValues(alpha: 0.14)
                : ZadTokens.surfaceContainer,
            borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    message.senderName,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: ZadTokens.textMuted,
                    ),
                  ),
                ),
              Row(
                children: [
                  if (selecting && isMine)
                    Checkbox(value: selected, onChanged: (_) => onSelect()),
                  Expanded(child: Text(message.body, softWrap: true)),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                ltrFragment(_formatWhen(message.createdAt)),
                style: const TextStyle(
                  fontSize: 10,
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
