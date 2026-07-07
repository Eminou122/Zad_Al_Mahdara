import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/ltr_fragment.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../services/auth_service.dart';
import '../data/team_service.dart';
import '../domain/team_models.dart';

// Stitch add_member accents, kept screen-local.
const _surface = Color(0xFFFFF8F4);
const _surfaceLow = Color(0xFFFFF1E4);
const _warmBorder = Color(0xFFF2E0CC);
const _paleGreen = Color(0xFFB1F1C8);

class AddTeamMemberScreen extends StatefulWidget {
  final AuthService authService;
  final String teamId;
  final TeamService? teamService;
  const AddTeamMemberScreen({
    super.key,
    required this.authService,
    required this.teamId,
    this.teamService,
  });

  @override
  State<AddTeamMemberScreen> createState() => _AddTeamMemberScreenState();
}

class _AddTeamMemberScreenState extends State<AddTeamMemberScreen> {
  late final TeamService _svc;
  final _searchCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  List<TeamMemberCandidate> _candidates = [];
  String? _currentQuery;
  bool _loading = true;
  bool _refreshing = false;
  bool _hasLoadedOnce = false;
  bool _addingExternal = false;
  String? _error;
  String? _externalError;
  final Set<String> _adding = {};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _svc = widget.teamService ?? TeamService(widget.authService);
    _loadCandidates(null);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final trimmed = q.trim();
      _loadCandidates(trimmed.isEmpty ? null : trimmed);
    });
  }

  Future<void> _loadCandidates(String? query) async {
    _currentQuery = query;
    setState(() {
      if (_hasLoadedOnce) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final r = await _svc.getTeamMemberCandidates(widget.teamId,
          query: query);
      if (mounted) {
        setState(() {
          _candidates = r;
          _loading = false;
          _refreshing = false;
          _hasLoadedOnce = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userErrorText(e);
          _loading = false;
          _refreshing = false;
          _hasLoadedOnce = true;
        });
      }
    }
  }

  Future<void> _add(TeamMemberCandidate c) async {
    if (!c.canAdd) return;
    setState(() => _adding.add(c.profileId));
    try {
      await _svc.addTeamMember(teamId: widget.teamId, profileId: c.profileId);
      if (mounted) {
        setState(() => _adding.remove(c.profileId));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم إضافة الطالب بنجاح')));
        await _loadCandidates(_currentQuery);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _adding.remove(c.profileId));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  Future<void> _addExternal() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty || name.length > 80) {
      setState(() => _externalError = 'اسم الطالب مطلوب');
      return;
    }
    if (!RegExp(r'^\d{8}$').hasMatch(phone)) {
      setState(() => _externalError = 'رقم الهاتف يجب أن يكون 8 أرقام');
      return;
    }
    setState(() {
      _addingExternal = true;
      _externalError = null;
    });
    try {
      await _svc.upsertExternalStudentAndAddToTeam(
        teamId: widget.teamId,
        displayName: name,
        phoneNumber: phone,
      );
      if (mounted) {
        _nameCtrl.clear();
        _phoneCtrl.clear();
        setState(() {
          _addingExternal = false;
          _externalError = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم إضافة الطالب بنجاح')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _addingExternal = false;
          _externalError = userErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text('إضافة عضو'),
        backgroundColor: _surface,
        surfaceTintColor: _surface,
        foregroundColor: ZadTokens.primary,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _warmBorder),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ZadTokens.contentMaxWidth,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'ابحث عن طالب بالاسم',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _refreshing
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                      filled: true,
                      fillColor: _surfaceLow,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: ZadTokens.s3,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: ZadTokens.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _warmBorder),
                      boxShadow: ZadTokens.cardShadow,
                    ),
                    child: ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: ZadTokens.s3,
                        vertical: ZadTokens.s1,
                      ),
                      leading: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ZadTokens.gold.withValues(alpha: 0.24),
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1,
                          size: 22,
                          color: ZadTokens.goldDark,
                        ),
                      ),
                      title: const Text(
                        'إضافة طالب بدون حساب',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'إضافة زميل غير مسجل',
                        style: TextStyle(fontSize: 12),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(
                        ZadTokens.s3,
                        0,
                        ZadTokens.s3,
                        ZadTokens.s3,
                      ),
                      children: [
                        TextField(
                          controller: _nameCtrl,
                          maxLength: 80,
                          decoration: const InputDecoration(
                            labelText: 'اسم الطالب',
                          ),
                        ),
                        const SizedBox(height: ZadTokens.s2),
                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          maxLength: 8,
                          decoration: const InputDecoration(
                            labelText: 'رقم الهاتف',
                          ),
                        ),
                        if (_externalError != null)
                          ZadInfoBanner(
                            _externalError!,
                            kind: ZadBannerKind.danger,
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _addingExternal
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.person_add_alt_1),
                            label: const Text('إضافة طالب بدون حساب'),
                            onPressed: _addingExternal ? null : _addExternal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, ZadTokens.s3, 20, 0),
                    child: ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _loading
                        ? const Center(
                            key: ValueKey('loading'),
                            child: CircularProgressIndicator(),
                          )
                        : _candidates.isEmpty
                            ? ListView(
                                key: const ValueKey('empty'),
                                padding:
                                    const EdgeInsets.fromLTRB(20, 20, 20, 96),
                                children: [
                                  _CompactEmptyState(
                                    icon: Icons.person_search_outlined,
                                    message: (_currentQuery == null ||
                                            _currentQuery!.isEmpty)
                                        ? 'لا توجد حسابات متاحة'
                                        : 'لا توجد نتائج',
                                  ),
                                ],
                              )
                            : ListView.builder(
                                key: const ValueKey('candidates'),
                                padding:
                                    const EdgeInsets.fromLTRB(20, 20, 20, 96),
                                itemCount: _candidates.length,
                                itemBuilder: (_, i) {
                                  final c = _candidates[i];
                                  return _CandidateRow(
                                    candidate: c,
                                    busy: _adding.contains(c.profileId),
                                    onAdd: () => _add(c),
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  final TeamMemberCandidate candidate;
  final bool busy;
  final VoidCallback onAdd;

  const _CandidateRow({
    required this.candidate,
    required this.busy,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: ZadTokens.s2),
      padding: const EdgeInsets.all(ZadTokens.s2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _warmBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _surfaceLow,
              border: Border.all(color: _warmBorder),
            ),
            child: const Icon(
              Icons.person_outline,
              color: ZadTokens.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: ZadTokens.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                  ),
                ),
                if (candidate.phoneMasked != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    ltrFragment(candidate.phoneMasked!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ZadTokens.textMuted,
                    ),
                  ),
                ],
                if (candidate.isAlreadyAdded) ...[
                  const SizedBox(height: 4),
                  const _StatusChip('مضاف'),
                ] else if (candidate.isConflictSameCategory) ...[
                  const SizedBox(height: 4),
                  const _StatusChip('في فريق آخر لنفس الوجبة', warning: true),
                  if (candidate.conflictingTeamName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'الفريق: ${candidate.conflictingTeamName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: ZadTokens.textMuted,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(width: ZadTokens.s2),
          if (busy)
            const SizedBox(
              width: 34,
              height: 34,
              child: Padding(
                padding: EdgeInsets.all(7),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (candidate.canAdd)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: ZadTokens.primary,
                foregroundColor: _paleGreen,
                minimumSize: const Size(74, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('إضافة'),
              onPressed: onAdd,
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool warning;
  const _StatusChip(this.label, {this.warning = false});

  @override
  Widget build(BuildContext context) {
    final color = warning ? ZadTokens.warning : ZadTokens.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _CompactEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _CompactEmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZadTokens.s3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _warmBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: ZadTokens.textMuted),
          const SizedBox(width: ZadTokens.s2),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: ZadTokens.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
