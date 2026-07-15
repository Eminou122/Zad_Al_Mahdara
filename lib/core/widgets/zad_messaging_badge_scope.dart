import 'package:flutter/widgets.dart';
import '../../features/messaging/data/messaging_badge_controller.dart';

/// Exposes the shell's [MessagingBadgeController] to the bottom nav badge
/// without threading it through every screen constructor — same pattern as
/// [ZadNotificationBadgeScope], kept separate so the two unread counts
/// never visually merge.
class ZadMessagingBadgeScope
    extends InheritedNotifier<MessagingBadgeController> {
  const ZadMessagingBadgeScope({
    super.key,
    required MessagingBadgeController controller,
    required super.child,
  }) : super(notifier: controller);

  static MessagingBadgeController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ZadMessagingBadgeScope>()
      ?.notifier;
}
