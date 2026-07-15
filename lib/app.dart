import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/zad_messaging_badge_scope.dart';
import 'core/widgets/zad_notification_badge_scope.dart';
import 'core/widgets/zad_session_scope.dart';
import 'features/messaging/data/messaging_badge_controller.dart';
import 'features/messaging/data/messaging_presence_controller.dart';
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
  late final MessagingPresenceController _presenceController;

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
    _presenceController = MessagingPresenceController(
      widget.authService,
      TeamMessagingService(widget.authService),
    );
    widget.authService.addListener(_onAuthChanged);
    WidgetsBinding.instance.addObserver(this);
    if (widget.authService.isAuthenticated) {
      _badgeController.refresh();
      _messagingBadgeController.refresh();
      _presenceController.start();
    }
  }

  void _onAuthChanged() {
    if (widget.authService.isAuthenticated) {
      _badgeController.refresh();
      _messagingBadgeController.refresh();
      _presenceController.start();
    } else {
      _badgeController.reset();
      _messagingBadgeController.reset();
      _presenceController.reset();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.authService.isAuthenticated) {
      _badgeController.refresh();
      _messagingBadgeController.refresh();
      _presenceController.resume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _presenceController.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.authService.removeListener(_onAuthChanged);
    _presenceController.dispose();
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
