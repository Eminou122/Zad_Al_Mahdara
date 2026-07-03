import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/routing/route_observer.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_badge.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_confirm.dart';
import '../../../core/widgets/zad_dotted_background.dart';
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
      body:
          'سيبقى العضو ظاهراً في الفريق كغير نشط، ولن يدخل في الأدوار القادمة.',
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
      // Gold add-member FAB (Stitch team_detail); same route push as before.
      floatingActionButton: d.canEdit
          ? FloatingActionButton(
              backgroundColor: ZadTokens.gold,
              foregroundColor: ZadTokens.primaryDark,
              tooltip: 'إضافة عضو',
              onPressed: () =>
                  context.push('/teams/${widget.teamId}/add-member'),
              child: const Icon(Icons.person_add_alt_1),
            )
          : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side =
                ((constraints.maxWidth - ZadTokens.contentMaxWidth) / 2).clamp(
                  ZadTokens.s4,
                  double.infinity,
                );
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: side,
                  vertical: ZadTokens.s4,
                ),
                children: [
                  ZadAnimatedEntry(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(ZadTokens.radiusLg),
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: ZadTokens.heroGradient,
                          boxShadow: ZadTokens.cardShadow,
                        ),
                        child: ZadDottedBackground(
                          color: Colors.white12,
                          child: Stack(
                            children: [
                              const PositionedDirectional(
                                start: 12,
                                top: 8,
                                child: Icon(
                                  Icons.mosque_outlined,
                                  size: 86,
                                  color: Colors.white12,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(ZadTokens.s4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: ZadTokens.s2,
                                      runSpacing: ZadTokens.s1,
                                      children: [
                                        _HeroBadge(
                                          teamTypeLabels[team.teamType] ??
                                              team.teamType,
                                          gold: true,
                                        ),
                                        _HeroBadge(
                                          teamStatusLabels[team.status] ??
                                              team.status,
                                        ),
                                        _HeroBadge(
                                          team.isPublic ? 'عام' : 'خاص',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: ZadTokens.s4),
                                    Text(
                                      team.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(color: Colors.white),
                                    ),
                                    const SizedBox(height: ZadTokens.s1),
                                    Text(
                                      'القائد: ${team.leaderName}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: ZadTokens.s3),
                                    const Divider(
                                      height: 1,
                                      color: Colors.white24,
                                    ),
                                    const SizedBox(height: ZadTokens.s3),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.people_alt_outlined,
                                          size: 16,
                                          color: ZadTokens.gold,
                                        ),
                                        const SizedBox(width: ZadTokens.s1 + 2),
                                        Expanded(
                                          child: Text(
                                            '${team.memberCount} عضو '
                                            '(نشط ${team.activeMemberCount} · '
                                            'غير نشط ${team.inactiveMemberCount})',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (team.note != null) ...[
                                      const SizedBox(height: ZadTokens.s2),
                                      Text(
                                        'ملاحظة: ${team.note!}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12.5,
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
                    ),
                  ),
                  const SizedBox(height: ZadTokens.s4),
                  // Add-member moved to the gold FAB (Stitch); edit stays.
                  if (d.canEdit)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit),
                      label: const Text('تعديل الفريق'),
                      onPressed: () => context.push(
                        '/teams/${widget.teamId}/edit',
                        extra: team,
                      ),
                    ),
                  const SizedBox(height: ZadTokens.s4),
                  ZadAnimatedEntry(
                    delay: const Duration(milliseconds: 60),
                    child: _TurnCard(
                      state: _turnState,
                      loading: _turnLoading,
                      isMember: d.isMember,
                      onStart: _startTurn,
                      onComplete: _completeTurn,
                    ),
                  ),
                  if (d.isMember && d.members.isNotEmpty) ...[
                    const ZadSectionHeader('الأعضاء'),
                    // Light stagger on the first rows only; row-level busy
                    // state lives inside _MemberTile and is unaffected.
                    ...d.members.asMap().entries.map(
                      (entry) => ZadAnimatedEntry(
                        delay: Duration(
                          milliseconds: entry.key < 6 ? 30 * entry.key : 0,
                        ),
                        child: _MemberTile(
                          displayPosition: entry.key + 1,
                          member: entry.value,
                          canManage: d.canEdit,
                          busy: _busyMembers.contains(entry.value.memberId),
                          onDeactivate: () => _deactivate(entry.value),
                          onReactivate: () => _reactivate(entry.value),
                          onRemove: () => _remove(entry.value),
                        ),
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
          // Stitch turn-system header: gold icon + title.
          Row(
            children: [
              const Icon(Icons.autorenew, size: 18, color: ZadTokens.goldDark),
              const SizedBox(width: ZadTokens.s2),
              Text(
                'نظام النوبات اليومي',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: ZadTokens.goldDark),
              ),
            ],
          ),
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
          // Today's turn holder highlighted (Stitch-inspired tinted row).
          Container(
            padding: const EdgeInsets.all(ZadTokens.s3),
            decoration: BoxDecoration(
              color: ZadTokens.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(ZadTokens.radiusSm),
              border: Border.all(
                color: ZadTokens.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: ZadTokens.primary,
                  child: Text(
                    today.displayName.isEmpty
                        ? '؟'
                        : today.displayName.characters.first,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: ZadTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'المسؤول اليوم',
                        style: TextStyle(
                          fontSize: 12,
                          color: ZadTokens.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        today.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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

    return Container(
      margin: const EdgeInsets.only(bottom: ZadTokens.s1),
      decoration: const BoxDecoration(
        color: ZadTokens.surface,
        border: Border(bottom: BorderSide(color: ZadTokens.goldSoft)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ZadTokens.s3,
          vertical: ZadTokens.s2,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: member.isActive
                    ? ZadTokens.primary.withValues(alpha: 0.10)
                    : ZadTokens.textMuted.withValues(alpha: 0.10),
              ),
              child: Text(
                '$displayPosition',
                style: TextStyle(
                  color: member.isActive
                      ? ZadTokens.primary
                      : ZadTokens.textMuted,
                  fontWeight: FontWeight.bold,
                ),
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
                          member.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (isLeader) const ZadBadge('القائد', gold: true),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    parts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: member.isActive
                          ? ZadTokens.textMuted
                          : ZadTokens.textMuted.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (showActions) ...[
              IconButton(
                tooltip: member.isActive ? 'تعطيل' : 'تفعيل',
                icon: Icon(
                  member.isActive
                      ? Icons.person_off_outlined
                      : Icons.person_add_alt_1_outlined,
                  color: member.isActive
                      ? ZadTokens.warning
                      : ZadTokens.primary,
                ),
                onPressed: member.isActive ? onDeactivate : onReactivate,
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
          ],
        ),
      ),
    );
  }
}

/// Pill badge for the green hero: white-tinted, or solid gold for accent.
class _HeroBadge extends StatelessWidget {
  final String label;
  final bool gold;
  const _HeroBadge(this.label, {this.gold = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZadTokens.s2 + 2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: gold ? ZadTokens.gold : Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: gold ? ZadTokens.primaryDark : Colors.white,
        ),
      ),
    );
  }
}
