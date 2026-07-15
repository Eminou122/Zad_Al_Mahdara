import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/ltr_fragment.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_messaging_badge_scope.dart';
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

  const TeamConversationScreen({
    super.key,
    required this.authService,
    required this.conversationId,
    this.teamId,
    this.teamName,
    this.otherPartyName,
    this.currentUserRole,
    this.service,
  });

  @override
  State<TeamConversationScreen> createState() => _TeamConversationScreenState();
}

class _TeamConversationScreenState extends State<TeamConversationScreen> {
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

  String? _teamId;
  String? _teamName;
  String? _otherPartyName;
  String? _role;
  bool _roleTrusted = false;

  String? get _myProfileId => widget.authService.profile?.id;

  bool get _canCompose =>
      _roleTrusted &&
      (_role == 'leader' || (_role == 'member' && _teamId != null));

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? TeamMessagingService(widget.authService);
    _teamId = widget.teamId;
    _teamName = widget.teamName;
    _otherPartyName = widget.otherPartyName;
    _role = widget.currentUserRole;
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _composerCtrl.dispose();
    super.dispose();
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
      _otherPartyName ??= match.memberName;
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
        _messages = _dedupe(page.items);
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _hasLoadedOnce = true;
        _loading = false;
        _refreshing = false;
      });
      unawaited(_markReadAndRefreshBadge());
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
        _messages = [result.message, ..._messages];
        _composerCtrl.clear();
        _sending = false;
      });
      ZadMessagingBadgeScope.maybeOf(context)?.refresh();
    } catch (e) {
      if (!mounted) return;
      // Preserve the typed draft on failure (section 10).
      setState(() {
        _sending = false;
        _composerError = userErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_teamName ?? 'المحادثة', overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight - 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_otherPartyName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _otherPartyName!,
                    style: const TextStyle(fontSize: 12.5),
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
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _messages.isEmpty
                ? LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
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
                              style: TextStyle(color: ZadTokens.textMuted),
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
                          padding: EdgeInsets.symmetric(vertical: ZadTokens.s3),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final m = _messages[index];
                      return _MessageBubble(
                        message: m,
                        isMine: m.isSentBy(_myProfileId),
                      );
                    },
                  ),
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

  const _MessageBubble({required this.message, required this.isMine});

  static String _formatWhen(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
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
            Text(message.body, softWrap: true),
            const SizedBox(height: 2),
            Text(
              ltrFragment(_formatWhen(message.createdAt)),
              style: const TextStyle(fontSize: 10, color: ZadTokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
