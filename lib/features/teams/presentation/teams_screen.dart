import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/error_text.dart';
import '../../../services/auth_service.dart';
import '../data/team_service.dart';
import '../domain/team_models.dart';

class TeamsScreen extends StatefulWidget {
  final AuthService authService;
  const TeamsScreen({super.key, required this.authService});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  late final TeamService _svc;
  List<TeamSummary> _mine = [];
  List<TeamSummary> _public = [];
  bool _loading = true;
  String? _error;
  bool _showPublic = false;

  @override
  void initState() {
    super.initState();
    _svc = TeamService(widget.authService);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _svc.getMyTeams(),
        _svc.getPublicTeams(),
      ]);
      if (mounted) {
        setState(() {
          _mine = results[0];
          _public = results[1];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userErrorText(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الفرق')),
      floatingActionButton: !_showPublic
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF2E7D32),
              onPressed: () => context.push('/teams/new').then((_) => _load()),
              child: const Icon(Icons.add),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => _showPublic = false),
                    style: TextButton.styleFrom(
                      foregroundColor: !_showPublic
                          ? const Color(0xFF2E7D32)
                          : Colors.grey,
                    ),
                    child: const Text('فرقي'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => _showPublic = true),
                    style: TextButton.styleFrom(
                      foregroundColor: _showPublic
                          ? const Color(0xFF2E7D32)
                          : Colors.grey,
                    ),
                    child: const Text('الفرق العامة'),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            if (_loading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
                ),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(onRefresh: _load, child: _buildList()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final items = _showPublic ? _public : _mine;
    if (items.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Center(
              child: Text(
                _showPublic ? 'لا توجد فرق عامة' : 'لا توجد فرق بعد',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) => _TeamCard(
        team: items[i],
        onTap: () => context.push('/teams/${items[i].id}').then((_) => _load()),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  final TeamSummary team;
  final VoidCallback onTap;
  const _TeamCard({required this.team, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          team.isPublic ? Icons.group : Icons.lock_outline,
          color: const Color(0xFF2E7D32),
        ),
        title: Text(team.name),
        subtitle: Text(
          '${teamTypeLabels[team.teamType] ?? team.teamType} · ${team.memberCount} عضو',
        ),
        trailing: Chip(
          label: Text(
            teamStatusLabels[team.status] ?? team.status,
            style: const TextStyle(fontSize: 12),
          ),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
