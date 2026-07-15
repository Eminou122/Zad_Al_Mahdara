import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'zad_bottom_nav.dart';
import 'zad_nested_swipe_scope.dart';
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
/// Gesture intent (Gate 29.12): movement is accumulated until one axis
/// clearly wins. Vertical locks first (|dy| ≥ 12 and |dy| ≥ |dx| · 1.1) and
/// kills the gesture for root; horizontal locks only on a deliberate move
/// (|dx| ≥ 24 and |dx| ≥ |dy| · 1.8). While neither test passes, the
/// gesture stays undecided and root does not move at all — vertical
/// scrolling with horizontal jitter can never start a tab swipe.
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
/// Edge clamp (Gate 29.12): before applying any drag offset, the drag
/// direction must have a real neighboring tab. At the first tab the
/// outward direction is blocked completely (no movement, no preview, no
/// route attempt), and likewise at the last tab — for both the 5-tab user
/// strip and the 6-tab admin strip.
///
/// State preservation (Gate 29.12): when [screenBuilder] is supplied,
/// this widget acts as a persistent tab shell. Every root screen it has
/// shown is built exactly once, cached, and kept alive in an offstage
/// keyed slot (tickers paused) — so dragging toward a neighbor, cancelling,
/// committing, and coming back never re-mounts a section and never
/// re-triggers its `initState` data fetch. This relies on [AppRouter]
/// giving all root-tab pages one shared page key, so GoRouter updates the
/// page in place instead of replacing the route.
///
/// During a root-owned drag, the current section follows the finger via
/// [Transform.translate] and the cached neighboring root screen is offset
/// by `dragOffset ∓ screenWidth` — a real filmstrip position, so its near
/// edge touches the current page and it reaches `x = 0` exactly when the
/// drag reaches full screen width, like a gallery/photo carousel.
///
/// On release, a single [AnimationController] (`_settleCtrl`) drives both
/// pages together to their resting position: on cancel, back to
/// `dragOffset = 0`; on commit, all the way to `dragOffset = ±screenWidth`
/// (current fully off-screen, neighbor at `x = 0`) — only then is
/// `context.go()` called once, so the filmstrip finishes its slide before
/// the router swaps the current tab (an in-place page update, no second
/// transition). Bottom-nav taps and browser navigation play the same
/// filmstrip slide programmatically, so every tab change feels identical.
class ZadSwipeNav extends StatefulWidget {
  final Widget child;
  final List<String> routes;
  final int index;

  /// Sentinel passed as `extra` to [GoRouterHelper.go] when a committed
  /// swipe navigates. With the shared root page key the router no longer
  /// plays a transition between tabs at all, but the sentinel is kept so
  /// tests (and any future non-shell embedding) can still detect a
  /// gesture-driven commit.
  static const swipeCommitExtra = 'zad-swipe-commit';

  /// Builds the real screen for a root route. When supplied, ZadSwipeNav
  /// runs in persistent-shell mode: built screens are cached and kept
  /// alive (see class docs). Optional so unit/widget tests that don't care
  /// about the gallery preview can omit it (falls back to a lightweight
  /// icon+label placeholder translating [child] directly).
  final Widget Function(String route)? screenBuilder;

  const ZadSwipeNav({
    super.key,
    required this.child,
    required this.routes,
    required this.index,
    this.screenBuilder,
  });

  // ── Gesture intent thresholds (Gate 29.12) ──
  // Horizontal lock: deliberate sideways move, clearly wider than tall.
  static const _horizontalLockDx = 24.0;
  static const _horizontalDominance = 1.8;
  // Vertical lock: checked first, so any clearly vertical gesture wins
  // ties and permanently rejects the root swipe.
  static const _verticalLockDy = 12.0;
  static const _verticalDominance = 1.1;

  // ── Commit thresholds ──
  static const _minVelocity = 500.0;
  static const _minDistanceFloor = 90.0;
  static const _commitFraction = 0.22;

  /// Distance a locked horizontal drag must cover to commit a tab change:
  /// max(90px, 22% of screen width) — a deliberate slide, not a nudge.
  static double commitDistance(double screenWidth) =>
      math.max(_minDistanceFloor, screenWidth * _commitFraction);

  /// Pure swipe-resolution logic, unit-testable.
  static int? targetIndex({
    required int index,
    required double dragDistance,
    required double velocity,
    required int routesLength,
    required double screenWidth,
  }) {
    final minDistance = commitDistance(screenWidth);
    final signal = velocity.abs() >= _minVelocity ? velocity : dragDistance;
    if (signal.abs() < minDistance && velocity.abs() < _minVelocity) {
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

  // Listener trackers: net accumulated movement since pointer down.
  double _totalDx = 0;
  double _totalDy = 0;
  bool _gestureLive = false;

  // Velocity tracking
  final _recent = <_Sample>[];
  static const _maxSampleAge = Duration(milliseconds: 120);

  // Child PageController tracking. In shell mode each cached screen's
  // registration is captured per route (so an offstage Teams can never
  // hijack boundary checks while another tab is current); the single
  // `_childPc` serves the legacy no-screenBuilder path.
  final _childPcs = <String, PageController>{};
  PageController? _childPc;

  // Decided once per gesture, the move axis-lock resolves to horizontal:
  // true means the registered child still has room to move in this
  // drag's direction, so root stays inert and lets the child's own
  // PageView handle the whole gesture.
  bool _deferToChild = false;

  // Persistent shell cache: every root screen built so far, keyed by
  // route. Built exactly once per route and kept alive offstage, so a
  // section's State (and its fetched data) survives tab switches for the
  // whole session. Pruned when the route list changes (admin ↔ user).
  final _screens = <String, Widget>{};

  // Settle animation: drives _dragOffset from _settleFrom to _settleTo.
  // _settleTo == 0 for a cancel (snap back) or a programmatic tab slide;
  // _settleTo == ±screenWidth for a commit (finish the filmstrip slide).
  // _commitRoute is non-null only for the commit case — context.go()
  // fires once, on completion.
  late AnimationController _settleCtrl;
  double _settleFrom = 0;
  double _settleTo = 0;
  String? _commitRoute;

  // True while our own commit's context.go() is propagating back down as
  // a widget update — that index change must not replay any animation.
  bool _selfCommit = false;

  // During a programmatic slide (bottom-nav tap / browser navigation) the
  // outgoing tab is shown as the filmstrip neighbor regardless of index
  // adjacency.
  String? _overrideNeighbor;

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
        _overrideNeighbor = null;
        final route = _commitRoute;
        _commitRoute = null;
        if (route != null && mounted) {
          _selfCommit = true;
          context.go(route, extra: ZadSwipeNav.swipeCommitExtra);
        }
      });
  }

  @override
  void didUpdateWidget(covariant ZadSwipeNav old) {
    super.didUpdateWidget(old);
    final wasSelfCommit = _selfCommit;
    _selfCommit = false;

    final routesChanged = !listEquals(old.routes, widget.routes);
    if (routesChanged) {
      // Never keep a stale screen for a route the user no longer has
      // (e.g. the admin tab after a role change).
      _screens.removeWhere((r, _) => !widget.routes.contains(r));
      _childPcs.removeWhere((r, _) => !widget.routes.contains(r));
    }
    if (widget.index == old.index && !routesChanged) return;

    _settleCtrl.stop();
    _commitRoute = null;
    _overrideNeighbor = null;
    _dragOffset = 0;

    // Our own committed swipe already finished the filmstrip slide — the
    // index change just swaps roles at identical pixels. External changes
    // (bottom-nav tap, browser back/forward) play the same filmstrip
    // slide programmatically so every tab change feels like the gallery.
    final canSlide = !wasSelfCommit &&
        !routesChanged &&
        widget.screenBuilder != null &&
        old.index >= 0 &&
        widget.index >= 0 &&
        widget.index != old.index &&
        !MediaQuery.of(context).disableAnimations;
    if (!canSlide) return;

    _overrideNeighbor = old.routes[old.index];
    final width = MediaQuery.sizeOf(context).width;
    // New current slides in from its filmstrip side (higher index lives
    // on the left in this RTL strip), outgoing tab slides out the other.
    _dragOffset = width * (widget.index > old.index ? -1 : 1);
    _settleFrom = _dragOffset;
    _settleTo = 0;
    _settleCtrl.forward(from: 0);
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
    final pc = widget.screenBuilder != null
        ? _childPcs[widget.routes[widget.index]]
        : _childPc;
    if (pc == null || !pc.hasClients) return false;
    final pos = pc.position;
    // Positive dx (drag right) moves toward a higher page index — same
    // convention as ZadSwipeNav.targetIndex — so it needs room *after*;
    // negative dx (drag left) needs room *before*.
    if (dx > 0) return pos.extentAfter > 0;
    if (dx < 0) return pos.extentBefore > 0;
    return false;
  }

  /// Edge clamp: a drag direction with no real neighboring tab produces no
  /// movement at all — no blank space, no fake neighbor, no route attempt.
  /// Positive offset reveals index+1, negative reveals index-1 (same
  /// convention as [ZadSwipeNav.targetIndex]).
  double _clampToNeighbors(double offset) {
    if (offset > 0 && widget.index + 1 >= widget.routes.length) return 0;
    if (offset < 0 && widget.index - 1 < 0) return 0;
    return offset;
  }

  // ── Listener callbacks ──

  void _onDown(PointerDownEvent event) {
    _settleCtrl.stop();
    final route = _commitRoute;
    _commitRoute = null;
    if (route != null && mounted) {
      // Touched down mid-commit-slide: finish the committed navigation
      // instantly rather than silently dropping it.
      _selfCommit = true;
      context.go(route, extra: ZadSwipeNav.swipeCommitExtra);
    }
    if (_dragOffset != 0 || _overrideNeighbor != null) {
      setState(() {
        _dragOffset = 0;
        _overrideNeighbor = null;
      });
    }
    _handled = false;
    _gestureLive = false;
    _deferToChild = false;
    _totalDx = 0;
    _totalDy = 0;
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

    _totalDx += event.delta.dx;
    _totalDy += event.delta.dy;

    if (!_gestureLive) {
      final dxAbs = _totalDx.abs();
      final dyAbs = _totalDy.abs();
      // Vertical is checked first and wins ties: once locked, the whole
      // gesture is ignored by root.
      if (dyAbs >= ZadSwipeNav._verticalLockDy &&
          dyAbs >= dxAbs * ZadSwipeNav._verticalDominance) {
        _handled = true;
        return;
      }
      // Not yet a deliberate horizontal move → stay undecided, no motion.
      if (dxAbs < ZadSwipeNav._horizontalLockDx ||
          dxAbs < dyAbs * ZadSwipeNav._horizontalDominance) {
        return;
      }

      // Axis resolved to horizontal: decide ownership once for this
      // gesture. If the child can still move that way, this gesture is
      // the child's — root never touches _dragOffset for it.
      if (_childCanMove(_totalDx)) {
        _deferToChild = true;
        return;
      }
      _gestureLive = true;
      // Apply the accumulated pre-lock movement so the page meets the
      // finger without a dead zone.
      _recent.add(_Sample(_totalDx, event.timeStamp));
      setState(() => _dragOffset = _clampToNeighbors(_totalDx));
      return;
    }

    _recent.add(_Sample(event.delta.dx, event.timeStamp));
    setState(
      () => _dragOffset = _clampToNeighbors(_dragOffset + event.delta.dx),
    );
  }

  void _onUp(PointerUpEvent event) {
    if (_handled || _deferToChild || !_gestureLive) return;

    final target = ZadSwipeNav.targetIndex(
      index: widget.index,
      dragDistance: _totalDx,
      velocity: _velocity(),
      routesLength: widget.routes.length,
      screenWidth: MediaQuery.sizeOf(context).width,
    );
    if (target != null) {
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
    '/messages': Icons.mail_outline,
    '/notifications': Icons.notifications_outlined,
    '/admin': Icons.admin_panel_settings_outlined,
  };

  static const _neighborLabelMap = {
    '/home': 'الرئيسية',
    '/budget': 'الميزانية',
    '/teams': 'الفرق',
    '/messages': 'الرسائل',
    '/notifications': 'التنبيهات',
    '/admin': 'الإدارة',
  };

  /// Lightweight icon+label placeholder for the legacy (no
  /// [ZadSwipeNav.screenBuilder]) path, e.g. unit tests.
  Widget _placeholderPreview(String neighborRoute) {
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

  @override
  Widget build(BuildContext context) {
    if (widget.index == -1) return widget.child;

    final routes = widget.routes;
    final current = routes[widget.index];

    // Neighbor shown while the strip is displaced — for the entire drag
    // and settle animation (cancel, commit, or programmatic tab slide),
    // so it never pops in/out out of sync with the current page.
    String? neighborRoute;
    if (_dragOffset != 0) {
      neighborRoute = _overrideNeighbor;
      if (neighborRoute == null) {
        final ni = widget.index + (_dragOffset > 0 ? 1 : -1);
        if (ni >= 0 && ni < routes.length) neighborRoute = routes[ni];
      }
    }

    // Filmstrip offset: the neighbor's near edge touches the current
    // page's trailing edge, and it reaches x = 0 exactly when the drag
    // reaches full screen width — a real adjacent page, not a static
    // underlay.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final neighborOffset =
        _dragOffset - screenWidth * (_dragOffset > 0 ? 1 : -1);

    final List<Widget> layers;
    if (widget.screenBuilder != null) {
      // Persistent-shell mode: cached screens, built once per route.
      _screens[current] ??= widget.screenBuilder!(current);
      if (neighborRoute != null) {
        _screens[neighborRoute] ??= widget.screenBuilder!(neighborRoute);
      }

      // Every slot keeps an identical widget chain and a stable key, so a
      // screen moving between offstage / neighbor / current never loses
      // its Element (and therefore never re-mounts or re-fetches).
      Widget slot(String route) {
        final isCurrent = route == current;
        final isNeighbor = route == neighborRoute;
        final active = isCurrent || isNeighbor;
        return Positioned.fill(
          key: ValueKey('zad-slot-$route'),
          child: Offstage(
            offstage: !active,
            child: TickerMode(
              enabled: active,
              child: IgnorePointer(
                ignoring: !isCurrent,
                child: Transform.translate(
                  offset: Offset(
                    isCurrent
                        ? _dragOffset
                        : (isNeighbor ? neighborOffset : 0),
                    0,
                  ),
                  child: NotificationListener<PageControllerRegistration>(
                    onNotification: (n) {
                      _childPcs[route] = n.controller;
                      return true;
                    },
                    child: _screens[route]!,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      layers = [
        // Kept-alive tabs (offstage) first, then the neighbor, then the
        // current tab on top — keyed slots, so paint-order changes never
        // remount a screen.
        for (final r in routes)
          if (_screens.containsKey(r) && r != current && r != neighborRoute)
            slot(r),
        if (neighborRoute != null) slot(neighborRoute),
        slot(current),
        // Each root screen carries its own bottom nav inside its
        // Scaffold, so during a filmstrip slide both navs would move
        // with their pages. This stable overlay (same widget, same
        // bottom position) covers them while the strip is moving, so
        // the nav appears fixed — like a real tabbed gallery. The active
        // pill shows the route the strip is settling on.
        if (neighborRoute != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child:
                  ZadBottomNav.forLocation(current) ?? const SizedBox.shrink(),
            ),
          ),
      ];
    } else {
      layers = [
        if (neighborRoute != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Transform.translate(
                offset: Offset(neighborOffset, 0),
                child: _placeholderPreview(neighborRoute),
              ),
            ),
          ),
        Transform.translate(
          offset: Offset(_dragOffset, 0),
          child: widget.child,
        ),
      ];
    }

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
        child: Stack(children: layers),
      ),
    );
  }
}
