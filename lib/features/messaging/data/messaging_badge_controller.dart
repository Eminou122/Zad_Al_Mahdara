import 'package:flutter/foundation.dart';
import '../domain/team_messaging_models.dart';
import 'team_messaging_service.dart';

/// Shell-wide messaging unread state, shared via [ZadMessagingBadgeScope] —
/// same pattern as [NotificationBadgeController]/[ZadNotificationBadgeScope],
/// kept as a separate controller/scope so the two badges never merge into
/// one number.
class MessagingBadgeController extends ChangeNotifier {
  final TeamMessagingService _service;
  MessagingUnreadCount _count = MessagingUnreadCount.zero;

  MessagingBadgeController(this._service);

  int get privateMessageUnreadCount => _count.privateMessageUnreadCount;
  int get announcementUnreadCount => _count.announcementUnreadCount;
  int get totalUnreadCount => _count.totalUnreadCount;

  void setCount(MessagingUnreadCount count) {
    if (_count.privateMessageUnreadCount == count.privateMessageUnreadCount &&
        _count.announcementUnreadCount == count.announcementUnreadCount &&
        _count.totalUnreadCount == count.totalUnreadCount) {
      return;
    }
    _count = count;
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      final count = await _service.getMessagingUnreadCount();
      setCount(count);
    } catch (_) {
      // Best-effort; keep the last known count on failure.
    }
  }

  void reset() => setCount(MessagingUnreadCount.zero);
}
