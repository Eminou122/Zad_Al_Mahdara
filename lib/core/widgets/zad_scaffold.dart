import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/zad_tokens.dart';
import 'zad_bottom_nav.dart';
import 'zad_logo_badge.dart';

class ZadScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Future<void> Function()? onRefresh;

  const ZadScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // Stitch app shell: bottom nav + back-arrow visibility derive from the
    // current route, so screens need no shell wiring of their own.
    final location = _location(context);
    return Scaffold(
      appBar: AppBar(
        // Root tabs never show a back arrow (Stitch); pop/browser back is
        // untouched — only the arrow is hidden.
        automaticallyImplyLeading:
            location == null || !ZadBottomNav.isRootTab(location),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ZadLogoBadge(size: 30),
            const SizedBox(width: ZadTokens.s2 + 2),
            Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: actions,
      ),
      bottomNavigationBar: location == null
          ? null
          : ZadBottomNav.forLocation(location),
      body: SafeArea(
        // topCenter: short pages start under the AppBar instead of mid-screen.
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ZadTokens.contentMaxWidth,
            ),
            child: onRefresh == null
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(ZadTokens.s4),
                    child: body,
                  )
                : _RefreshableBody(onRefresh: onRefresh!, child: body),
          ),
        ),
      ),
    );
  }

  String? _location(BuildContext context) {
    try {
      return GoRouterState.of(context).matchedLocation;
    } catch (_) {
      return null; // built outside a route (e.g. bare widget tests)
    }
  }
}

class _RefreshableBody extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const _RefreshableBody({required this.onRefresh, required this.child});

  @override
  State<_RefreshableBody> createState() => _RefreshableBodyState();
}

class _RefreshableBodyState extends State<_RefreshableBody> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await widget.onRefresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديث البيانات. حاول مرة أخرى.')),
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(ZadTokens.s4),
        child: widget.child,
      ),
    );
  }
}
