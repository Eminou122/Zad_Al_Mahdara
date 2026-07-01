import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

  late final GoRouter router = GoRouter(
    refreshListenable: authService,
    redirect: _guard,
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => LoginScreen(authService: authService)),
      GoRoute(path: '/register', builder: (_, _) => RegisterScreen(authService: authService)),
      GoRoute(path: '/forgot-pin', builder: (_, _) => const ForgotPinScreen()),
      GoRoute(path: '/home', builder: (_, _) => HomeScreen(authService: authService)),
      GoRoute(path: '/budget', builder: (_, _) => BudgetScreen(authService: authService)),
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
      GoRoute(path: '/teams', builder: (_, _) => TeamsScreen(authService: authService)),
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
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
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
