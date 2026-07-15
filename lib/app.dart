import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/zad_messaging_badge_scope.dart';
import 'core/widgets/zad_notification_badge_scope.dart';
import 'core/widgets/zad_session_scope.dart';
import 'features/messaging/data/messaging_badge_controller.dart';
import 'features/messaging/data/team_messaging_service.dart';
import 'features/notifications/data/notification_badge_controller.dart';
import 'features/notifications/data/notification_service.dart';
import 'services/auth_service.dart';

class ZadApp extends StatefulWidget {
  final AuthService authService;
  const ZadApp({super.key, required this.authService});

  @override
  State<ZadApp> createState() => _ZadAppState();
}

class _ZadAppState extends State<ZadApp> with WidgetsBindingObserver {
  late final GoRouter _router;
  late final NotificationBadgeController _badgeController;
  late final MessagingBadgeController _messagingBadgeController;

  @override
  void initState() {
    super.initState();
    _router = AppRouter(widget.authService).router;
    _badgeController = NotificationBadgeController(
      NotificationService(widget.authService),
    );
    _messagingBadgeController = MessagingBadgeController(
      TeamMessagingService(widget.authService),
    );
    widget.authService.addListener(_onAuthChanged);
    WidgetsBinding.instance.addObserver(this);
    if (widget.authService.isAuthenticated) {
      _badgeController.refresh();
      _messagingBadgeController.refresh();
    }
  }

  void _onAuthChanged() {
    if (widget.authService.isAuthenticated) {
      _badgeController.refresh();
      _messagingBadgeController.refresh();
    } else {
      _badgeController.reset();
      _messagingBadgeController.reset();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.authService.isAuthenticated) {
      _badgeController.refresh();
      _messagingBadgeController.refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.authService.removeListener(_onAuthChanged);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'زاد المحظرة',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: _router,
      // Session scope lets shell widgets (bottom nav) read admin state
      // without passing flags through every screen; the badge scope does
      // the same for the unread-notification count.
      builder: (context, child) => ZadSessionScope(
        authService: widget.authService,
        child: ZadNotificationBadgeScope(
          controller: _badgeController,
          child: ZadMessagingBadgeScope(
            controller: _messagingBadgeController,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
        ),
      ),
    );
  }
}
