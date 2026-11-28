import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import 'trend_series.dart';

/// Colours and text the chart paints with. All from the palette; the line
/// uses the theme accent (user decision 2026-11-26), never a safety colour.
@immutable
class TrendChartStyle {
  const TrendChartStyle({
    required this.line,
    required this.muted,
    required this.grid,
    required this.pastBand,
    required this.surface,
    required this.marker,
    required this.label,
    required this.textScaler,
    required this.sourceColor,
  });

  final Color line;

  /// Stale hours: dashed and in this colour, never the line colour.
  final Color muted;
  final Color grid;
  final Color pastBand;
  final Color surface;
  final Color marker;
  final TextStyle label;
  final TextScaler textScaler;

  /// A source's fixed line colour, for the strip under each hour.
  final Color Function(String sourceId) sourceColor;
}

/// Where everything sits. Shared by the painter and the hit testing, so a tap
/// lands on the hour that is drawn under it.
class TrendLayout {
  TrendLayout(this.series, this.size, this.style) {
    final widest = series.axis.ticks
        .map((t) => _measure(_tick(t)).width)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final labelHeight = _measure('0').height;
    left = widest + 8;
    top = labelHeight * 2 + 6 + (series.hasDirections ? arrowRow : 0); // marker rows, arrows
    final bottom = stripHeight + 4 + labelHeight + 4;
    plot = Rect.fromLTRB(left, top, size.width - 4, size.height - bottom);
  }

  final TrendSeries series;
  final Size size;
  final TrendChartStyle style;

  static const stripHeight = 6.0;

  /// The row of wind arrows between the marker labels and the plot.
  static const arrowRow = 18.0;

  /// Hour labels (and wind arrows) every [labelEvery] hours, so the widest
  /// label never touches its neighbour: 1, 2, 3, 4, 6, 12 or 24.
  int get labelEvery {
    final widest = painter('12 PM', mono: true).width + 8;
    final hourWidth = plot.width / series.hours;
    if (hourWidth <= 0) return 24;
    final need = (widest / hourWidth).ceil();
    for (final step in const [1, 2, 3, 4, 6, 12]) {
      if (step >= need) return step;
    }
    return 24;
  }

  late final double left;
  late final double top;
  late final Rect plot;

  TextPainter painter(String text, {Color? color, bool mono = false}) => TextPainter(
    text: mono
        ? PitchyFigures.figureSpans(text, style.label.copyWith(color: color))
        : TextSpan(
            text: text,
            style: style.label.copyWith(color: color),
          ),
    textDirection: TextDirection.ltr,
    textScaler: style.textScaler,
  )..layout();

  Size _measure(String text) => painter(text).size;

  /// Every tick with the same decimals, so "32" and "32.2" don't mix.
  String _tick(double t) {
    final ticks = series.axis.ticks;
    final step = ticks.length < 2 ? 1.0 : (ticks[1] - ticks[0]).abs();
    final decimals = step >= 1 || step == 0 ? 0 : (step >= 0.1 ? 1 : 2);
    return t.toStringAsFixed(decimals);
  }

  double get _span {
    final s = series.end.difference(series.start).inSeconds.toDouble();
    return s <= 0 ? 1 : s;
  }

  double xOf(DateTime t) =>
      plot.left + plot.width * (t.difference(series.start).inSeconds / _span).clamp(0.0, 1.0);

  double yOf(double v) {
    final a = series.axis;
    final f = (v - a.min) / (a.max - a.min);
    return plot.bottom - plot.height * f.clamp(0.0, 1.0);
  }

  /// The hour under [x], or null outside the plot.
  int? indexAt(double x) {
    if (series.points.isEmpty || x < plot.left - 12 || x > plot.right + 12) return null;
    for (var i = 0; i < series.points.length; i++) {
      final p = series.points[i];
      if (x <= xOf(p.until)) return i;
    }
    return series.points.length - 1;
  }

  /// Minimum height for the chart at the current text size.
  static double heightFor(TextStyle label, TextScaler scaler, {bool arrows = false}) {
    final line = scaler.scale(label.fontSize ?? 11) * (label.height ?? 1.3);
    return 150 + line * 3 + stripHeight + 14 + (arrows ? arrowRow : 0);
  }
}

/// [num.clamp] throws when [hi] < [lo] (a label wider than a narrow chart at
/// large text); this keeps the lower bound instead.
double _safeClamp(double v, double lo, double hi) => hi < lo ? lo : v.clamp(lo, hi);

class TrendPainter extends CustomPainter {
  TrendPainter({
    required this.series,
    required this.style,
    required this.selected,
    this.marker,
  }) : super(repaint: marker);

  final TrendSeries series;
  final TrendChartStyle style;
  final int? selected;

  /// Where the selected-hour line sits, as a position between hours (0 is the
  /// first hour's middle, 1.5 halfway from the second to the third). Moves
  /// only the line: the value, ring and readout follow [selected] at once.
  /// Null: the line sits on [selected].
  final Animation<double>? marker;

  /// The x of the selected-hour line, or null when there is none.
  double? markerX(TrendLayout l) {
    final pts = series.points;
    if (pts.isEmpty) return null;
    final sel = selected;
    if (sel == null || sel >= pts.length) return null;
    final pos = marker?.value;
    if (pos == null) return l.xOf(pts[sel].middle);
    final at = pos.clamp(0.0, pts.length - 1.0);
    final lo = at.floor(), hi = at.ceil();
    final a = l.xOf(pts[lo].middle), b = l.xOf(pts[hi].middle);
    return a + (b - a) * (at - lo);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final l = TrendLayout(series, size, style);
    final plot = l.plot;
    final hair = Paint()
      ..color = style.grid
      ..strokeWidth = 1;

    // Hours already past: a light band, so they read as earlier forecasts.
    final pastEnd = series.checkedAt.isBefore(series.end) ? series.checkedAt : series.end;
    if (pastEnd.isAfter(series.start)) {
      canvas.drawRect(
        Rect.fromLTRB(plot.left, plot.top, l.xOf(pastEnd), plot.bottom),
        Paint()..color = style.pastBand,
      );
    }

    // Grid lines and y labels.
    for (final t in series.axis.ticks) {
      final y = l.yOf(t);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), hair);
      final tp = l.painter(l._tick(t));
      tp.paint(canvas, Offset(plot.left - 8 - tp.width, y - tp.height / 2));
    }

    // Markers: kickoff, end of coverage, now. Labels in two rows so close
    // markers don't overlap.
    final markers = <(DateTime, String)>[
      (series.kickoff, 'Kickoff'),
      if (series.coverageEnd != null) (series.coverageEnd!, 'Match window end'),
      (series.checkedAt, 'Now'),
    ];
    var lastRight = double.negativeInfinity;
    var row = 0;
    for (final (t, name) in markers) {
      if (t.isBefore(series.start) || t.isAfter(series.end)) continue;
      final x = l.xOf(t);
      _dashedLine(canvas, Offset(x, plot.top), Offset(x, plot.bottom), style.marker, 1, 3, 3);
      final tp = l.painter(name, color: style.marker);
      final lx = _safeClamp(x - tp.width / 2, 0, size.width - tp.width);
      row = lx < lastRight + 6 ? (row + 1) % 2 : 0;
      tp.paint(canvas, Offset(lx, row * (tp.height + 2)));
      lastRight = lx + tp.width;
    }

    // Selected hour: a thin solid line through it (not a shaded column, so
    // it can't be confused with the past-hours band).
    final x = markerX(l);
    if (x != null) {
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = style.muted
          ..strokeWidth = 1,
      );
    }

    if (series.kind == TrendKind.bars) {
      _bars(canvas, l);
    } else {
      _line(canvas, l);
    }

    // Source strip: one cell per hour in that hour's source colour; a gap has
    // an empty outlined cell.
    final stripTop = plot.bottom + 4;
    for (final p in series.points) {
      final r = Rect.fromLTRB(
        l.xOf(p.from) + 1,
        stripTop,
        l.xOf(p.until) - 1,
        stripTop + TrendLayout.stripHeight,
      );
      if (p.sourceId == null) {
        canvas.drawRect(
          r.deflate(0.5),
          Paint()
            ..color = style.grid
            ..style = PaintingStyle.stroke,
        );
      } else {
        canvas.drawRect(r, Paint()..color = style.sourceColor(p.sourceId!));
      }
    }

    // Hour labels under the strip; every second one when they'd crowd.
    final labelTop = stripTop + TrendLayout.stripHeight + 4;
    final every = l.labelEvery;
    for (var i = 0; i < series.points.length; i += every) {
      final p = series.points[i];
      final tp = l.painter(TrendSeries.hourLabel(p.from), mono: true);
      final x = _safeClamp(l.xOf(p.middle) - tp.width / 2, 0, size.width - tp.width);
      tp.paint(canvas, Offset(x, labelTop));
      if (p.hasDirection) _arrow(canvas, l, p, i == selected);
    }
  }

  /// A wind arrow above the plot, pointing the way the wind blows (downwind,
  /// as on weather maps); the readout says where it comes FROM.
  void _arrow(Canvas canvas, TrendLayout l, TrendPoint p, bool selected) {
    const half = 6.0;
    final c = Offset(l.xOf(p.middle), l.plot.top - TrendLayout.arrowRow / 2);
    final color = p.directionCurrent ? style.line : style.muted;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2.5 : 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate((p.direction! + 180) * math.pi / 180);
    // Up is north before rotating: shaft plus head.
    canvas
      ..drawLine(const Offset(0, half), const Offset(0, -half), paint)
      ..drawLine(const Offset(0, -half), const Offset(-3.5, -half + 4.5), paint)
      ..drawLine(const Offset(0, -half), const Offset(3.5, -half + 4.5), paint)
      ..restore();
  }

  void _line(Canvas canvas, TrendLayout l) {
    final pts = series.points;
    Offset at(int i) => Offset(l.xOf(pts[i].middle), l.yOf(pts[i].value!));
    for (final link in series.links) {
      final a = at(link.from), b = at(link.to);
      if (link.dashed) {
        _dashedLine(canvas, a, b, style.muted, 2, 5, 4);
      } else {
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = style.line
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    for (var i = 0; i < pts.length; i++) {
      if (!pts[i].hasValue) continue;
      final c = at(i);
      final r = i == selected ? 6.0 : 4.0;
      if (pts[i].current) {
        canvas.drawCircle(c, r, Paint()..color = style.line);
      } else {
        // Not current: a hollow, muted dot (no state by colour alone).
        canvas.drawCircle(c, r, Paint()..color = style.surface);
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..color = style.muted
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      if (i == selected) {
        canvas.drawCircle(
          c,
          r + 3,
          Paint()
            ..color = pts[i].current ? style.line : style.muted
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  void _bars(Canvas canvas, TrendLayout l) {
    final base = l.yOf(series.axis.min);
    for (var i = 0; i < series.points.length; i++) {
      final p = series.points[i];
      if (!p.hasValue) continue;
      final left = l.xOf(p.from), right = l.xOf(p.until);
      final inset = _safeClamp((right - left) * 0.18, 0, 10);
      // A zero amount is a zero-height bar: just its outline on the baseline,
      // which still differs from a gap (nothing drawn).
      final top = _safeClamp(l.yOf(p.value!), l.plot.top, base);
      final r = Rect.fromLTRB(left + inset, top, right - inset, base);
      if (p.current) {
        canvas
          ..drawRect(r, Paint()..color = style.line.withValues(alpha: 0.28))
          ..drawRect(
            r,
            Paint()
              ..color = style.line
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
      } else {
        canvas.drawRect(r, Paint()..color = style.surface);
        _dashedRect(canvas, r.deflate(1), style.muted);
      }
      if (i == selected) {
        canvas.drawRect(
          r.inflate(2),
          Paint()
            ..color = p.current ? style.line : style.muted
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  static void _dashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Color color,
    double width,
    double dash,
    double gap,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += dash + gap) {
      final end = (d + dash).clamp(0.0, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
    }
  }

  static void _dashedRect(Canvas canvas, Rect r, Color color) {
    _dashedLine(canvas, r.topLeft, r.topRight, color, 1.5, 4, 3);
    _dashedLine(canvas, r.topRight, r.bottomRight, color, 1.5, 4, 3);
    _dashedLine(canvas, r.bottomRight, r.bottomLeft, color, 1.5, 4, 3);
    _dashedLine(canvas, r.bottomLeft, r.topLeft, color, 1.5, 4, 3);
  }

  @override
  bool shouldRepaint(TrendPainter old) =>
      old.series != series ||
      old.selected != selected ||
      old.style != style ||
      old.marker != marker;
}
