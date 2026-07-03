import 'package:flutter/material.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_scaffold.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  // Premium "ding" hint: one quick micro-wiggle (~450ms) then complete rest
  // for the remaining ~2.55s of each 3s cycle. The bell must feel like a
  // small elegant notification hint — not an alarm, not a pendulum.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat();
  late final Animation<double> _ding = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 4, // ~120ms — quick flick right
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: -0.7,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 5, // ~150ms — smooth counter-swing
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: -0.7,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 6, // ~180ms — settle, no snap
    ),
    // Rest completely for the remaining ~2.55s.
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 85),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion: bell stays fully static.
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
    return ZadScaffold(
      title: 'الإشعارات',
      body: Padding(
        padding: const EdgeInsets.only(top: ZadTokens.s6),
        child: ZadAnimatedEntry(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ZadTokens.s4,
              vertical: ZadTokens.s6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Static disk; only the bell moves (paint-only transform).
                Container(
                  width: 120,
                  height: 120,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ZadTokens.gold.withValues(alpha: 0.12),
                  ),
                  child: AnimatedBuilder(
                    animation: _ding,
                    builder: (context, child) => Transform.rotate(
                      angle: 0.03 * _ding.value, // ±0.03 rad ≈ ±1.7°
                      child: child,
                    ),
                    child: const Icon(
                      Icons.notifications_none_outlined,
                      size: 48,
                      color: ZadTokens.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(height: ZadTokens.s4),
                Text(
                  'لا توجد تنبيهات حالياً',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: ZadTokens.s2),
                const Text(
                  'ستظهر التنبيهات هنا قريباً — سنقوم بإشعارك عند وجود تحديثات جديدة في ميزانيتك أو فرقك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ZadTokens.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
