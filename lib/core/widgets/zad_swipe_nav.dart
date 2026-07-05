import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'zad_bottom_nav.dart';
import 'zad_nested_swipe_scope.dart';
import 'zad_session_scope.dart';
import '../theme/zad_tokens.dart';

/// Wraps a bottom-nav root-tab screen with horizontal swipe-to-switch-tab.
///
/// Uses a raw [Listener] (not [GestureDetector]) to track pointer events
/// because Flutter's [HorizontalDragGestureRecognizer] accepts gestures
/// based on Euclidean distance (not horizontal-only displacement) and
/// zeroes out `dy` in [DragUpdateDetails.delta], making axis-lock
/// checking impossible inside its callbacks. A real root [PageView] was
/// considered (see Gate 29.7 report) but rejected: nesting it around a
/// section that itself owns a horizontal [PageView] (Teams) would put two
/// same-axis [Scrollable]s in the same gesture arena, which Flutter has no
/// clean built-in way to arbitrate — exactly the kind of low-level conflict
/// this gate is meant to remove, not relocate.
///
/// The listener applies per-event axis dominance checking: if the first
/// non-trivial move of a gesture is vertical-dominant, the entire
/// gesture is ignored.
///
/// Child sections register their [PageController] via
/// [PageControllerRegistration]. On the move that resolves axis-lock to
/// horizontal, root checks the child's current scroll boundary
/// ([ScrollMetrics.extentBefore]/[extentAfter] — generic, no Teams-specific
/// code) in the drag's direction: if the child still has room to move,
/// root stays completely inert for the rest of the gesture and the
/// pointer events reach the child's own [PageView] untouched. Root only
/// drives its own drag when the child is already at that boundary (or no
/// child is registered).
///
/// During a root-owned drag, the current section follows the finger via
/// [Transform.translate] and the actual neighboring root screen (built by
/// [screenBuilder], current + one neighbor only, and only while dragging)
/// is offset by `dragOffset ∓ screenWidth` — a real filmstrip position, so
/// its near edge touches the current page and it reaches `x = 0` exactly
/// when the drag reaches full screen width, like a gallery/photo carousel.
///
/// On release, a single [AnimationController] (`_settleCtrl`) drives both
/// pages together to their resting position: on cancel, back to
/// `dragOffset = 0`; on commit, all the way to `dragOffset = ±screenWidth`
/// (current fully off-screen, neighbor at `x = 0`) — only then is
/// `context.go()` called once, so the filmstrip finishes its slide before
/// GoRouter's own route transition takes over.
class ZadSwipeNav extends StatefulWidget {
  final Widget child;
  final List<String> routes;
  final int index;

  /// Sentinel passed as `extra` to [GoRouterHelper.go] when a committed
  /// swipe navigates, so the router can skip its own page transition —
  /// the filmstrip has already animated the change; playing a second
  /// fade/drift on top would create a visible seam.
  static const swipeCommitExtra = 'zad-swipe-commit';

  /// Builds the real screen for a root route, used to render the
  /// neighboring section during drag. Optional so unit/widget tests that
  /// don't care about the gallery preview can omit it (falls back to a
  /// lightweight icon+label placeholder).
  final Widget Function(String route)? screenBuilder;

  const ZadSwipeNav({
    super.key,
    required this.child,
    required this.routes,
    required this.index,
    this.screenBuilder,
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

class _Sample {
  final double dx;
  final Duration at;
  _Sample(this.dx, this.at);
}

class _ZadSwipeNavState extends State<ZadSwipeNav>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  bool _handled = false;

  // Listener trackers
  double _listenerTotalDx = 0;
  double _listenerTotalDy = 0;
  bool _gestureLive = false;

  // Velocity tracking
  final _recent = <_Sample>[];
  static const _maxSampleAge = Duration(milliseconds: 120);

  // Child PageController tracking
  PageController? _childPc;

  // Decided once per gesture, the move axis-lock resolves to horizontal:
  // true means the registered child still has room to move in this
  // drag's direction, so root stays inert and lets the child's own
  // PageView handle the whole gesture.
  bool _deferToChild = false;

  // Settle animation: drives _dragOffset from _settleFrom to _settleTo.
  // _settleTo == 0 for a cancel (snap back); _settleTo == ±screenWidth for
  // a commit (finish the filmstrip slide). _commitRoute is non-null only
  // for the commit case — context.go() fires once, on completion.
  late AnimationController _settleCtrl;
  double _settleFrom = 0;
  double _settleTo = 0;
  String? _commitRoute;

  @override
  void initState() {
    super.initState();
    _settleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )
      ..addListener(() {
        if (!mounted) return;
        setState(() {
          _dragOffset =
              _settleFrom + (_settleTo - _settleFrom) * _settleCtrl.value;
        });
      })
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        final route = _commitRoute;
        _commitRoute = null;
        if (route != null && mounted) {
          context.go(route, extra: ZadSwipeNav.swipeCommitExtra);
        }
      });
  }

  @override
  void dispose() {
    _settleCtrl.dispose();
    super.dispose();
  }

  /// Does the registered child [PageController] still have room to move
  /// further in the direction of [dx]? Generic scroll-boundary check
  /// (works for any child PageView, any page count — not Teams-specific).
  bool _childCanMove(double dx) {
    final pc = _childPc;
    if (pc == null || !pc.hasClients) return false;
    final pos = pc.position;
    // Positive dx (drag right) moves toward a higher page index — same
    // convention as ZadSwipeNav.targetIndex — so it needs room *after*;
    // negative dx (drag left) needs room *before*.
    if (dx > 0) return pos.extentAfter > 0;
    if (dx < 0) return pos.extentBefore > 0;
    return false;
  }

  // ── Listener callbacks ──

  void _onDown(PointerDownEvent event) {
    _settleCtrl.stop();
    _commitRoute = null;
    _dragOffset = 0;
    _handled = false;
    _gestureLive = false;
    _deferToChild = false;
    _listenerTotalDx = 0;
    _listenerTotalDy = 0;
    _recent.clear();
  }

  double _velocity() {
    if (_recent.isEmpty) return 0;
    final now = _recent.last.at;
    _recent.removeWhere((s) => (now - s.at).abs() > _maxSampleAge);
    if (_recent.isEmpty) return 0;
    final totalDx = _recent.fold<double>(0, (s, e) => s + e.dx);
    return totalDx / (_maxSampleAge.inMilliseconds / 1000.0);
  }

  void _onMove(PointerMoveEvent event) {
    if (_handled || _deferToChild) return;

    _listenerTotalDx += event.delta.dx;
    _listenerTotalDy += event.delta.dy.abs();

    // First move: accept only if the gesture is horizontal-dominant
    if (!_gestureLive) {
      if (_listenerTotalDy > _listenerTotalDx.abs() * 1.4) {
        // Vertical-dominant → mark handled for the entire gesture
        _handled = true;
        return;
      }
      _gestureLive = true;

      // Axis resolved to horizontal: decide ownership once for this
      // gesture. If the child can still move that way, this gesture is
      // the child's — root never touches _dragOffset for it.
      if (_childCanMove(_listenerTotalDx)) {
        _deferToChild = true;
        return;
      }
    }

    _recent.add(_Sample(event.delta.dx, event.timeStamp));

    setState(() {
      _dragOffset += event.delta.dx;
    });
  }

  void _onUp(PointerUpEvent event) {
    if (_handled || _deferToChild) return;
    if (!_gestureLive) return;

    final target = ZadSwipeNav.targetIndex(
      index: widget.index,
      dragDistance: _listenerTotalDx,
      velocity: _velocity(),
      routesLength: widget.routes.length,
    );
    if (target != null && target >= 0 && target < widget.routes.length) {
      _handled = true;
      // Use the same forward/backward signal that picked target (not
      // _dragOffset's sign) — a fast whip-back flick can end with a net
      // distance opposite the velocity that actually decided the target.
      _commitTo(widget.routes[target], forward: target > widget.index);
    } else {
      _animateBack();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _animateBack();
  }

  /// Finishes the filmstrip slide to completion (current page fully
  /// off-screen, neighbor at `x = 0`) before navigating — so the drag
  /// visually completes instead of being cut off mid-slide.
  void _commitTo(String route, {required bool forward}) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    _settleFrom = _dragOffset;
    _settleTo = screenWidth * (forward ? 1 : -1);
    _commitRoute = route;
    _settleCtrl.forward(from: 0);
  }

  void _animateBack() {
    if (_dragOffset == 0) return;
    _settleFrom = _dragOffset;
    _settleTo = 0;
    _commitRoute = null;
    _settleCtrl.forward(from: 0);
  }

  static const _neighborIconMap = {
    '/home': Icons.home_outlined,
    '/budget': Icons.account_balance_wallet_outlined,
    '/teams': Icons.groups_outlined,
    '/notifications': Icons.notifications_outlined,
    '/admin': Icons.admin_panel_settings_outlined,
  };

  static const _neighborLabelMap = {
    '/home': 'الرئيسية',
    '/budget': 'الميزانية',
    '/teams': 'الفرق',
    '/notifications': 'التنبيهات',
    '/admin': 'الإدارة',
  };

  /// Real neighbor screen (current + one neighbor only, built lazily —
  /// only while actively dragging) for a true gallery/carousel feel.
  /// Falls back to a lightweight icon+label placeholder when no
  /// [ZadSwipeNav.screenBuilder] was supplied (e.g. unit tests).
  Widget _buildNeighborPreview(String neighborRoute) {
    final builder = widget.screenBuilder;
    if (builder == null) {
      return Container(
        color: ZadTokens.surface,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _neighborIconMap[neighborRoute] ?? Icons.circle_outlined,
              size: 48,
              color: ZadTokens.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              _neighborLabelMap[neighborRoute] ?? '',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ZadTokens.textMuted,
              ),
            ),
          ],
        ),
      );
    }
    return KeyedSubtree(
      key: ValueKey('zad-swipe-neighbor-$neighborRoute'),
      child: builder(neighborRoute),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.index == -1) return widget.child;

    final isAdmin = ZadSessionScope.maybeOf(context)?.isAdmin ?? false;
    final allRoutes = ZadBottomNav.routesFor(isAdmin);

    // Neighbor info during drag — stays mounted for the entire settle
    // animation (cancel or commit), not just the raw finger-driven drag,
    // so it never pops in/out out of sync with the current page.
    String? neighborRoute;
    if (_dragOffset.abs() > 0) {
      final dir = _dragOffset > 0 ? 1 : -1;
      final ni = widget.index + dir;
      if (ni >= 0 && ni < allRoutes.length) {
        neighborRoute = allRoutes[ni];
      }
    }

    // Filmstrip offset: the neighbor's near edge touches the current
    // page's trailing edge, and it reaches x = 0 exactly when the drag
    // reaches full screen width — a real adjacent page, not a static
    // underlay.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final neighborOffset = _dragOffset - screenWidth * (_dragOffset > 0 ? 1 : -1);

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
        onPointerCancel: _onPointerCancel,
        child: Stack(
          children: [
            // Gallery-style neighbor page — offset like a real filmstrip.
            if (neighborRoute != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Transform.translate(
                    offset: Offset(neighborOffset, 0),
                    child: _buildNeighborPreview(neighborRoute),
                  ),
                ),
              ),
            // Current page — slides to reveal neighbor
            Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: widget.child,
            ),
            // Each root screen carries its own bottom nav inside its
            // Scaffold, so during a filmstrip drag both navs would slide
            // with their pages. This stable overlay (same widget, same
            // bottom position) covers them while the strip is moving, so
            // the nav appears fixed — like a real tabbed gallery. Only in
            // real-gallery mode (screenBuilder != null); the active pill
            // updates when the route commits, matching bottom-nav taps.
            if (neighborRoute != null && widget.screenBuilder != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: ZadBottomNav.forLocation(
                        widget.routes[widget.index],
                      ) ??
                      const SizedBox.shrink(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
