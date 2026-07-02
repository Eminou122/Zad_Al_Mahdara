import 'package:flutter/material.dart';

/// One-time gentle fade + slide-up entry (220ms, easeOutCubic).
/// State persists across parent rebuilds, so it never re-animates on
/// setState; it plays again only when the subtree is recreated from
/// scratch (e.g. after a full-screen loading spinner).
class ZadAnimatedEntry extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const ZadAnimatedEntry({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  @override
  State<ZadAnimatedEntry> createState() => _ZadAnimatedEntryState();
}

class _ZadAnimatedEntryState extends State<ZadAnimatedEntry> {
  static const _duration = Duration(milliseconds: 220);
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      // Next frame, so the hidden state paints once and the fade is visible.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _visible = true);
      });
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Opacity/slide are paint-only: no layout shift, taps stay live.
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: _duration,
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.05),
        duration: _duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
