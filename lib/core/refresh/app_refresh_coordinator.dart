import 'dart:async';

import 'package:flutter/foundation.dart';

enum AppRefreshScope {
  notifications,
  messages,
  announcements,
  notificationBadge,
  messagingBadge,
}

typedef AppRefreshCallback = void Function(AppRefreshScope scope);
typedef RootRouteVisibleCallback = void Function(String route);
typedef AppForegroundCallback = void Function(bool foreground);

class AppRefreshCoordinator {
  AppRefreshCoordinator._();

  static final AppRefreshCoordinator instance = AppRefreshCoordinator._();

  final _listeners = <AppRefreshScope, Set<AppRefreshCallback>>{};
  final _routeListeners = <RootRouteVisibleCallback>{};
  final _foregroundListeners = <AppForegroundCallback>{};
  final _pendingScopes = <AppRefreshScope>{};
  String? _pendingRoute;
  bool? _pendingForeground;
  bool _flushScheduled = false;

  VoidCallback subscribe(AppRefreshScope scope, AppRefreshCallback callback) {
    (_listeners[scope] ??= <AppRefreshCallback>{}).add(callback);
    return () => _listeners[scope]?.remove(callback);
  }

  VoidCallback subscribeRootRouteVisible(RootRouteVisibleCallback callback) {
    _routeListeners.add(callback);
    return () => _routeListeners.remove(callback);
  }

  VoidCallback subscribeAppForeground(AppForegroundCallback callback) {
    _foregroundListeners.add(callback);
    return () => _foregroundListeners.remove(callback);
  }

  void invalidate(AppRefreshScope scope) => invalidateMany({scope});

  void invalidateMany(Iterable<AppRefreshScope> scopes) {
    _pendingScopes.addAll(scopes);
    _scheduleFlush();
  }

  void notifyRootRouteVisible(String route) {
    _pendingRoute = route;
    _scheduleFlush();
  }

  void notifyAppResumed() {
    _pendingForeground = true;
    invalidateMany({
      AppRefreshScope.notifications,
      AppRefreshScope.notificationBadge,
      AppRefreshScope.messages,
      AppRefreshScope.messagingBadge,
      AppRefreshScope.announcements,
    });
  }

  void notifyAppBackgrounded() {
    _pendingForeground = false;
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _flushScheduled = false;
    final route = _pendingRoute;
    final foreground = _pendingForeground;
    _pendingRoute = null;
    _pendingForeground = null;

    switch (route) {
      case '/notifications':
        _pendingScopes.addAll({
          AppRefreshScope.notifications,
          AppRefreshScope.notificationBadge,
        });
      case '/messages':
        _pendingScopes.addAll({
          AppRefreshScope.messages,
          AppRefreshScope.announcements,
          AppRefreshScope.messagingBadge,
        });
    }
    final scopes = Set<AppRefreshScope>.from(_pendingScopes);
    _pendingScopes.clear();

    if (route != null) {
      for (final callback in List<RootRouteVisibleCallback>.from(
        _routeListeners,
      )) {
        if (_routeListeners.contains(callback)) callback(route);
      }
    }

    if (foreground != null) {
      for (final callback in List<AppForegroundCallback>.from(
        _foregroundListeners,
      )) {
        if (_foregroundListeners.contains(callback)) callback(foreground);
      }
    }

    for (final scope in scopes) {
      final callbacks = _listeners[scope];
      if (callbacks == null) continue;
      for (final callback in List<AppRefreshCallback>.from(callbacks)) {
        if (callbacks.contains(callback)) callback(scope);
      }
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _listeners.clear();
    _routeListeners.clear();
    _foregroundListeners.clear();
    _pendingScopes.clear();
    _pendingRoute = null;
    _pendingForeground = null;
    _flushScheduled = false;
  }
}
