import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'route_observer.dart';
import '../widgets/zad_bottom_nav.dart';
import '../widgets/zad_swipe_nav.dart';
import '../../services/auth_service.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/forgot_pin_screen.dart';
import '../../features/auth/presentation/reset_pin_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/budget/presentation/budget_screen.dart';
import '../../features/budget/presentation/budget_plan_form_screen.dart';
import '../../features/budget/presentation/expense_form_screen.dart';
import '../../features/budget/presentation/subscription_form_screen.dart';
import '../../features/budget/presentation/recurring_purchases_screen.dart';
import '../../features/budget/presentation/recurring_purchase_history_screen.dart';
import '../../features/budget/presentation/recurring_purchase_form_screen.dart';
import '../../features/budget/domain/budget_models.dart';
import '../../features/teams/presentation/teams_screen.dart';
import '../../features/teams/presentation/team_form_screen.dart';
import '../../features/teams/presentation/team_detail_screen.dart';
import '../../features/teams/presentation/add_team_member_screen.dart';
import '../../features/teams/domain/team_models.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/admin/presentation/admin_screen.dart';
import '../../features/account/presentation/account_screen.dart';
import '../../features/directory/presentation/student_directory_screen.dart';
import '../../features/messaging/presentation/messaging_home_screen.dart';
import '../../features/messaging/presentation/team_conversation_screen.dart';
import '../../features/messaging/presentation/team_announcements_screen.dart';
import '../../features/messaging/presentation/compose_team_announcement_screen.dart';

class AppRouter {
  final AuthService authService;
  AppRouter(this.authService);

  static const _authPaths = {
    '/login',
    '/register',
    '/forgot-pin',
    '/reset-pin',
    '/',
  };

  /// Builds the real screen for a root route — used by [ZadSwipeNav] to
  /// populate its persistent per-route screen cache (each screen is built
  /// once per session and kept alive, so tab switches never re-fetch).
  Widget _buildMainScreen(String route) {
    return switch (route) {
      '/home' => HomeScreen(authService: authService),
      '/budget' => BudgetScreen(authService: authService),
      '/teams' => TeamsScreen(authService: authService),
      '/messages' => MessagingHomeScreen(authService: authService),
      '/notifications' => NotificationsScreen(authService: authService),
      '/admin' => AdminScreen(authService: authService),
      _ => const SizedBox.shrink(),
    };
  }

  /// Shared page for the bottom-nav root tabs. All five use one page key,
  /// so switching tabs updates this page IN PLACE instead of replacing the
  /// route — ZadSwipeNav's State (and every root screen cached inside it)
  /// survives the switch, which is what prevents re-mount/re-fetch on
  /// every swipe or tab tap. Tab-to-tab motion is animated by ZadSwipeNav
  /// itself (the filmstrip, for both swipes and taps); the fade below only
  /// plays when entering the shell from a non-tab page (login/splash/
  /// account), so a gesture-driven commit never gets a second transition.
  Page<void> _mainPage(GoRouterState state, Widget child) {
    final routes = ZadBottomNav.routesFor(authService.isAdmin);
    final index = routes.indexOf(state.matchedLocation);
    return CustomTransitionPage<void>(
      key: const ValueKey('zad-root-shell'),
      child: ZadSwipeNav(
        routes: routes,
        index: index,
        screenBuilder: _buildMainScreen,
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  late final GoRouter router = GoRouter(
    refreshListenable: authService,
    redirect: _guard,
    initialLocation: kIsWeb && Uri.base.fragment.isNotEmpty
        ? Uri.base.fragment
        : '/',
    observers: [appRouteObserver],
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: '/login',
        builder: (_, _) => LoginScreen(authService: authService),
      ),
      GoRoute(
        path: '/register',
        builder: (_, _) => RegisterScreen(authService: authService),
      ),
      GoRoute(
        path: '/forgot-pin',
        builder: (_, _) => ForgotPinScreen(authService: authService),
      ),
      GoRoute(
        path: '/reset-pin',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is! Map ||
              extra['phone'] is! String ||
              extra['request'] is! PinResetRequest) {
            return ForgotPinScreen(authService: authService);
          }
          return ResetPinScreen(
            authService: authService,
            phone: extra['phone'] as String,
            request: extra['request'] as PinResetRequest,
          );
        },
      ),
      GoRoute(
        path: '/home',
        pageBuilder: (_, state) =>
            _mainPage(state, HomeScreen(authService: authService)),
      ),
      GoRoute(
        path: '/budget',
        pageBuilder: (_, state) =>
            _mainPage(state, BudgetScreen(authService: authService)),
      ),
      GoRoute(
        path: '/budget/setup',
        builder: (_, state) => BudgetPlanFormScreen(
          authService: authService,
          existingPlan: state.extra as BudgetPlan?,
        ),
      ),
      GoRoute(
        path: '/budget/expense/new',
        builder: (_, state) => ExpenseFormScreen(
          authService: authService,
          existingExpense: state.extra as Expense?,
        ),
      ),
      GoRoute(
        path: '/budget/subscription/new',
        builder: (_, state) => SubscriptionFormScreen(
          authService: authService,
          existingSub: state.extra as AppSubscription?,
        ),
      ),
      GoRoute(
        path: '/budget/recurring',
        builder: (_, _) => RecurringPurchasesScreen(authService: authService),
      ),
      GoRoute(
        path: '/budget/recurring/new',
        builder: (_, state) => RecurringPurchaseFormScreen(
          authService: authService,
          existing: state.extra as RecurringPurchase?,
        ),
      ),
      GoRoute(
        path: '/budget/recurring/history',
        builder: (_, _) =>
            RecurringPurchaseHistoryScreen(authService: authService),
      ),
      GoRoute(
        path: '/teams',
        pageBuilder: (_, state) =>
            _mainPage(state, TeamsScreen(authService: authService)),
      ),
      GoRoute(
        path: '/teams/new',
        builder: (_, _) => TeamFormScreen(authService: authService),
      ),
      GoRoute(
        path: '/teams/:id',
        builder: (_, state) => TeamDetailScreen(
          authService: authService,
          teamId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/teams/:id/edit',
        builder: (_, state) => TeamFormScreen(
          authService: authService,
          teamId: state.pathParameters['id']!,
          existing: state.extra as TeamInfo?,
        ),
      ),
      GoRoute(
        path: '/teams/:id/add-member',
        builder: (_, state) => AddTeamMemberScreen(
          authService: authService,
          teamId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/directory',
        builder: (_, _) => StudentDirectoryScreen(authService: authService),
      ),
      GoRoute(
        path: '/messages',
        pageBuilder: (_, state) =>
            _mainPage(state, MessagingHomeScreen(authService: authService)),
      ),
      GoRoute(
        path: '/messages/conversation/:conversationId',
        builder: (_, state) {
          final conversationId = state.pathParameters['conversationId'];
          if (conversationId == null || conversationId.isEmpty) {
            return const Scaffold(
              body: Center(child: Text('تعذر فتح المحادثة')),
            );
          }
          final extra = state.extra;
          final hints = extra is Map ? Map<String, dynamic>.from(extra) : null;
          return TeamConversationScreen(
            authService: authService,
            conversationId: conversationId,
            teamId: hints?['teamId'] as String?,
            teamName: hints?['teamName'] as String?,
            otherPartyName: hints?['otherPartyName'] as String?,
            currentUserRole: hints?['currentUserRole'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/teams/:id/announcements',
        builder: (_, state) {
          final teamId = state.pathParameters['id'];
          if (teamId == null || teamId.isEmpty) {
            return const Scaffold(
              body: Center(child: Text('تعذر فتح الإعلانات')),
            );
          }
          final extra = state.extra;
          final hints = extra is Map ? Map<String, dynamic>.from(extra) : null;
          return TeamAnnouncementsScreen(
            authService: authService,
            teamId: teamId,
            teamName: hints?['teamName'] as String?,
            isLeader: hints?['isLeader'] as bool? ?? false,
            focusAnnouncementId: hints?['announcementId'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/teams/:id/announcements/new',
        builder: (_, state) {
          final teamId = state.pathParameters['id'];
          if (teamId == null || teamId.isEmpty) {
            return const Scaffold(
              body: Center(child: Text('تعذر فتح الإعلانات')),
            );
          }
          return ComposeTeamAnnouncementScreen(
            authService: authService,
            teamId: teamId,
            teamName: state.extra as String?,
          );
        },
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (_, state) =>
            _mainPage(state, NotificationsScreen(authService: authService)),
      ),
      GoRoute(
        path: '/admin',
        pageBuilder: (_, state) =>
            _mainPage(state, AdminScreen(authService: authService)),
      ),
      GoRoute(
        path: '/account',
        builder: (_, _) => AccountScreen(authService: authService),
      ),
    ],
  );

  String? _guard(BuildContext context, GoRouterState state) {
    if (authService.isLoadingSession) return null;
    final loggedIn = authService.isAuthenticated;
    final loc = state.matchedLocation;

    if (!loggedIn && !_authPaths.contains(loc)) return '/login';
    if (loggedIn && _authPaths.contains(loc)) return '/home';
    if (loggedIn && loc == '/admin' && !authService.isAdmin) return '/home';
    return null;
  }
}
