import 'package:flutter/widgets.dart';
import '../../features/notifications/data/notification_badge_controller.dart';

/// Exposes the shell's [NotificationBadgeController] to the bottom nav badge
/// without threading it through every screen constructor — same pattern as
/// [ZadSessionScope] for the admin flag.
class ZadNotificationBadgeScope
    extends InheritedNotifier<NotificationBadgeController> {
  const ZadNotificationBadgeScope({
    super.key,
    required NotificationBadgeController controller,
    required super.child,
  }) : super(notifier: controller);

  static NotificationBadgeController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ZadNotificationBadgeScope>()
          ?.notifier;
}
