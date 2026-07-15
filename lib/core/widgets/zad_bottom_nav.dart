import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/zad_tokens.dart';
import 'zad_messaging_badge_scope.dart';
import 'zad_notification_badge_scope.dart';
import 'zad_session_scope.dart';

/// The root tabs of the Stitch app shell. الإدارة appears only for admins.
enum ZadTab { home, budget, teams, messages, notifications, admin }

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
      '/messages' => ZadTab.messages,
      '/notifications' => ZadTab.notifications,
      '/admin' => ZadTab.admin,
      _ => null,
    };
    return tab == null ? null : ZadBottomNav(current: tab);
  }

  /// Root tabs never show a back arrow (Stitch top bar).
  static bool isRootTab(String location) => switch (location) {
    '/home' ||
    '/budget' ||
    '/teams' ||
    '/messages' ||
    '/notifications' ||
    '/admin' => true,
    _ => false,
  };

  /// Root-tab routes in visual right-to-left order (matches [_userItems] /
  /// [_adminItems] below) — shared source of truth for swipe/transition
  /// direction, so tab order never drifts out of sync with the nav itself.
  static List<String> routesFor(bool isAdmin) =>
      (isAdmin ? _adminItems : _userItems).map((t) => t.$5).toList();

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
  static const _messages = (
    ZadTab.messages,
    Icons.mail_outline,
    Icons.mail,
    'الرسائل',
    '/messages',
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
  // Normal users (5 tabs): الرئيسية at the far right, then الميزانية،
  // الفرق، الرسائل، التنبيهات reading right→left.
  static const _userItems = [_home, _budget, _teams, _messages, _notifications];
  // Admins (6 tabs): الرئيسية still near-centered — right→left reads
  // الميزانية، الفرق، الرئيسية، الرسائل، التنبيهات، الإدارة (admin at far
  // left edge).
  static const _adminItems = [
    _budget,
    _teams,
    _home,
    _messages,
    _notifications,
    _admin,
  ];

  @override
  Widget build(BuildContext context) {
    final isAdmin = ZadSessionScope.maybeOf(context)?.isAdmin ?? false;
    final unreadCount =
        ZadNotificationBadgeScope.maybeOf(context)?.unreadCount ?? 0;
    final messagingUnreadCount =
        ZadMessagingBadgeScope.maybeOf(context)?.totalUnreadCount ?? 0;
    final items = isAdmin ? _adminItems : _userItems;
    // 5+ tabs need slightly smaller icons/labels to stay safe at 320px.
    final compact = items.length >= 5;
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
                    badgeCount: switch (tab) {
                      ZadTab.notifications => unreadCount,
                      ZadTab.messages => messagingUnreadCount,
                      _ => 0,
                    },
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
  final int badgeCount;
  final VoidCallback? onTap;

  const _NavItem({
    required this.active,
    required this.compact,
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badgeCount = 0,
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
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    active ? activeIcon : icon,
                    size: compact ? 20 : 22,
                    color: color,
                  ),
                  if (badgeCount > 0)
                    PositionedDirectional(
                      top: -4,
                      end: -8,
                      child: _UnreadBadge(count: badgeCount, onDark: active),
                    ),
                ],
              ),
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

/// Small pill on the notifications tab icon. Exact count 1-99, "99+"
/// beyond that; never shown at zero (caller already guards on badgeCount > 0).
class _UnreadBadge extends StatelessWidget {
  final int count;
  final bool onDark;
  const _UnreadBadge({required this.count, required this.onDark});

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ZadTokens.danger,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: onDark ? ZadTokens.primary : ZadTokens.surface,
          width: 1.5,
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}
