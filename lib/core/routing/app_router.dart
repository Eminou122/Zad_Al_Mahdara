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
import '../../features/home/presentation/home_screen.dart';
import '../../features/budget/presentation/budget_screen.dart';
import '../../features/budget/presentation/budget_plan_form_screen.dart';
import '../../features/budget/presentation/expense_form_screen.dart';
import '../../features/budget/presentation/subscription_form_screen.dart';
import '../../features/budget/presentation/recurring_purchases_screen.dart';
import '../../features/budget/presentation/recurring_purchase_form_screen.dart';
import '../../features/budget/domain/budget_models.dart';
import '../../features/teams/presentation/teams_screen.dart';
import '../../features/teams/presentation/team_form_screen.dart';
import '../../features/teams/presentation/team_detail_screen.dart';
import '../../features/teams/presentation/add_team_member_screen.dart';
import '../../features/teams/domain/team_models.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/admin/presentation/admin_screen.dart';

class AppRouter {
  final AuthService authService;
  AppRouter(this.authService);

  static const _authPaths = {'/login', '/register', '/forgot-pin', '/'};

  // Previous main-tab index, so the transition direction reflects whether
  // the user is moving toward the start or end of the tab strip. Null until
  // the first main tab is shown, so the initial app load never slides.
  int? _lastMainIndex;

  /// Premium, subtle page transition for the 5 bottom-nav root tabs: a fast
  /// fade + small horizontal drift (not a full-width push — the bottom nav
  /// each screen carries stays visually put). Direction matches the tab's
  /// position in the (RTL-ordered) nav strip; see ZadSwipeNav for the same
  /// left/right convention used for swipe.
  Page<void> _mainPage(GoRouterState state, Widget child) {
    final path = state.matchedLocation;
    final routes = ZadBottomNav.routesFor(authService.isAdmin);
    final index = routes.indexOf(path);
    final previous = _lastMainIndex;
    final forward = (previous == null || index == -1 || previous == index)
        ? null // first load or unchanged index: fade only, no direction
        : index > previous;
    if (index != -1) _lastMainIndex = index;

    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: ZadSwipeNav(routes: routes, index: index, child: child),
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (forward == null || MediaQuery.of(context).disableAnimations) {
          return FadeTransition(opacity: animation, child: child);
        }
        // Target tab lives to the left when moving forward (higher index)
        // in this RTL strip, so it enters from the left, and vice versa.
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        final beginOffset = Offset(forward ? -0.045 : 0.045, 0);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.985, end: 1.0).animate(curved),
            child: SlideTransition(
              position: Tween(
                begin: beginOffset,
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          ),
        );
      },
    );
  }

  late final GoRouter router = GoRouter(
    refreshListenable: authService,
    redirect: _guard,
    initialLocation: '/',
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
      GoRoute(path: '/forgot-pin', builder: (_, _) => const ForgotPinScreen()),
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
        path: '/notifications',
        pageBuilder: (_, state) =>
            _mainPage(state, const NotificationsScreen()),
      ),
      GoRoute(
        path: '/admin',
        pageBuilder: (_, state) =>
            _mainPage(state, AdminScreen(authService: authService)),
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
