import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../services/auth_service.dart';
import '../data/team_service.dart';
import '../domain/team_models.dart';

class TeamFormScreen extends StatefulWidget {
  final AuthService authService;
  final String? teamId;
  final TeamInfo? existing;
  const TeamFormScreen({
    super.key,
    required this.authService,
    this.teamId,
    this.existing,
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

  bool get _isEdit => widget.teamId != null;

  @override
  void initState() {
    super.initState();
    _svc = TeamService(widget.authService);
    if (widget.existing != null) {
      final e = widget.existing!;
      _nameCtrl.text = e.name;
      _noteCtrl.text = e.note ?? '';
      _teamType = e.teamType;
      _status = e.status;
      _isPublic = e.isPublic;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
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
        await _svc.createTeam(
          name: name,
          teamType: _teamType,
          isPublic: _isPublic,
          status: _status,
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        );
      }
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
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
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'اسم الفريق',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _teamType, // ignore: deprecated_member_use
            decoration: const InputDecoration(
              labelText: 'نوع الفريق',
              border: OutlineInputBorder(),
            ),
            items: teamTypeLabels.entries
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
            decoration: const InputDecoration(
              labelText: 'الحالة',
              border: OutlineInputBorder(),
            ),
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
            activeThumbColor: const Color(0xFF2E7D32),
            onChanged: (v) => setState(() => _isPublic = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
              labelText: 'ملاحظة (اختياري)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
            ),
            child: _saving
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
