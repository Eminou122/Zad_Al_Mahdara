import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/zad_tokens.dart';
import 'zad_session_scope.dart';

/// The root tabs of the Stitch app shell. الإدارة appears only for admins.
enum ZadTab { home, budget, teams, notifications, admin }

/// Stitch-style fixed bottom navigation: cream surface with rounded top
/// corners, active tab as a deep-green pill (white filled icon + label),
/// inactive tabs as muted outlined icons with Arabic labels.
///
/// Navigation uses `context.go` (location replacement), so the browser/
/// Android back stack and hash routes keep working unchanged.
class ZadBottomNav extends StatelessWidget {
  final ZadTab? current;
  const ZadBottomNav({super.key, this.current});

  /// Shell mapping: which locations show the nav and with which active tab.
  /// Returns null for locations without a nav (auth pages, form screens —
  /// Stitch add_member shows no bottom nav, forms keep their bottom buttons).
  static ZadBottomNav? forLocation(String location) {
    final tab = switch (location) {
      '/home' => ZadTab.home,
      '/budget' || '/budget/recurring' => ZadTab.budget,
      '/teams' => ZadTab.teams,
      '/notifications' => ZadTab.notifications,
      '/admin' => ZadTab.admin,
      _ => null,
    };
    return tab == null ? null : ZadBottomNav(current: tab);
  }

  /// Root tabs never show a back arrow (Stitch top bar).
  static bool isRootTab(String location) => switch (location) {
    '/home' || '/budget' || '/teams' || '/notifications' || '/admin' => true,
    _ => false,
  };

  // (tab, inactive icon, active filled icon, label, route).
  static const _home = (
    ZadTab.home,
    Icons.home_outlined,
    Icons.home,
    'الرئيسية',
    '/home',
  );
  static const _budget = (
    ZadTab.budget,
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet,
    'الميزانية',
    '/budget',
  );
  static const _teams = (
    ZadTab.teams,
    Icons.groups_outlined,
    Icons.groups,
    'الفرق',
    '/teams',
  );
  static const _notifications = (
    ZadTab.notifications,
    Icons.notifications_outlined,
    Icons.notifications,
    'التنبيهات',
    '/notifications',
  );
  static const _admin = (
    ZadTab.admin,
    Icons.admin_panel_settings_outlined,
    Icons.admin_panel_settings,
    'الإدارة',
    '/admin',
  );

  // In this RTL Row the first child lands at the RIGHT edge.
  // Normal users (4 tabs): الرئيسية at the far right, then الميزانية،
  // الفرق، التنبيهات reading right→left.
  static const _userItems = [_home, _budget, _teams, _notifications];
  // Admins (5 tabs): الرئيسية exactly centered — right→left reads
  // الميزانية، الفرق، الرئيسية، التنبيهات، الإدارة (admin at far left edge).
  static const _adminItems = [_budget, _teams, _home, _notifications, _admin];

  @override
  Widget build(BuildContext context) {
    final isAdmin = ZadSessionScope.maybeOf(context)?.isAdmin ?? false;
    final items = isAdmin ? _adminItems : _userItems;
    // 5 tabs need slightly smaller icons/labels to stay safe at 320px.
    final compact = items.length == 5;
    return Material(
      color: ZadTokens.surface,
      elevation: 10,
      shadowColor: const Color(0x33000000),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ZadTokens.radiusMd),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZadTokens.s2,
            vertical: ZadTokens.s2,
          ),
          child: Row(
            children: [
              for (final (tab, icon, activeIcon, label, route) in items)
                Expanded(
                  child: _NavItem(
                    active: tab == current,
                    compact: compact,
                    icon: icon,
                    activeIcon: activeIcon,
                    label: label,
                    onTap: tab == current ? null : () => context.go(route),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final bool active;
  final bool compact;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final VoidCallback? onTap;

  const _NavItem({
    required this.active,
    required this.compact,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : ZadTokens.textMuted;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 2 : ZadTokens.s1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: ZadTokens.s1 + 2),
          decoration: active
              ? BoxDecoration(
                  color: ZadTokens.primary,
                  borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(active ? activeIcon : icon, size: compact ? 20 : 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 10 : 11,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
