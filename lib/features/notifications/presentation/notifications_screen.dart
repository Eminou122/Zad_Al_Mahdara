import 'package:flutter/material.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_scaffold.dart';

const _warmBorder = Color(0xFFF2E0CC);
const _warmDisk = Color(0xFFFEEDDC);

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
      title: 'التنبيهات',
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, ZadTokens.s6, 20, 96),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 128).clamp(360.0, 620.0),
              ),
              child: Center(
                child: ZadAnimatedEntry(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 148,
                          height: 148,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _warmDisk,
                            border: Border.all(color: _warmBorder),
                            boxShadow: ZadTokens.cardShadow,
                          ),
                          child: AnimatedBuilder(
                            animation: _ding,
                            builder: (context, child) => Transform.rotate(
                              angle: 0.03 * _ding.value,
                              child: child,
                            ),
                            child: const Icon(
                              Icons.notifications_none_outlined,
                              size: 72,
                              color: ZadTokens.primaryDark,
                            ),
                          ),
                        ),
                        const SizedBox(height: ZadTokens.s5),
                        Text(
                          'لا توجد تنبيهات حالياً',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: ZadTokens.text,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: ZadTokens.s3),
                        const Text(
                          'ستظهر التنبيهات هنا قريباً. سنقوم بإشعارك عند وجود تحديثات جديدة في ميزانيتك أو فرقك الدراسية.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: ZadTokens.textMuted,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
