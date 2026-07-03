import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_badge.dart';
import '../../../core/widgets/zad_empty_state.dart';
import '../../../core/widgets/zad_info_banner.dart';
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
              backgroundColor: ZadTokens.primary,
              foregroundColor: Colors.white,
              onPressed: () => context.push('/teams/new').then((_) => _load()),
              child: const Icon(Icons.add),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            // Segmented pill toggle (Stitch teams_list).
            Container(
              margin: const EdgeInsets.fromLTRB(
                ZadTokens.s3,
                ZadTokens.s3,
                ZadTokens.s3,
                ZadTokens.s1,
              ),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                maxWidth: ZadTokens.contentMaxWidth,
              ),
              decoration: BoxDecoration(
                color: ZadTokens.surfaceContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  _tab('فرقي', !_showPublic, () {
                    setState(() => _showPublic = false);
                  }),
                  _tab('الفرق العامة', _showPublic, () {
                    setState(() => _showPublic = true);
                  }),
                ],
              ),
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(ZadTokens.s4),
                    child: ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
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

  Widget _tab(String label, bool selected, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? ZadTokens.primaryDark : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : ZadTokens.textMuted,
          ),
        ),
      ),
    ),
  );

  Widget _buildList() {
    final items = _showPublic ? _public : _mine;
    // Side padding grows on wide screens so cards stay near contentMaxWidth.
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = ((constraints.maxWidth - ZadTokens.contentMaxWidth) / 2)
            .clamp(ZadTokens.s3, double.infinity);
        if (items.isEmpty) {
          return ListView(
            padding: EdgeInsets.symmetric(
              horizontal: side,
              vertical: ZadTokens.s6,
            ),
            children: [
              ZadAnimatedEntry(
                child: ZadEmptyState(
                  icon: _showPublic ? Icons.public_off : Icons.group_outlined,
                  message: _showPublic ? 'لا توجد فرق عامة' : 'لا توجد فرق بعد',
                ),
              ),
            ],
          );
        }
        return ListView.builder(
          padding: EdgeInsets.symmetric(
            horizontal: side,
            vertical: ZadTokens.s3,
          ),
          itemCount: items.length,
          // Stagger only the first screenful; later rows appear instantly
          // while scrolling. Entry state persists, so the "فرقي/عامة" toggle
          // swaps content without replaying the animation.
          itemBuilder: (_, i) => ZadAnimatedEntry(
            delay: Duration(milliseconds: i < 6 ? 40 * i : 0),
            child: _TeamCard(
              team: items[i],
              onTap: () =>
                  context.push('/teams/${items[i].id}').then((_) => _load()),
            ),
          ),
        );
      },
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
      margin: const EdgeInsets.only(bottom: ZadTokens.s3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(ZadTokens.s4),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ZadTokens.surfaceContainer,
                      borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
                    ),
                    child: Icon(
                      team.isPublic ? Icons.menu_book : Icons.lock_outline,
                      size: 24,
                      color: ZadTokens.primary,
                    ),
                  ),
                  const SizedBox(width: ZadTokens.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          team.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: ZadTokens.s2),
                        Wrap(
                          spacing: ZadTokens.s2,
                          runSpacing: ZadTokens.s1,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ZadBadge(
                              teamTypeLabels[team.teamType] ?? team.teamType,
                              gold: true,
                            ),
                            ZadBadge(
                              teamStatusLabels[team.status] ?? team.status,
                            ),
                            if (team.myRole == 'leader') const ZadBadge('قائد'),
                            ZadBadge(team.isPublic ? 'عام' : 'خاص'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_left, color: ZadTokens.textMuted),
                ],
              ),
              const Divider(height: ZadTokens.s5),
              Row(
                children: [
                  const Icon(
                    Icons.people_alt_outlined,
                    size: 16,
                    color: ZadTokens.textMuted,
                  ),
                  const SizedBox(width: ZadTokens.s1 + 2),
                  Text(
                    '${team.memberCount} عضو',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: ZadTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
