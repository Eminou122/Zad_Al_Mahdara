import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/routing/route_observer.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/zad_badge.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_confirm.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_section_header.dart';
import '../../../services/auth_service.dart';
import '../data/team_service.dart';
import '../data/team_turn_service.dart';
import '../domain/team_models.dart';
import '../domain/team_turn_models.dart';

class TeamDetailScreen extends StatefulWidget {
  final AuthService authService;
  final String teamId;
  const TeamDetailScreen({
    super.key,
    required this.authService,
    required this.teamId,
  });

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> with RouteAware {
  late final TeamService _svc;
  late final TeamTurnService _turnSvc;
  TeamDetail? _detail;
  TeamTurnState? _turnState;
  bool _loading = true;
  bool _turnLoading = false;
  bool _routeSubscribed = false;
  String? _error;
  final Set<String> _busyMembers = {};

  @override
  void initState() {
    super.initState();
    _svc = TeamService(widget.authService);
    _turnSvc = TeamTurnService(widget.authService);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route != null) {
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void didPopNext() {
    _load();
  }

  @override
  void dispose() {
    if (_routeSubscribed) appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _detail = await _svc.getTeamDetail(widget.teamId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userErrorText(e);
          _loading = false;
        });
      }
      return;
    }
    try {
      _turnState = await _turnSvc.getTurnState(widget.teamId);
    } catch (_) {} // turn state is non-fatal; card shows empty
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _refreshTurnState() async {
    try {
      final turnState = await _turnSvc.getTurnState(widget.teamId);
      if (mounted) setState(() => _turnState = turnState);
    } catch (_) {}
  }

  void _setMemberBusy(String memberId, bool busy) {
    setState(() {
      if (busy) {
        _busyMembers.add(memberId);
      } else {
        _busyMembers.remove(memberId);
      }
    });
  }

  Future<void> _applyMemberUpdate(
    TeamMember member,
    Future<TeamDetail> Function() action,
  ) async {
    _setMemberBusy(member.memberId, true);
    try {
      final detail = await action();
      if (mounted) {
        setState(() {
          _detail = detail;
          _busyMembers.remove(member.memberId);
        });
        await _refreshTurnState();
      }
    } catch (e) {
      if (mounted) {
        _setMemberBusy(member.memberId, false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  Future<void> _deactivate(TeamMember m) async {
    final ok = await zadConfirm(
      context,
      title: 'تعطيل العضو',
      body: 'سيبقى العضو ظاهراً في الفريق كغير نشط، ولن يدخل في الأدوار القادمة.',
      confirmLabel: 'تعطيل',
    );
    if (!ok) return;
    await _applyMemberUpdate(
      m,
      () => _svc.deactivateTeamMember(
        teamId: widget.teamId,
        memberId: m.memberId,
      ),
    );
  }

  Future<void> _remove(TeamMember m) async {
    final ok = await zadConfirm(
      context,
      title: 'إزالة العضو',
      body: 'سيختفي العضو من قائمة الفريق، مع بقاء السجل القديم محفوظاً.',
      confirmLabel: 'إزالة',
    );
    if (!ok) return;
    await _applyMemberUpdate(
      m,
      () => _svc.removeTeamMember(teamId: widget.teamId, memberId: m.memberId),
    );
  }

  Future<void> _reactivate(TeamMember m) async {
    final ok = await zadConfirm(
      context,
      title: 'تفعيل العضو',
      body: 'سيعود العضو إلى الأدوار القادمة في الفريق.',
      confirmLabel: 'تفعيل',
    );
    if (!ok) return;
    await _applyMemberUpdate(
      m,
      () => _svc.reactivateTeamMember(
        teamId: widget.teamId,
        memberId: m.memberId,
      ),
    );
  }

  Future<void> _startTurn() async {
    setState(() => _turnLoading = true);
    try {
      final ts = await _turnSvc.ensureTodayTurn(widget.teamId);
      if (mounted) {
        setState(() {
          _turnState = ts;
          _turnLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _turnLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  Future<void> _completeTurn(String turnId) async {
    setState(() => _turnLoading = true);
    try {
      final ts = await _turnSvc.completeTurn(turnId);
      if (mounted) {
        setState(() {
          _turnState = ts;
          _turnLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _turnLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('الفريق')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(ZadTokens.s4),
            child: ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
          ),
        ),
      );
    }
    final d = _detail!;
    final team = d.team;
    return Scaffold(
      appBar: AppBar(title: Text(team.name)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side =
                ((constraints.maxWidth - ZadTokens.contentMaxWidth) / 2)
                    .clamp(ZadTokens.s4, double.infinity);
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: side,
                  vertical: ZadTokens.s4,
                ),
                children: [
                  ZadCard(
                    highlighted: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: ZadTokens.s2,
                          runSpacing: ZadTokens.s1,
                          children: [
                            ZadBadge(
                              teamTypeLabels[team.teamType] ?? team.teamType,
                              gold: true,
                            ),
                            ZadBadge(
                              teamStatusLabels[team.status] ?? team.status,
                            ),
                            ZadBadge(team.isPublic ? 'عام' : 'خاص'),
                          ],
                        ),
                        const SizedBox(height: ZadTokens.s3),
                        const Divider(height: 1),
                        const SizedBox(height: ZadTokens.s3),
                        _InfoRow('القائد', team.leaderName),
                        _InfoRow(
                          'الأعضاء',
                          '${team.memberCount} '
                          '(نشط ${team.activeMemberCount} · '
                          'غير نشط ${team.inactiveMemberCount})',
                        ),
                        if (team.note != null) _InfoRow('ملاحظة', team.note!),
                      ],
                    ),
                  ),
                  const SizedBox(height: ZadTokens.s4),
                  if (d.canEdit)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.edit),
                            label: const Text('تعديل'),
                            onPressed: () => context.push(
                              '/teams/${widget.teamId}/edit',
                              extra: team,
                            ),
                          ),
                        ),
                        const SizedBox(width: ZadTokens.s2),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.person_add),
                            label: const Text('إضافة عضو'),
                            onPressed: () => context
                                .push('/teams/${widget.teamId}/add-member'),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: ZadTokens.s4),
                  _TurnCard(
                    state: _turnState,
                    loading: _turnLoading,
                    isMember: d.isMember,
                    onStart: _startTurn,
                    onComplete: _completeTurn,
                  ),
                  if (d.isMember && d.members.isNotEmpty) ...[
                    const ZadSectionHeader('الأعضاء'),
                    ...d.members.asMap().entries.map(
                      (entry) => _MemberTile(
                        displayPosition: entry.key + 1,
                        member: entry.value,
                        canManage: d.canEdit,
                        busy: _busyMembers.contains(entry.value.memberId),
                        onDeactivate: () => _deactivate(entry.value),
                        onReactivate: () => _reactivate(entry.value),
                        onRemove: () => _remove(entry.value),
                      ),
                    ),
                  ] else if (!d.isMember)
                    const Padding(
                      padding: EdgeInsets.only(top: ZadTokens.s2),
                      child: Text(
                        'انضم للفريق لرؤية الأعضاء',
                        style: TextStyle(color: ZadTokens.textMuted),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TurnCard extends StatelessWidget {
  final TeamTurnState? state;
  final bool loading;
  final bool isMember;
  final VoidCallback onStart;
  final void Function(String) onComplete;

  const _TurnCard({
    required this.state,
    required this.loading,
    required this.isMember,
    required this.onStart,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    return ZadCard(
      margin: const EdgeInsets.only(bottom: ZadTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('دور اليوم', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: ZadTokens.s1),
          const Text(
            'هنا تعرف من عليه الدور اليوم ومن بعده.',
            style: TextStyle(color: ZadTokens.textMuted, fontSize: 13),
          ),
          const Divider(height: 20),
          if (!isMember)
            const Text(
              'تفاصيل الأدوار تظهر لأعضاء الفريق فقط.',
              style: TextStyle(color: ZadTokens.textMuted),
            )
          else if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(ZadTokens.s2),
                child: CircularProgressIndicator(),
              ),
            )
          else if (state == null)
            const Text(
              'لم تتوفر بيانات الأدوار حالياً',
              style: TextStyle(color: ZadTokens.textMuted),
            )
          else
            _body(),
        ],
      ),
    );
  }

  Widget _body() {
    final s = state!;
    final today = s.todayTurn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (today == null) ...[
          const Text(
            'لا يوجد دور لهذا اليوم.',
            style: TextStyle(color: ZadTokens.textMuted),
          ),
          if (s.canManageTurns) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onStart,
                child: const Text('بدء دور اليوم'),
              ),
            ),
          ],
        ] else ...[
          _InfoRow('المسؤول اليوم', today.displayName),
          if (today.status == 'pending' && s.canManageTurns) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => onComplete(today.id),
                child: const Text('تم إنجاز الدور'),
              ),
            ),
          ],
        ],
        if (s.nextMember != null &&
            (today == null ||
                today.status == 'completed' ||
                today.memberId != s.nextMember!.memberId)) ...[
          const SizedBox(height: ZadTokens.s2),
          _InfoRow('التالي', s.nextMember!.displayName),
        ] else if (s.nextMember == null) ...[
          const SizedBox(height: ZadTokens.s2),
          const Text(
            'لا يوجد أعضاء نشطون للأدوار حالياً',
            style: TextStyle(color: ZadTokens.textMuted),
          ),
        ],
        if (s.lastCompletedTurn != null) ...[
          const SizedBox(height: ZadTokens.s2),
          _InfoRow('آخر دور مكتمل', s.lastCompletedTurn!.displayName),
        ],
        if (s.history.isNotEmpty) ...[
          const SizedBox(height: ZadTokens.s3),
          const Text(
            'آخر الأدوار',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: ZadTokens.s1),
          ...s.history
              .take(5)
              .map(
                (h) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Text(
                        h.turnDate,
                        style: const TextStyle(
                          color: ZadTokens.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: ZadTokens.s2),
                      Expanded(
                        child: Text(
                          h.displayName,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        h.status == 'completed' ? '✓' : '…',
                        style: TextStyle(
                          color: h.status == 'completed'
                              ? ZadTokens.primary
                              : ZadTokens.warning,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: ZadTokens.s2),
    child: Row(
      children: [
        Text('$label: ', style: const TextStyle(color: ZadTokens.textMuted)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

class _MemberTile extends StatelessWidget {
  final int displayPosition;
  final TeamMember member;
  final bool canManage;
  final bool busy;
  final VoidCallback onDeactivate;
  final VoidCallback onReactivate;
  final VoidCallback onRemove;
  const _MemberTile({
    required this.displayPosition,
    required this.member,
    required this.canManage,
    required this.busy,
    required this.onDeactivate,
    required this.onReactivate,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isLeader = member.role == 'leader';
    final roleLabel = isLeader ? 'قائد' : 'عضو';
    final showActions = canManage && !isLeader;
    final parts = [
      if (!member.hasAccount) 'بدون حساب',
      if (member.phoneMasked != null) member.phoneMasked!,
      member.isActive ? roleLabel : '$roleLabel · غير نشط',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: ZadTokens.s2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: ZadTokens.s3),
        leading: CircleAvatar(
          backgroundColor:
              member.isActive ? ZadTokens.primary : ZadTokens.textMuted,
          child: Text(
            '$displayPosition',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(member.displayName),
        subtitle: Text(
          parts.join(' · '),
          style: member.isActive
              ? null
              : const TextStyle(color: ZadTokens.textMuted),
        ),
        trailing: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : !showActions
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (member.isActive)
                    IconButton(
                      tooltip: 'تعطيل',
                      icon: const Icon(
                        Icons.pause_circle_outline,
                        color: ZadTokens.warning,
                      ),
                      onPressed: onDeactivate,
                    )
                  else
                    IconButton(
                      tooltip: 'تفعيل',
                      icon: const Icon(
                        Icons.play_circle_outline,
                        color: ZadTokens.primary,
                      ),
                      onPressed: onReactivate,
                    ),
                  IconButton(
                    tooltip: 'إزالة',
                    icon: const Icon(
                      Icons.person_remove_outlined,
                      color: ZadTokens.danger,
                    ),
                    onPressed: onRemove,
                  ),
                ],
              ),
      ),
    );
  }
}
