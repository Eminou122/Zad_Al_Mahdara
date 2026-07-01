import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/auth_service.dart';
import '../data/team_service.dart';
import '../domain/team_models.dart';

class AddTeamMemberScreen extends StatefulWidget {
  final AuthService authService;
  final String teamId;
  const AddTeamMemberScreen({super.key, required this.authService, required this.teamId});

  @override
  State<AddTeamMemberScreen> createState() => _AddTeamMemberScreenState();
}

class _AddTeamMemberScreenState extends State<AddTeamMemberScreen> {
  late final TeamService _svc;
  final _searchCtrl = TextEditingController();
  List<StudentResult> _results = [];
  bool _searching = false;
  String? _error;
  final Set<String> _adding = {};

  @override
  void initState() {
    super.initState();
    _svc = TeamService(widget.authService);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() { _results = []; _error = null; });
      return;
    }
    setState(() { _searching = true; _error = null; });
    try {
      final r = await _svc.searchStudents(q.trim());
      if (mounted) setState(() { _results = r; _searching = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _searching = false; });
    }
  }

  Future<void> _add(StudentResult s) async {
    setState(() => _adding.add(s.profileId));
    try {
      await _svc.addTeamMember(teamId: widget.teamId, profileId: s.profileId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تمت إضافة ${s.displayName}')),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _adding.remove(s.profileId));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : const Icon(Icons.search),
                ),
                onChanged: _search,
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
                        _searchCtrl.text.length < 2 ? 'ابحث عن طالب للإضافة' : 'لا توجد نتائج',
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
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(
                                  icon: const Icon(Icons.person_add, color: Color(0xFF2E7D32)),
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
