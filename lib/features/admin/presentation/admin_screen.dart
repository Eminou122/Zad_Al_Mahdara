import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/ltr_fragment.dart';
import '../../../core/widgets/zad_badge.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_confirm.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../core/widgets/zad_section_header.dart';
import '../../../services/auth_service.dart';
import '../data/admin_models.dart';
import '../data/admin_service.dart';

class AdminScreen extends StatefulWidget {
  final AuthService authService;
  final AdminService? service;

  const AdminScreen({super.key, required this.authService, this.service});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late final AdminService _admin =
      widget.service ?? AdminService(widget.authService);
  final _search = TextEditingController();
  Timer? _debounce;

  AdminDashboard? _dashboard;
  List<AdminUserSummary> _users = [];
  List<AdminPublicTeam> _teams = [];
  List<AdminPinResetRequest> _pinResetRequests = [];
  bool _loading = true;
  bool _usersLoading = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });
    try {
      final results = await Future.wait([
        _admin.getDashboard(),
        _admin.listUsers(_search.text),
        _admin.listPublicTeams(),
        _admin.listActivePinResetRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboard = results[0] as AdminDashboard;
        _users = results[1] as List<AdminUserSummary>;
        _teams = results[2] as List<AdminPublicTeam>;
        _pinResetRequests = results[3] as List<AdminPinResetRequest>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _safeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadUsers() async {
    setState(() {
      _usersLoading = true;
      _error = null;
      _message = null;
    });
    try {
      final users = await _admin.listUsers(_search.text);
      if (!mounted) return;
      setState(() {
        _users = users;
        _usersLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _safeError(e);
        _usersLoading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadUsers);
  }

  Future<void> _showUser(AdminUserSummary user) async {
    try {
      final detail = await _admin.getUserDetail(user.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: ZadTokens.background,
        builder: (_) => _UserDetailSheet(
          user: detail,
          onDeactivate: () => _changeUserActive(detail, false),
          onReactivate: () => _changeUserActive(detail, true),
        ),
      );
    } catch (e) {
      if (mounted) _snack(_safeError(e), danger: true);
    }
  }

  Future<void> _changeUserActive(AdminUserDetail user, bool active) async {
    final ok = await zadConfirm(
      context,
      title: active ? 'إعادة تفعيل المستخدم' : 'إيقاف المستخدم',
      body: active
          ? 'هل تريد إعادة تفعيل هذا المستخدم؟'
          : 'هل تريد إيقاف هذا المستخدم؟',
      confirmLabel: active ? 'إعادة التفعيل' : 'إيقاف',
    );
    if (!ok) return;

    try {
      if (active) {
        await _admin.reactivateUser(user.id);
      } else {
        await _admin.deactivateUser(user.id);
      }
      if (!mounted) return;
      Navigator.of(context).maybePop();
      setState(() => _message = active ? 'تمت إعادة التفعيل' : 'تم الإيقاف');
      await _loadAll();
    } catch (e) {
      if (mounted) _snack(_safeError(e), danger: true);
    }
  }

  Future<void> _issuePinResetCode(AdminPinResetRequest request) async {
    try {
      final issued = await _admin.issuePinResetCode(request.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _IssuedCodeDialog(issued: issued),
      );
      await _loadAll();
    } catch (e) {
      if (mounted) _snack(_safeError(e), danger: true);
    }
  }

  Future<void> _cancelPinResetRequest(AdminPinResetRequest request) async {
    final ok = await zadConfirm(
      context,
      title: 'إلغاء طلب إعادة التعيين',
      body: 'هل تريد إلغاء هذا الطلب؟',
      confirmLabel: 'إلغاء الطلب',
    );
    if (!ok) return;

    try {
      await _admin.cancelPinResetRequest(request.id);
      if (!mounted) return;
      await _loadAll();
      if (mounted) setState(() => _message = 'تم إلغاء طلب إعادة التعيين');
    } catch (e) {
      if (mounted) _snack(_safeError(e), danger: true);
    }
  }

  void _snack(String message, {bool danger = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: danger ? ZadTokens.danger : ZadTokens.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ZadScaffold(
      title: 'الإدارة',
      actions: [
        IconButton(
          tooltip: 'تحديث',
          onPressed: _loading ? null : _loadAll,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
                  if (_message != null)
                    ZadInfoBanner(_message!, kind: ZadBannerKind.success),
                  if (_dashboard != null) _DashboardGrid(_dashboard!),
                  const ZadSectionHeader('طلبات إعادة تعيين الرمز'),
                  if (_pinResetRequests.isEmpty)
                    const _EmptyCard('لا توجد طلبات نشطة')
                  else
                    for (final request in _pinResetRequests)
                      _PinResetRequestCard(
                        request: request,
                        onIssue: () => _issuePinResetCode(request),
                        onCancel: () => _cancelPinResetRequest(request),
                      ),
                  const ZadSectionHeader('المستخدمون'),
                  _SearchBox(
                    controller: _search,
                    loading: _usersLoading,
                    onChanged: _onSearchChanged,
                    onRefresh: _loadUsers,
                  ),
                  const SizedBox(height: ZadTokens.s3),
                  if (_users.isEmpty)
                    const _EmptyCard('لا يوجد مستخدمون')
                  else
                    for (final user in _users)
                      _UserCard(user: user, onTap: () => _showUser(user)),
                  const ZadSectionHeader('الفرق العامة'),
                  if (_teams.isEmpty)
                    const _EmptyCard('لا توجد فرق عامة')
                  else
                    for (final team in _teams) _TeamCard(team),
                ],
              ),
            ),
    );
  }
}

class _DashboardGrid extends StatelessWidget {
  final AdminDashboard dashboard;
  const _DashboardGrid(this.dashboard);

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard('نشطون', dashboard.activeUsersCount, Icons.verified_outlined),
      _StatCard('متوقفون', dashboard.inactiveUsersCount, Icons.block_outlined),
      _StatCard('فرق عامة', dashboard.publicTeamsCount, Icons.groups_outlined),
      _StatCard(
        'طلبات PIN',
        dashboard.pendingPinResetRequestsCount,
        Icons.lock_reset_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 380 ? 2 : 4;
        final width =
            (constraints.maxWidth - (columns - 1) * ZadTokens.s2) / columns;
        return Wrap(
          spacing: ZadTokens.s2,
          runSpacing: ZadTokens.s2,
          children: [
            for (final card in cards)
              SizedBox(width: width, height: 104, child: card),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  const _StatCard(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return ZadCard(
      padding: const EdgeInsets.all(ZadTokens.s3),
      highlighted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ZadTokens.primary, size: 20),
          const SizedBox(height: ZadTokens.s1),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$value',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: ZadTokens.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final ValueChanged<String> onChanged;
  final VoidCallback onRefresh;

  const _SearchBox({
    required this.controller,
    required this.loading,
    required this.onChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'بحث بالاسم أو الهاتف المخفي',
            ),
          ),
        ),
        const SizedBox(width: ZadTokens.s2),
        IconButton.filledTonal(
          tooltip: 'تحديث',
          onPressed: loading ? null : onRefresh,
          icon: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  final AdminUserSummary user;
  final VoidCallback onTap;
  const _UserCard({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ZadTokens.s2),
      child: Material(
        color: ZadTokens.surface,
        borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
          onTap: onTap,
          child: ZadCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Icon(Icons.chevron_left, color: ZadTokens.textMuted),
                  ],
                ),
                const SizedBox(height: ZadTokens.s2),
                Wrap(
                  spacing: ZadTokens.s2,
                  runSpacing: ZadTokens.s1,
                  children: [
                    ZadBadge(user.isActive ? 'نشط' : 'متوقف'),
                    if (user.isAdmin) const ZadBadge('مسؤول', gold: true),
                    _MaskedPhoneBadge(user.phoneMasked),
                  ],
                ),
                const SizedBox(height: ZadTokens.s2),
                _MetaLine(
                  createdAt: user.createdAt,
                  lastLoginAt: user.lastLoginAt,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserDetailSheet extends StatelessWidget {
  final AdminUserDetail user;
  final VoidCallback onDeactivate;
  final VoidCallback onReactivate;

  const _UserDetailSheet({
    required this.user,
    required this.onDeactivate,
    required this.onReactivate,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          ZadTokens.s4,
          ZadTokens.s4,
          ZadTokens.s4,
          ZadTokens.s4 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    user.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: ZadTokens.s2),
            Wrap(
              spacing: ZadTokens.s2,
              runSpacing: ZadTokens.s1,
              children: [
                ZadBadge(user.isActive ? 'نشط' : 'متوقف'),
                if (user.isAdmin) const ZadBadge('مسؤول', gold: true),
                _MaskedPhoneBadge(user.phoneMasked),
              ],
            ),
            const SizedBox(height: ZadTokens.s4),
            _DetailRow('تاريخ الإنشاء', _fmtDate(user.createdAt)),
            _DetailRow('آخر دخول', _fmtDate(user.lastLoginAt)),
            _DetailRow('محاولات فاشلة', '${user.failedLoginCount}'),
            if (user.lockedUntil != null)
              _DetailRow('مقفل حتى', _fmtDateTime(user.lockedUntil)),
            const SizedBox(height: ZadTokens.s4),
            if (!user.isAdmin)
              ElevatedButton.icon(
                onPressed: user.isActive ? onDeactivate : onReactivate,
                icon: Icon(user.isActive ? Icons.block : Icons.restart_alt),
                label: Text(user.isActive ? 'إيقاف المستخدم' : 'إعادة التفعيل'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: user.isActive
                      ? ZadTokens.danger
                      : ZadTokens.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PinResetRequestCard extends StatelessWidget {
  final AdminPinResetRequest request;
  final VoidCallback onIssue;
  final VoidCallback onCancel;

  const _PinResetRequestCard({
    required this.request,
    required this.onIssue,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return ZadCard(
      margin: const EdgeInsets.only(bottom: ZadTokens.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            request.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: ZadTokens.s2),
          Wrap(
            spacing: ZadTokens.s2,
            runSpacing: ZadTokens.s1,
            children: [
              ZadBadge(_resetStatus(request.status), gold: true),
              _MaskedPhoneBadge(request.phoneMasked),
              ZadBadge('محاولات: ${request.attemptCount}'),
            ],
          ),
          const SizedBox(height: ZadTokens.s2),
          Text(
            'أضيف: ${_fmtDateTime(request.createdAt)}'
            '${request.issuedAt == null ? '' : ' • أُصدر: ${_fmtDateTime(request.issuedAt)}'}'
            '${request.codeExpiresAt == null ? '' : ' • ينتهي: ${_fmtDateTime(request.codeExpiresAt)}'}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: ZadTokens.textMuted),
          ),
          const SizedBox(height: ZadTokens.s3),
          LayoutBuilder(
            builder: (context, constraints) {
              final issue = FilledButton.icon(
                onPressed: onIssue,
                icon: const Icon(Icons.lock_reset_outlined, size: 18),
                label: Text(
                  request.status == 'code_issued'
                      ? 'إصدار رمز جديد'
                      : 'إصدار رمز',
                ),
              );
              final cancel = OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('إلغاء'),
              );
              if (constraints.maxWidth < 300) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    issue,
                    const SizedBox(height: ZadTokens.s2),
                    cancel,
                  ],
                );
              }
              return Wrap(
                spacing: ZadTokens.s2,
                runSpacing: ZadTokens.s2,
                children: [issue, cancel],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _IssuedCodeDialog extends StatelessWidget {
  final AdminIssuedPinResetCode issued;
  const _IssuedCodeDialog({required this.issued});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('رمز إعادة التعيين'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'سيظهر هذا الرمز مرة واحدة فقط. انسخه أو أعطه للطالب الآن.',
          ),
          const SizedBox(height: ZadTokens.s3),
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(
              issued.code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
          if (issued.codeExpiresAt != null) ...[
            const SizedBox(height: ZadTokens.s2),
            Text(
              'ينتهي: ${_fmtDateTime(issued.codeExpiresAt)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: ZadTokens.textMuted),
            ),
          ],
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: issued.code));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('تم نسخ الرمز')));
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('نسخ'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('تم'),
        ),
      ],
    );
  }
}

class _TeamCard extends StatelessWidget {
  final AdminPublicTeam team;
  const _TeamCard(this.team);

  @override
  Widget build(BuildContext context) {
    return ZadCard(
      margin: const EdgeInsets.only(bottom: ZadTokens.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            team.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: ZadTokens.s2),
          Wrap(
            spacing: ZadTokens.s2,
            runSpacing: ZadTokens.s1,
            children: [
              ZadBadge(_teamType(team.teamType), gold: true),
              ZadBadge(_teamStatus(team.status)),
              ZadBadge('${ltrFragment('${team.memberCount}')} عضو'),
            ],
          ),
          const SizedBox(height: ZadTokens.s2),
          Text(
            'القائد: ${team.leaderName}',
            style: const TextStyle(color: ZadTokens.textMuted),
          ),
          const SizedBox(height: ZadTokens.s1),
          Text(
            'نشطون: ${ltrFragment('${team.activeMemberCount}')} • '
            'متوقفون: ${ltrFragment('${team.inactiveMemberCount}')}'
            '${team.createdAt == null ? '' : ' • ${ltrFragment(_fmtDate(team.createdAt))}'}',
            style: const TextStyle(fontSize: 12, color: ZadTokens.textMuted),
          ),
        ],
      ),
    );
  }
}

class _MaskedPhoneBadge extends StatelessWidget {
  final String value;
  const _MaskedPhoneBadge(this.value);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ZadBadge(value, gold: true),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  const _MetaLine({required this.createdAt, required this.lastLoginAt});

  @override
  Widget build(BuildContext context) {
    return Text(
      'أضيف: ${ltrFragment(_fmtDate(createdAt))}'
      '${lastLoginAt == null ? '' : ' • آخر دخول: ${ltrFragment(_fmtDate(lastLoginAt))}'}',
      style: const TextStyle(fontSize: 12, color: ZadTokens.textMuted),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ZadTokens.s2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: ZadTokens.textMuted),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard(this.message);

  @override
  Widget build(BuildContext context) {
    return ZadCard(
      child: Text(message, style: const TextStyle(color: ZadTokens.textMuted)),
    );
  }
}

String _fmtDate(DateTime? d) {
  if (d == null) return 'غير متوفر';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _fmtDateTime(DateTime? d) {
  if (d == null) return 'غير متوفر';
  return '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _teamType(String value) {
  if (value == 'mahdara') return 'محظرة';
  if (value == 'housing') return 'سكن';
  return value;
}

String _teamStatus(String value) {
  if (value == 'open') return 'مفتوح';
  if (value == 'closed') return 'مغلق';
  return value;
}

String _resetStatus(String value) {
  if (value == 'pending') return 'بانتظار الرمز';
  if (value == 'code_issued') return 'صدر رمز';
  if (value == 'used') return 'مستخدم';
  if (value == 'expired') return 'منتهي';
  if (value == 'cancelled') return 'ملغى';
  return value;
}

String _safeError(Object e) {
  final msg = e is PostgrestException
      ? e.message.toLowerCase()
      : '$e'.toLowerCase();
  if (msg.contains('admin only')) return 'هذه الصفحة للمسؤولين فقط';
  if (msg.contains('invalid session') || msg.contains('not authenticated')) {
    return 'انتهت الجلسة — يرجى تسجيل الدخول من جديد';
  }
  if (msg.contains('cannot act on own account')) {
    return 'لا يمكن تنفيذ هذا الإجراء على حسابك';
  }
  if (msg.contains('cannot deactivate an admin account')) {
    return 'لا يمكن إيقاف حساب مسؤول';
  }
  if (msg.contains('pin reset request not found')) {
    return 'طلب إعادة التعيين غير موجود';
  }
  if (msg.contains('user not found')) return 'المستخدم غير موجود';
  return 'حدث خطأ — حاول مرة أخرى';
}
