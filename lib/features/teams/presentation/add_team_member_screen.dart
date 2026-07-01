import 'package:flutter/material.dart';
import '../../../core/utils/error_text.dart';
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  labelText: 'البحث بالاسم (حرفان على الأقل)',
                  border: const OutlineInputBorder(),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.search),
                ),
                onChanged: _search,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('إضافة طالب بدون حساب'),
                childrenPadding: const EdgeInsets.only(bottom: 12),
                children: [
                  TextField(
                    controller: _nameCtrl,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'اسم الطالب',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    maxLength: 8,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_externalError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _externalError!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: _addingExternal
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.person_add_alt_1),
                      label: const Text('إضافة طالب بدون حساب'),
                      onPressed: _addingExternal ? null : _addExternal,
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        _searchCtrl.text.length < 2
                            ? 'ابحث عن طالب للإضافة'
                            : 'لا توجد نتائج',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final s = _results[i];
                        return ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(s.displayName),
                          subtitle: Text(s.phoneMasked),
                          trailing: _adding.contains(s.profileId)
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(
                                    Icons.person_add,
                                    color: Color(0xFF2E7D32),
                                  ),
                                  onPressed: () => _add(s),
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
