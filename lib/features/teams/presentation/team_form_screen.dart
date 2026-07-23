import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/ltr_fragment.dart';
import '../../../core/utils/mauritanian_phone.dart';
import '../../../core/widgets/mauritanian_phone_field.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../services/auth_service.dart';
import '../data/team_service.dart';
import '../domain/team_models.dart';

/// One row in the team-creation member list: the creator ('leader'), a
/// registered user ('account'), or a manually-entered member ('manual').
/// Mirrors the {kind, profile_id?, name?, phone?} shape create_team_with_members
/// expects, so submission is just `_members.map((e) => e.toJson())`.
class _DraftMember {
  final String kind;
  final String? profileId;
  final String name;
  final String? phone;

  const _DraftMember.leader({required this.name, this.phone})
    : kind = 'leader',
      profileId = null;
  const _DraftMember.account({
    required this.profileId,
    required this.name,
    this.phone,
  }) : kind = 'account';
  const _DraftMember.manual({required this.name, required this.phone})
    : kind = 'manual',
      profileId = null;

  Map<String, dynamic> toJson() => switch (kind) {
    'leader' => {'kind': 'leader'},
    'account' => {'kind': 'account', 'profile_id': profileId},
    _ => {'kind': 'manual', 'name': name, 'phone': phone},
  };
}

class TeamFormScreen extends StatefulWidget {
  final AuthService authService;
  final String? teamId;
  final TeamInfo? existing;
  final TeamService? teamService;
  const TeamFormScreen({
    super.key,
    required this.authService,
    this.teamId,
    this.existing,
    this.teamService,
  });

  @override
  State<TeamFormScreen> createState() => _TeamFormScreenState();
}

class _TeamFormScreenState extends State<TeamFormScreen> {
  late final TeamService _svc;
  final _nameCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _teamType = 'lunch';
  String _status = 'open';
  bool _isPublic = true;
  bool _saving = false;
  String? _error;

  final List<_DraftMember> _members = [];
  final _memberSearchCtrl = TextEditingController();
  final _manualNameCtrl = TextEditingController();
  final _manualPhoneCtrl = TextEditingController();
  List<StudentResult> _searchResults = [];
  bool _searching = false;
  String? _searchError;
  String? _manualError;
  Timer? _searchDebounce;

  bool get _isEdit => widget.teamId != null;

  @override
  void initState() {
    super.initState();
    _svc = widget.teamService ?? TeamService(widget.authService);
    if (widget.existing != null) {
      final e = widget.existing!;
      _nameCtrl.text = e.name;
      _noteCtrl.text = e.note ?? '';
      _teamType = selectableTeamTypeLabels.containsKey(e.teamType)
          ? e.teamType
          : 'lunch';
      _status = e.status;
      _isPublic = e.isPublic;
    } else {
      final me = widget.authService.profile;
      _members.add(
        _DraftMember.leader(
          name: me?.displayName ?? '',
          phone: me?.phoneMasked,
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    _memberSearchCtrl.dispose();
    _manualNameCtrl.dispose();
    _manualPhoneCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onMemberSearchChanged(String q) {
    _searchDebounce?.cancel();
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() {
        _searching = true;
        _searchError = null;
      });
      try {
        final r = await _svc.searchStudents(trimmed);
        if (mounted) setState(() => _searchResults = r);
      } catch (e) {
        if (mounted) setState(() => _searchError = userErrorText(e));
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _addRegistered(StudentResult s) {
    if (_members.any((m) => m.profileId == s.profileId)) return;
    setState(() {
      _members.add(
        _DraftMember.account(
          profileId: s.profileId,
          name: s.displayName,
          phone: s.phoneMasked,
        ),
      );
    });
  }

  void _addManual() {
    final name = _manualNameCtrl.text.trim();
    final phone = normalizeMauritanianPhone(_manualPhoneCtrl.text);
    if (name.isEmpty || name.length > 80) {
      setState(() => _manualError = 'اسم العضو مطلوب');
      return;
    }
    final phoneError = validateMauritanianPhone(phone);
    if (phoneError != null) {
      setState(() => _manualError = phoneError);
      return;
    }
    setState(() {
      _members.add(_DraftMember.manual(name: name, phone: phone));
      _manualNameCtrl.clear();
      _manualPhoneCtrl.clear();
      _manualError = null;
    });
  }

  void _moveMember(int from, int to) {
    setState(() {
      final m = _members.removeAt(from);
      _members.insert(to, m);
    });
  }

  void _removeMember(int index) {
    setState(() => _members.removeAt(index));
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اسم الفريق مطلوب');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await _svc.updateTeamSettings(
          teamId: widget.teamId!,
          name: name,
          teamType: _teamType,
          isPublic: _isPublic,
          status: _status,
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        );
      } else {
        await _svc.createTeamWithMembers(
          name: name,
          teamType: _teamType,
          isPublic: _isPublic,
          status: _status,
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          members: _members.map((m) => m.toJson()).toList(),
        );
      }
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userErrorText(e);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ZadScaffold(
      title: _isEdit ? 'تعديل الفريق' : 'فريق جديد',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'اسم الفريق'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _teamType, // ignore: deprecated_member_use
            decoration: const InputDecoration(labelText: 'نوع الفريق'),
            items: selectableTeamTypeLabels.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _teamType = v);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _status, // ignore: deprecated_member_use
            decoration: const InputDecoration(labelText: 'الحالة'),
            items: teamStatusLabels.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _status = v);
            },
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('فريق عام'),
            subtitle: const Text('يظهر للجميع في قائمة الفرق العامة'),
            value: _isPublic,
            onChanged: (v) => setState(() => _isPublic = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
            maxLines: 3,
          ),
          if (!_isEdit) ...[const SizedBox(height: 24), ..._membersSection()],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  List<Widget> _membersSection() {
    return [
      Text(
        'أعضاء الفريق',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: ZadTokens.s2),
      Container(
        key: const Key('team-form-member-list'),
        decoration: BoxDecoration(
          border: Border.all(color: ZadTokens.surfaceContainer),
          borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
        ),
        child: Column(
          children: [
            for (final entry in _members.asMap().entries) ...[
              if (entry.key > 0)
                const Divider(height: 1, color: ZadTokens.surfaceContainer),
              _DraftMemberRow(
                position: entry.key + 1,
                member: entry.value,
                onUp: entry.key == 0
                    ? null
                    : () => _moveMember(entry.key, entry.key - 1),
                onDown: entry.key == _members.length - 1
                    ? null
                    : () => _moveMember(entry.key, entry.key + 1),
                onRemove: entry.value.kind == 'leader'
                    ? null
                    : () => _removeMember(entry.key),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: ZadTokens.s3),
      TextField(
        key: const Key('team-form-member-search'),
        controller: _memberSearchCtrl,
        decoration: InputDecoration(
          labelText: 'إضافة عضو مسجل',
          hintText: 'ابحث عن طالب بالاسم',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
        onChanged: _onMemberSearchChanged,
      ),
      if (_searchError != null)
        Padding(
          padding: const EdgeInsets.only(top: ZadTokens.s1),
          child: ZadInfoBanner(_searchError!, kind: ZadBannerKind.warning),
        ),
      if (_searchResults.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: ZadTokens.s2),
          child: Column(
            children: _searchResults.map((s) {
              final added = _members.any((m) => m.profileId == s.profileId);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(s.displayName),
                subtitle: Text(ltrFragment(s.phoneMasked)),
                trailing: added
                    ? const Text(
                        'مضاف',
                        style: TextStyle(
                          color: ZadTokens.textMuted,
                          fontSize: 12,
                        ),
                      )
                    : TextButton(
                        onPressed: () => _addRegistered(s),
                        child: const Text('إضافة'),
                      ),
              );
            }).toList(),
          ),
        ),
      const SizedBox(height: ZadTokens.s3),
      Text(
        'إضافة عضو يدوياً',
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: ZadTokens.s2),
      TextField(
        key: const Key('team-form-manual-name'),
        controller: _manualNameCtrl,
        maxLength: 80,
        decoration: const InputDecoration(labelText: 'اسم العضو'),
      ),
      const SizedBox(height: ZadTokens.s2),
      MauritanianPhoneField(
        controller: _manualPhoneCtrl,
        labelText: 'رقم الهاتف',
      ),
      if (_manualError != null)
        Padding(
          padding: const EdgeInsets.only(top: ZadTokens.s1),
          child: ZadInfoBanner(_manualError!, kind: ZadBannerKind.danger),
        ),
      const SizedBox(height: ZadTokens.s2),
      OutlinedButton.icon(
        onPressed: _addManual,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('إضافة عضو يدوياً'),
      ),
    ];
  }
}

class _DraftMemberRow extends StatelessWidget {
  final int position;
  final _DraftMember member;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onRemove;

  const _DraftMemberRow({
    required this.position,
    required this.member,
    this.onUp,
    this.onDown,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final caption = [
      if (member.kind == 'leader')
        'أنت (المنشئ)'
      else if (member.kind == 'manual')
        'بدون حساب',
      if (member.phone != null) ltrFragment(member.phone!),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZadTokens.s3,
        vertical: ZadTokens.s2,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ZadTokens.surfaceContainer,
              borderRadius: BorderRadius.circular(ZadTokens.radiusSm),
            ),
            child: Text(
              '$position',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: ZadTokens.primary,
              ),
            ),
          ),
          const SizedBox(width: ZadTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (caption.isNotEmpty)
                  Text(
                    caption,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ZadTokens.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'رفع',
            visualDensity: VisualDensity.compact,
            onPressed: onUp,
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          IconButton(
            tooltip: 'خفض',
            visualDensity: VisualDensity.compact,
            onPressed: onDown,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'إزالة',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, color: ZadTokens.danger),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}
