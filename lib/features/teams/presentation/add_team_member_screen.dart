import 'package:flutter/material.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/zad_empty_state.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../services/auth_service.dart';
import '../data/team_service.dart';
import '../domain/team_models.dart';

class AddTeamMemberScreen extends StatefulWidget {
  final AuthService authService;
  final String teamId;
  const AddTeamMemberScreen({
    super.key,
    required this.authService,
    required this.teamId,
  });

  @override
  State<AddTeamMemberScreen> createState() => _AddTeamMemberScreenState();
}

class _AddTeamMemberScreenState extends State<AddTeamMemberScreen> {
  late final TeamService _svc;
  final _searchCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  List<StudentResult> _results = [];
  bool _searching = false;
  bool _addingExternal = false;
  String? _error;
  String? _externalError;
  bool _showExternal = false;
  final Set<String> _adding = {};

  @override
  void initState() {
    super.initState();
    _svc = TeamService(widget.authService);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final r = await _svc.searchStudents(q.trim());
      if (mounted) {
        setState(() {
          _results = r;
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userErrorText(e);
          _searching = false;
        });
      }
    }
  }

  Future<void> _add(StudentResult s) async {
    setState(() => _adding.add(s.profileId));
    try {
      await _svc.addTeamMember(teamId: widget.teamId, profileId: s.profileId);
      if (mounted) {
        _searchCtrl.clear();
        setState(() {
          _adding.remove(s.profileId);
          _results = [];
          _error = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم إضافة الطالب بنجاح')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _adding.remove(s.profileId));
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
      appBar: AppBar(title: const Text('إضافة عضو')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ZadTokens.contentMaxWidth,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ZadTokens.s3,
                    ZadTokens.s4,
                    ZadTokens.s3,
                    ZadTokens.s3,
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'ابحث عن طالب بالاسم (حرفان على الأقل)',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searching
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
                    ),
                    onChanged: _search,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ZadTokens.s3),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: ExpansionTile(
                      key: ValueKey(_showExternal),
                      initiallyExpanded: _showExternal,
                      onExpansionChanged: (value) =>
                          setState(() => _showExternal = value),
                      shape: const Border(),
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: ZadTokens.s3,
                      ),
                      leading: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ZadTokens.gold.withValues(alpha: 0.15),
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1,
                          size: 20,
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
                    padding: const EdgeInsets.fromLTRB(
                      ZadTokens.s3,
                      ZadTokens.s3,
                      ZadTokens.s3,
                      0,
                    ),
                    child: ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
                  ),
                Expanded(
                  // 200ms crossfade between empty state and results. Keys are
                  // per-state, so typing inside results never re-animates.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _results.isEmpty
                        // Plain ListView keeps the empty card full-width and
                        // top-aligned instead of a centered narrow tower.
                        ? ListView(
                            key: const ValueKey('empty'),
                            padding: const EdgeInsets.all(ZadTokens.s3),
                            children: [
                              ZadEmptyState(
                                icon: Icons.person_search_outlined,
                                message: _searchCtrl.text.length < 2
                                    ? 'ابحث عن طالب لإضافته إلى الفريق'
                                    : 'لا توجد نتائج',
                              ),
                            ],
                          )
                        : ListView.builder(
                            key: const ValueKey('results'),
                            padding: const EdgeInsets.all(ZadTokens.s3),
                            itemCount: _results.length,
                            itemBuilder: (_, i) {
                              final s = _results[i];
                              return Card(
                                margin: const EdgeInsets.only(
                                  bottom: ZadTokens.s2,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: ZadTokens.s3,
                                    vertical: ZadTokens.s2,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              s.displayName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              s.phoneMasked,
                                              style: const TextStyle(
                                                color: ZadTokens.textMuted,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _adding.contains(s.profileId)
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                minimumSize: const Size(0, 36),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: ZadTokens.s3,
                                                    ),
                                                shape: const StadiumBorder(),
                                                textStyle: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.add,
                                                size: 16,
                                              ),
                                              label: const Text('إضافة'),
                                              onPressed: () => _add(s),
                                            ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(ZadTokens.s3),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('إضافة المزيد'),
                    onPressed: () => setState(() => _showExternal = true),
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
