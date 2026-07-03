import 'package:flutter/widgets.dart';
import '../../services/auth_service.dart';

/// Exposes the app's [AuthService] to shell widgets (e.g. the bottom nav's
/// admin-only tab) without threading flags through every screen constructor.
/// Rebuilds dependents when the session changes (login/logout/role load).
class ZadSessionScope extends InheritedNotifier<AuthService> {
  const ZadSessionScope({
    super.key,
    required AuthService authService,
    required super.child,
  }) : super(notifier: authService);

  static AuthService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ZadSessionScope>()?.notifier;
}
