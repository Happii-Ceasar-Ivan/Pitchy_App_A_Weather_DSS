import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/features/dashboard/trend/trend_card.dart';
import 'package:pitchy/features/dashboard/trend/trend_painter.dart';
import 'package:pitchy/features/dashboard/trend/trend_series.dart';
import 'package:pitchy/shared/models/weather.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';

import '../helpers.dart';

ConsolidatedWeather _weather({int hours = 5, bool rainGaps = false}) {
  final json = trendWeatherJson(now: testNow, kickoff: testKickoff, hours: hours);
  if (rainGaps) {
    // Missing hours late in the window: the backend sends no value there.
    final rain = (json['quantities']! as List).cast<Map<String, Object?>>().firstWhere(
      (q) => q['quantity'] == 'rain',
    );
    final slots = (rain['slots']! as List).cast<Map<String, Object?>>();
    for (final slot in slots.skip(slots.length - 3)) {
      slot
        ..['value'] = null
        ..['source_id'] = null
        ..['state'] = null
        ..['range'] = null
        ..['by_source'] = <Object?>[];
    }
  }
  return ConsolidatedWeather.fromJson(json);
}

Future<void> _pump(
  WidgetTester tester,
  ConsolidatedWeather w, {
  double textScale = 1,
  Size size = const Size(390, 844),
  ValueChanged<int>? onNeed,
}) => pumpThemed(
  tester,
  MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: TrendCard(
        weather: w,
        matchKickoff: testKickoff,
        now: testNow,
        onNeedHours: onNeed,
      ),
    ),
  ),
  size: size,
);

Finder _menu(String label) => find.byWidgetPredicate(
  (w) => w is DropdownMenu && w.label is Text && (w.label! as Text).data == label,
);

Future<void> _choose(WidgetTester tester, String menu, String entry) async {
  await tester.tap(_menu(menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entry).hitTestable().last);
  await tester.pumpAndSettle();
}

TrendChartStyle _style(TextScaler scaler) => TrendChartStyle(
  line: const Color(0xFF0000FF),
  muted: const Color(0xFF888888),
  grid: const Color(0xFFCCCCCC),
  pastBand: const Color(0xFFDDDDDD),
  surface: const Color(0xFFFFFFFF),
  marker: const Color(0xFF888888),
  label: const TextStyle(fontSize: 11, fontFamily: 'Switzer'),
  textScaler: scaler,
  sourceColor: (_) => const Color(0xFFFF0000),
);

TrendSeries _series(ConsolidatedWeather w, String quantity, TrendRange range) => TrendSeries.build(
  w,
  w.quantities.firstWhere((q) => q.quantity == quantity),
  range,
  matchKickoff: testKickoff,
);

/// Records the paints of every drawRect, ignoring the rest.
class _Recorder implements Canvas {
  final rects = <Paint>[];
  final lines = <Paint>[];

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(paint);

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines.add(paint);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(loadAppFonts);

  test('the new ranges request only what they need, within the backend limit', () {
    expect(TrendRange.kickoffPlus6.requestHours, 6);
    expect(TrendRange.kickoffPlus12.requestHours, 12);
    expect(TrendRange.kickoffPlus24.requestHours, 24);
    for (final r in TrendRange.values) {
      expect(r.requestHours, inInclusiveRange(1, trendMaxHours), reason: r.label);
    }
    // The first four ranges keep the default request.
    expect(TrendRange.kickoffPlus5.requestHours, trendHours);
    expect(TrendRange.sixBefore.requestHours, trendHours);
  });

  testWidgets('the Range menu offers the new ranges and asks only when not covered', (
    tester,
  ) async {
    final asked = <int>[];
    await _pump(tester, _weather(), onNeed: asked.add);
    await tester.tap(_menu('Range'));
    await tester.pumpAndSettle();
    for (final r in ['Kickoff to +6 h', 'Kickoff to +12 h', 'Kickoff to +24 h']) {
      expect(find.text(r), findsWidgets, reason: r);
    }
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await _choose(tester, 'Range', 'Kickoff to +5 h (match and after)');
    expect(asked, isEmpty);
    await _choose(tester, 'Range', 'Kickoff to +12 h');
    expect(asked, [12]);
  });

  testWidgets('a reply that already holds 24 h needs no request', (tester) async {
    final asked = <int>[];
    await _pump(tester, _weather(hours: 24), onNeed: asked.add);
    await _choose(tester, 'Range', 'Kickoff to +24 h');
    expect(asked, isEmpty);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('24 h at 360 px, text x$scale: no overflow, labels do not overlap', (
      tester,
    ) async {
      await _pump(
        tester,
        _weather(hours: 24),
        textScale: scale,
        size: const Size(360, 1800),
      );
      await _choose(tester, 'Range', 'Kickoff to +24 h');
      expect(tester.takeException(), isNull);

      final w = _weather(hours: 24);
      final series = _series(w, 'air_temperature', TrendRange.kickoffPlus24);
      final layout = TrendLayout(series, const Size(328, 330), _style(TextScaler.linear(scale)));
      final every = layout.labelEvery;
      final hourWidth = layout.plot.width / series.hours;
      final widest = layout.painter('12 PM', mono: true).width;
      expect(every * hourWidth, greaterThanOrEqualTo(widest + 4));
      expect(every, greaterThan(1));
    });
  }

  test('rain draws bars with an accent outline, zero as a flat bar, gaps as nothing', () {
    final w = _weather(hours: 12, rainGaps: true);
    final series = _series(w, 'rain', TrendRange.kickoffPlus12);
    expect(series.kind, TrendKind.bars);
    final gaps = series.points.where((p) => !p.hasValue).length;
    expect(gaps, greaterThan(0));
    final before = _series(w, 'rain', TrendRange.sixBefore);
    expect(before.points.where((p) => p.hasValue && p.value == 0), isNotEmpty);

    final style = _style(TextScaler.noScaling);
    final rec = _Recorder();
    const size = Size(328, 330);
    TrendPainter(series: series, style: style, selected: null).paint(rec, size);
    final light = style.line.withValues(alpha: 0.28).toARGB32();
    final fills = rec.rects.where((p) => p.color.toARGB32() == light).length;
    final outlines = rec.rects
        .where((p) => p.style == PaintingStyle.stroke && p.color == style.line)
        .length;
    final drawn = series.points.where((p) => p.hasValue && p.current).length;
    expect(fills, drawn); // one bar per hour with a value; none for a gap
    expect(outlines, drawn);
    expect(drawn, lessThan(series.points.length));
  });

  testWidgets('wind speed shows the direction in the readout, as where it comes from', (
    tester,
  ) async {
    await _pump(tester, _weather());
    await _choose(tester, 'Value', 'Wind speed');
    expect(find.textContaining('3–4 PM PHT · 3.4 m/s'), findsOneWidget);
    expect(find.textContaining('from N (20°)'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.tap(find.byType(CustomPaint).last);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.textContaining('from '), findsWidgets);
    // Wind direction itself is not offered as a value.
    await tester.tap(_menu('Value'));
    await tester.pumpAndSettle();
    expect(find.text('Wind direction'), findsNothing);
  });

  test('wind arrows are drawn for the labelled hours only when direction exists', () {
    final w = _weather();
    final wind = _series(w, 'wind_speed', TrendRange.kickoffPlus5);
    final temp = _series(w, 'air_temperature', TrendRange.kickoffPlus5);
    expect(wind.hasDirections, isTrue);
    expect(temp.hasDirections, isFalse);
    expect(TrendSeries.compass(350), 'N');
    expect(TrendSeries.compass(45), 'NE');
    expect(TrendSeries.compass(225), 'SW');
    final style = _style(TextScaler.noScaling);
    final a = _Recorder(), b = _Recorder();
    TrendPainter(series: wind, style: style, selected: null).paint(a, const Size(328, 330));
    TrendPainter(series: temp, style: style, selected: null).paint(b, const Size(328, 330));
    final accentLines = a.lines.where((p) => p.color == style.line && p.strokeWidth == 1.5);
    expect(accentLines.length, greaterThanOrEqualTo(3)); // shaft and head, per arrow
    expect(
      b.lines.where((p) => p.color == style.line && p.strokeWidth == 1.5),
      isEmpty,
    );
  });
}
