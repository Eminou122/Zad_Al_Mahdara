import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../features/messaging/data/team_messaging_service.dart';
import '../../../features/messaging/domain/team_messaging_models.dart';
import '../../../features/messaging/presentation/message_team_leader_dialog.dart';
import '../../../features/teams/domain/team_models.dart';
import '../../../services/auth_service.dart';
import '../data/student_directory_service.dart';
import '../domain/student_directory_models.dart';

class StudentDirectoryScreen extends StatefulWidget {
  final AuthService authService;
  final StudentDirectoryService? service;
  final TeamMessagingService? messagingService;
  final Duration searchDebounce;

  const StudentDirectoryScreen({
    super.key,
    required this.authService,
    this.service,
    this.messagingService,
    this.searchDebounce = const Duration(milliseconds: 330),
  });

  @override
  State<StudentDirectoryScreen> createState() => _StudentDirectoryScreenState();
}

class _StudentDirectoryScreenState extends State<StudentDirectoryScreen> {
  late final StudentDirectoryService _service;
  late final TeamMessagingService _messagingService;
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _items = <StudentDirectoryEntry>[];
  final _ids = <String>{};

  Timer? _debounce;
  StudentDirectoryCursor? _nextCursor;
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  String? _moreError;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? StudentDirectoryService(widget.authService);
    _messagingService =
        widget.messagingService ?? TeamMessagingService(widget.authService);
    _scrollCtrl.addListener(_maybeLoadMore);
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(widget.searchDebounce, () {
      unawaited(_load(reset: true));
    });
  }

  Future<void> _load({required bool reset}) async {
    final id = ++_requestId;
    if (reset) {
      setState(() {
        _loading = _items.isEmpty;
        _refreshing = _items.isNotEmpty;
        _error = null;
        _moreError = null;
      });
    } else {
      if (_loadingMore || !_hasMore || _nextCursor == null) return;
      setState(() {
        _loadingMore = true;
        _moreError = null;
      });
    }

    try {
      final page = await _service.getStudentDirectory(
        query: _searchCtrl.text,
        after: reset ? null : _nextCursor,
      );
      if (!mounted || id != _requestId) return;
      setState(() {
        if (reset) {
          _items.clear();
          _ids.clear();
        }
        for (final item in page.items) {
          if (_ids.add(item.profileId)) _items.add(item);
        }
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        if (reset && _items.isEmpty) _error = userErrorText(e);
        if (!reset) _moreError = userErrorText(e);
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _refresh() => _load(reset: true);

  void _maybeLoadMore() {
    if (!_scrollCtrl.hasClients || !_hasMore || _loadingMore) return;
    final position = _scrollCtrl.position;
    if (position.pixels >= position.maxScrollExtent - 280) {
      unawaited(_load(reset: false));
    }
  }

  Future<void> _message(
    StudentDirectoryEntry entry,
    DirectoryContactTarget target,
  ) async {
    final sent = await showDialog<SentTeamMessage>(
      context: context,
      builder: (_) => MessageTeamLeaderDialog(
        service: _messagingService,
        teamId: target.teamId,
      ),
    );
    if (!mounted || sent == null) return;
    context.push(
      '/messages/conversation/${sent.conversation.id}',
      extra: {
        'teamId': sent.conversation.teamId,
        'teamName': target.teamName,
        'otherPartyName': entry.displayName,
        'currentUserRole': 'member',
      },
    );
  }

  Future<void> _chooseMessageTarget(StudentDirectoryEntry entry) async {
    final targets = entry.contactTargets;
    if (targets.isEmpty) return;
    if (targets.length == 1) {
      await _message(entry, targets.first);
      return;
    }
    final selected = await showModalBottomSheet<DirectoryContactTarget>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(ZadTokens.s4),
          children: [
            Text('اختر الفريق', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: ZadTokens.s2),
            for (final target in targets)
              ListTile(
                title: Text(target.teamName),
                subtitle: Text(
                  teamTypeLabels[target.teamType] ?? target.teamType,
                ),
                onTap: () => Navigator.pop(context, target),
              ),
          ],
        ),
      ),
    );
    if (selected != null) await _message(entry, selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دليل الطلاب')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ZadTokens.contentMaxWidth,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(ZadTokens.s4),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'ابحث عن طالب',
                    ),
                  ),
                ),
                if (_refreshing) const LinearProgressIndicator(minHeight: 2),
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) {
      return _ScrollableState(
        onRefresh: _refresh,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('تعذر تحميل دليل الطلاب'),
            const SizedBox(height: ZadTokens.s3),
            OutlinedButton.icon(
              onPressed: () => unawaited(_load(reset: true)),
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return _ScrollableState(
        onRefresh: _refresh,
        child: const Text('لا توجد نتائج'),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          ZadTokens.s4,
          0,
          ZadTokens.s4,
          ZadTokens.s4,
        ),
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index == _items.length) return _loadMoreFooter();
          return Padding(
            padding: const EdgeInsets.only(bottom: ZadTokens.s3),
            child: _StudentCard(
              entry: _items[index],
              onMessage: () => unawaited(_chooseMessageTarget(_items[index])),
            ),
          );
        },
      ),
    );
  }

  Widget _loadMoreFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(ZadTokens.s3),
        child: Center(child: Text('جارٍ تحميل المزيد...')),
      );
    }
    if (_moreError != null) {
      return Center(
        child: OutlinedButton(
          onPressed: () => unawaited(_load(reset: false)),
          child: const Text('إعادة المحاولة'),
        ),
      );
    }
    if (_hasMore) return const SizedBox(height: ZadTokens.s5);
    return const SizedBox.shrink();
  }
}

class _ScrollableState extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const _ScrollableState({required this.child, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(ZadTokens.s4),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  final StudentDirectoryEntry entry;
  final VoidCallback onMessage;

  const _StudentCard({required this.entry, required this.onMessage});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ZadTokens.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.displayName,
              style: Theme.of(context).textTheme.titleMedium,
              softWrap: true,
            ),
            const SizedBox(height: ZadTokens.s3),
            const Text(
              'الفرق العامة',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: ZadTokens.textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: ZadTokens.s2),
            if (entry.publicTeams.isEmpty)
              const Text(
                'لا توجد فرق عامة',
                style: TextStyle(color: ZadTokens.textMuted),
              )
            else
              Wrap(
                spacing: ZadTokens.s2,
                runSpacing: ZadTokens.s2,
                children: [
                  for (final team in entry.publicTeams)
                    Chip(
                      label: Text(
                        [
                          team.teamName,
                          teamTypeLabels[team.teamType] ?? team.teamType,
                          if (team.isCurrentLeader) 'قائد الفريق',
                        ].where((v) => v.isNotEmpty).join(' · '),
                      ),
                    ),
                ],
              ),
            if (entry.contactTargets.isNotEmpty) ...[
              const SizedBox(height: ZadTokens.s3),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.icon(
                  onPressed: onMessage,
                  icon: const Icon(Icons.message_outlined),
                  label: const Text('مراسلة قائد الفريق'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
