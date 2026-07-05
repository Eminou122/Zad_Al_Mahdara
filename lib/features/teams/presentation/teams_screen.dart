import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_badge.dart';
import '../../../core/widgets/zad_bottom_nav.dart';
import '../../../core/widgets/zad_empty_state.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_nested_swipe_scope.dart';
import '../../../services/auth_service.dart';
import '../data/team_service.dart';
import '../domain/team_models.dart';

const _cardBorder = Color(0xFFF2E0CC);

class TeamsScreen extends StatefulWidget {
  final AuthService authService;

  /// Injectable for widget tests (same pattern as AdminScreen/BudgetScreen);
  /// production always uses the default [TeamService].
  final TeamService? service;

  const TeamsScreen({super.key, required this.authService, this.service});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  late final TeamService _svc;
  List<TeamSummary> _mine = [];
  List<TeamSummary> _public = [];
  bool _loading = true;
  String? _error;

  late final PageController _pageController;
  int _teamPage = 0;

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? TeamService(widget.authService);
    _pageController = PageController();
    _pageController.addListener(_onPageChanged);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PageControllerRegistration(_pageController).dispatch(context);
      }
    });
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page ?? 0;
    setState(() => _teamPage = page.round());
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
      appBar: AppBar(
        title: const Text('الفرق'),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const ZadBottomNav(current: ZadTab.teams),
      floatingActionButton: _teamPage == 0
          ? FloatingActionButton(
              backgroundColor: ZadTokens.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onPressed: () => context.push('/teams/new').then((_) => _load()),
              child: const Icon(Icons.add),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
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
                borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
              ),
              child: Row(
                children: [
                  _tab('فرقي', _teamPage == 0, () {
                    _pageController.animateToPage(
                      0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                    );
                  }),
                  _tab('الفرق العامة', _teamPage == 1, () {
                    _pageController.animateToPage(
                      1,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                    );
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
                child: PageView(
                  controller: _pageController,
                  scrollDirection: Axis.horizontal,
                  children: [
                    RefreshIndicator(
                      onRefresh: _load,
                      child: _buildList(isMine: true),
                    ),
                    RefreshIndicator(
                      onRefresh: _load,
                      child: _buildList(isMine: false),
                    ),
                  ],
                ),
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
          color: selected ? ZadTokens.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(ZadTokens.radiusSm + 2),
          boxShadow: selected ? ZadTokens.cardShadow : null,
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

  Widget _buildList({required bool isMine}) {
    final items = isMine ? _mine : _public;
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
                  icon: isMine ? Icons.group_outlined : Icons.public_off,
                  message: isMine ? 'لا توجد فرق بعد' : 'لا توجد فرق عامة',
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
    return Padding(
      padding: const EdgeInsets.only(bottom: ZadTokens.s3),
      child: Material(
        color: ZadTokens.surface,
        elevation: 1,
        shadowColor: const Color(0x14000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
          side: const BorderSide(color: _cardBorder),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
          child: Padding(
            padding: const EdgeInsets.all(ZadTokens.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            team.name,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              color: ZadTokens.text,
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
                              if (team.myRole == 'leader')
                                const ZadBadge('قائد')
                              else if (team.myRole != null)
                                const ZadBadge('عضو'),
                              ZadBadge(team.isPublic ? 'عام' : 'خاص'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: ZadTokens.s3),
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ZadTokens.surfaceContainer,
                        borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
                      ),
                      child: Icon(
                        team.isPublic ? Icons.groups : Icons.lock_outline,
                        size: 26,
                        color: ZadTokens.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZadTokens.s3),
                const Divider(height: 1, color: _cardBorder),
                const SizedBox(height: ZadTokens.s3),
                Row(
                  children: [
                    const Icon(
                      Icons.groups_outlined,
                      size: 18,
                      color: ZadTokens.textMuted,
                    ),
                    const SizedBox(width: ZadTokens.s1 + 2),
                    Text(
                      '${team.memberCount} عضو',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ZadTokens.textMuted,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.chevron_left,
                      size: 20,
                      color: ZadTokens.textMuted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
