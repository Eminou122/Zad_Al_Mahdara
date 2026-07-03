import 'package:flutter/material.dart';

class ZadDottedBackground extends StatelessWidget {
  final Widget child;
  final Color color;
  final double spacing;

  const ZadDottedBackground({
    super.key,
    required this.child,
    this.color = const Color(0x22C9A227),
    this.spacing = 18,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DotsPainter(color: color, spacing: spacing),
      child: child,
    );
  }
}

class _DotsPainter extends CustomPainter {
  final Color color;
  final double spacing;

  const _DotsPainter({required this.color, required this.spacing});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = spacing / 2; y < size.height; y += spacing) {
      for (double x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.spacing != spacing;
}
