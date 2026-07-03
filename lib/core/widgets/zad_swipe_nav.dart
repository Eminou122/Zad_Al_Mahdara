import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Wraps a bottom-nav root-tab screen with horizontal swipe-to-switch-tab.
/// Only ever built for the 5 main sections (see AppRouter) — detail/form
/// routes never get this wrapper, so they never pick up the gesture.
class ZadSwipeNav extends StatefulWidget {
  final Widget child;
  final List<String> routes;
  final int index; // this tab's position in [routes]; -1 = not a known tab.

  const ZadSwipeNav({
    super.key,
    required this.child,
    required this.routes,
    required this.index,
  });

  // Distance/velocity thresholds so an incidental diagonal scroll doesn't
  // fire a tab change — one of these two must be clearly exceeded.
  static const _minDistance = 60.0;
  static const _minVelocity = 300.0;

  /// Pure swipe-resolution logic, split out so it's unit-testable without
  /// simulating real drag gestures. Returns the tab index to navigate to, or
  /// null if the gesture doesn't clear the threshold or would go out of
  /// bounds (e.g. swiping past the first/last tab).
  ///
  /// Swipe right (positive signal) -> next tab, which sits visually to the
  /// left in this RTL nav strip; swipe left (negative) -> previous tab,
  /// visually to the right. See app_router.dart's _mainPage for the matching
  /// transition-direction convention.
  static int? targetIndex({
    required int index,
    required double dragDistance,
    required double velocity,
    required int routesLength,
  }) {
    final signal = velocity.abs() >= _minVelocity ? velocity : dragDistance;
    if (signal.abs() < _minDistance && velocity.abs() < _minVelocity) {
      return null;
    }
    final target = index + (signal > 0 ? 1 : -1);
    if (target < 0 || target >= routesLength) return null;
    return target;
  }

  @override
  State<ZadSwipeNav> createState() => _ZadSwipeNavState();
}

class _ZadSwipeNavState extends State<ZadSwipeNav> {
  double _dragDistance = 0;
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    if (widget.index == -1) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        _dragDistance = 0;
        _handled = false;
      },
      onHorizontalDragUpdate: (details) {
        _dragDistance += details.primaryDelta ?? 0;
      },
      onHorizontalDragEnd: (details) {
        if (_handled) return;
        final target = ZadSwipeNav.targetIndex(
          index: widget.index,
          dragDistance: _dragDistance,
          velocity: details.primaryVelocity ?? 0,
          routesLength: widget.routes.length,
        );
        if (target == null) return;
        _handled = true;
        context.go(widget.routes[target]);
      },
      child: widget.child,
    );
  }
}
