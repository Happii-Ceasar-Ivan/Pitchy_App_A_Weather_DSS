import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';

/// A hairline dashed outline (the "stamp" used for Stale).
class DashedBorder extends StatelessWidget {
  const DashedBorder({super.key, required this.color, required this.radius, required this.child});

  final Color color;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(foregroundPainter: _DashedPainter(color, radius), child: child);
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final r = radius.clamp(0, size.shortestSide / 2).toDouble();
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(r),
    ).deflate(AppTheme.hairline / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppTheme.hairline * 1.5;
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) => old.color != color || old.radius != radius;
}
