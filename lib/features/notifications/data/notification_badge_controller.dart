import 'package:flutter/foundation.dart';
import '../../../core/refresh/app_refresh_coordinator.dart';
import 'notification_service.dart';

/// Shell-wide unread-notification count, shared via [ZadNotificationBadgeScope]
/// so the bottom nav badge and the notifications screen stay in sync without
/// a realtime subscription — every mutation that changes the count (mark
/// read, mark all read, archive, a fresh page load) already knows the new
/// value and pushes it here directly instead of triggering a refetch.
class NotificationBadgeController extends ChangeNotifier {
  final NotificationService _service;
  int _unreadCount = 0;

  NotificationBadgeController(this._service);

  int get unreadCount => _unreadCount;

  void setCount(int count, {bool markNotificationsDirtyOnIncrease = true}) {
    if (_unreadCount == count) return;
    final increased = count > _unreadCount;
    _unreadCount = count;
    notifyListeners();
    if (increased && markNotificationsDirtyOnIncrease) {
      AppRefreshCoordinator.instance.markDirty(AppRefreshScope.notifications);
    }
  }

  Future<void> refresh() async {
    try {
      final count = await _service.getUnreadCount();
      setCount(count);
    } catch (_) {
      // Best-effort; keep the last known count on failure.
    }
  }

  void reset() => setCount(0);
}
