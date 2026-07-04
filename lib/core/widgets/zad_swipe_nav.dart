import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'zad_bottom_nav.dart';
import 'zad_nested_swipe_scope.dart';
import 'zad_session_scope.dart';
import '../theme/zad_tokens.dart';

/// Wraps a bottom-nav root-tab screen with horizontal swipe-to-switch-tab.
/// Uses raw [Listener] (no arena competition with child scrollables).
/// During drag the page follows the finger via transform.
/// Child sections (e.g. Teams with PageView) register their PageController
/// via [PageControllerRegistration] so root defers navigation when the
/// child consumes the gesture internally.
class ZadSwipeNav extends StatefulWidget {
  final Widget child;
  final List<String> routes;
  final int index;

  const ZadSwipeNav({
    super.key,
    required this.child,
    required this.routes,
    required this.index,
  });

  static const _minDistance = 60.0;
  static const _minVelocity = 300.0;

  /// Pure swipe-resolution logic, unit-testable.
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

class _ZadSwipeNavState extends State<ZadSwipeNav>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  bool _handled = false;
  bool _isDragging = false;

  // Velocity tracking
  final _recent = <_Sample>[];
  static const _maxSampleAge = Duration(milliseconds: 120);

  // Child PageController tracking
  PageController? _childPc;
  double? _childPageAtDown;

  // Cancel animation
  late AnimationController _cancelCtrl;
  double _cancelFrom = 0;

  @override
  void initState() {
    super.initState();
    _cancelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (!mounted) return;
        setState(() {
          _dragOffset = _cancelFrom * (1.0 - _cancelCtrl.value);
        });
      });
  }

  @override
  void dispose() {
    _cancelCtrl.dispose();
    super.dispose();
  }

  double _velocity() {
    if (_recent.isEmpty) return 0;
    final now = DateTime.now();
    _recent.removeWhere((s) => now.difference(s.at).abs() > _maxSampleAge);
    if (_recent.isEmpty) return 0;
    final totalDx = _recent.fold<double>(0, (s, e) => s + e.dx);
    return totalDx / (_maxSampleAge.inMilliseconds / 1000.0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.index == -1) return widget.child;

    final isAdmin = ZadSessionScope.maybeOf(context)?.isAdmin ?? false;
    final allRoutes = ZadBottomNav.routesFor(isAdmin);

    // Neighbor label to show during drag
    String? neighborLabel;
    if (_dragOffset.abs() > 20 && !_cancelCtrl.isAnimating) {
      final dir = _dragOffset > 0 ? 1 : -1;
      final ni = widget.index + dir;
      if (ni >= 0 && ni < allRoutes.length) {
        neighborLabel = switch (allRoutes[ni]) {
          '/home' => 'الرئيسية',
          '/budget' => 'الميزانية',
          '/teams' => 'الفرق',
          '/notifications' => 'التنبيهات',
          '/admin' => 'الإدارة',
          _ => null,
        };
      }
    }

    final showNeighbor = neighborLabel != null;
    final neighborOnLeft = _dragOffset > 0;

    return NotificationListener<PageControllerRegistration>(
      onNotification: (n) {
        _childPc = n.controller;
        return true;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: (_) => _cancelDrag(),
        child: Stack(
          children: [
            // Neighbor preview
            if (showNeighbor)
              Positioned.fill(
                left: neighborOnLeft ? 0 : null,
                right: neighborOnLeft ? null : 0,
                child: IgnorePointer(
                  child: Container(
                    width: _dragOffset.abs().clamp(0, 120),
                    color: ZadTokens.surfaceContainer,
                    alignment: neighborOnLeft
                        ? AlignmentDirectional.centerStart
                        : AlignmentDirectional.centerEnd,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      neighborLabel,
                      style: const TextStyle(
                        color: ZadTokens.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            // Current page
            AnimatedBuilder(
              animation: _cancelCtrl,
              builder: (context, _) {
                return Transform.translate(
                  offset: Offset(_dragOffset, 0),
                  child: widget.child,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _onDown(PointerDownEvent event) {
    _cancelCtrl.stop();
    _dragOffset = 0;
    _handled = false;
    _isDragging = true;
    _recent.clear();
    _childPageAtDown = _childPc?.page;
  }

  void _onMove(PointerMoveEvent event) {
    if (_handled) return;
    setState(() {
      _dragOffset += event.delta.dx;
    });
    _recent.add(_Sample(event.delta.dx, DateTime.now()));
  }

  void _onUp(PointerUpEvent event) {
    if (!_isDragging || _handled) return;
    _isDragging = false;

    // Check if a child PageView consumed the gesture
    final pc = _childPc;
    final double consumed;
    if (pc != null && pc.hasClients) {
      final pageNow = pc.page;
      consumed = (_childPageAtDown != null && pageNow != null)
          ? (pageNow - _childPageAtDown!).abs()
          : 0;
    } else {
      consumed = 0;
    }

    // If the child page changed, the gesture was consumed internally
    if (consumed > 0.01) {
      _animateBack();
      return;
    }

    final target = ZadSwipeNav.targetIndex(
      index: widget.index,
      dragDistance: _dragOffset,
      velocity: _velocity(),
      routesLength: widget.routes.length,
    );
    if (target != null && target >= 0 && target < widget.routes.length) {
      _handled = true;
      context.go(widget.routes[target]);
    } else {
      _animateBack();
    }
  }

  void _cancelDrag() {
    _isDragging = false;
    _animateBack();
  }

  void _animateBack() {
    if (_dragOffset == 0) return;
    _cancelFrom = _dragOffset;
    _cancelCtrl.forward(from: 0);
  }
}

class _Sample {
  final double dx;
  final DateTime at;
  _Sample(this.dx, this.at);
}
