// W1 motion: the weather card opens in place, the trend chart crossfades on a
// Value change, the selected-hour line glides on a spring, the scrub ticks at
// the first and last hour, and standalone buttons press (P-29).

import 'dart:ui' show AccessibilityFeatures;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/theme/motion.dart';
import 'package:pitchy/features/dashboard/trend/trend_card.dart';
import 'package:pitchy/features/dashboard/trend/trend_painter.dart';
import 'package:pitchy/shared/models/weather.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/widgets/press_scale.dart';
import 'package:pitchy/shared/widgets/weather_value_card.dart';

import '../app_harness.dart';
import '../helpers.dart';

ConsolidatedWeather _trend() => ConsolidatedWeather.fromJson(
  trendWeatherJson(
    scenario: MockScenario.allCurrent,
    now: testNow,
    kickoff: testKickoff,
    trendContract: true,
  ),
);

Future<void> _pumpCard(WidgetTester tester, {bool reduced = false}) => pumpThemed(
  tester,
  MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: TrendCard(weather: _trend(), matchKickoff: testKickoff, now: testNow),
    ),
  ),
);

final _charts = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is TrendPainter);

TrendPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_charts.last).painter! as TrendPainter;

TrendLayout _layout(WidgetTester tester) {
  final p = _painter(tester);
  return TrendLayout(p.series, tester.getSize(_charts.last), p.style);
}

/// The selected-hour line's x, in the chart's own coordinates.
double _markerX(WidgetTester tester) => _painter(tester).markerX(_layout(tester))!;

/// The global point in the middle of hour [i], halfway down the chart.
Offset _hourPoint(WidgetTester tester, int i) {
  final l = _layout(tester);
  final box = tester.getRect(_charts.last);
  return Offset(box.left + l.xOf(l.series.points[i].middle), box.center.dy);
}

String _readout(WidgetTester tester) =>
    tester.widget<Text>(find.textContaining(' PHT · ').first).textSpan!.toPlainText();

int _selectedIndex(WidgetTester tester) => _painter(tester).selected!;

void main() {
  setUpAll(loadAppFonts);

  group('weather card opens in place', () {
    Finder card(String quantity) =>
        find.byWidgetPredicate((w) => w is WeatherValueCard && w.quantity.quantity == quantity);

    double detailsHeight(WidgetTester tester, String quantity) => tester
        .getSize(find.descendant(of: card(quantity), matching: find.byType(AnimatedSize)))
        .height;

    Future<String> firstQuantity(WidgetTester tester) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch(), size: const Size(390, 2400));
      return tester.widget<WeatherValueCard>(find.byType(WeatherValueCard).first).quantity.quantity;
    }

    testWidgets('keeps its element, animates open, and fades its detail in', (tester) async {
      final q = await firstQuantity(tester);
      final before = card(q).evaluate().single;
      final closed = detailsHeight(tester, q);
      await tester.tap(card(q));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(identical(card(q).evaluate().single, before), isTrue, reason: 'same element');
      final mid = detailsHeight(tester, q);
      final opacity = tester
          .widget<Opacity>(find.descendant(of: card(q), matching: find.byType(Opacity)).first)
          .opacity;
      expect(opacity, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      final full = detailsHeight(tester, q);
      expect(mid, greaterThan(closed));
      expect(mid, lessThan(full));
      expect(identical(card(q).evaluate().single, before), isTrue);
    });

    testWidgets('reduced: fully open after one pump, no running ticker', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = _NoAnimations();
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final q = await firstQuantity(tester);
      final closed = detailsHeight(tester, q);
      await tester.tap(card(q));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final open = detailsHeight(tester, q);
      expect(open, greaterThan(closed));
      await tester.pump(PitchyMotion.quick); // the short opacity fade
      expect(detailsHeight(tester, q), open);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('360 px at 200 % text: the open card has no overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpPitchyApp(tester, prefs: withActiveMatch(), size: const Size(360, 3200));
      await tester.tap(find.byType(WeatherValueCard).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('trend Value switch', () {
    Future<void> pickHumidity(WidgetTester tester) async {
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is DropdownMenu && w.label is Text && (w.label! as Text).data == 'Value',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Relative humidity').hitTestable().last);
    }

    testWidgets('the chart crossfades; the readout is new on the first pump', (tester) async {
      await _pumpCard(tester);
      expect(_charts, findsOneWidget);
      expect(_readout(tester), contains('°C'));
      await pickHumidity(tester);
      // The first frame that holds the new value: its chart fades in beside
      // the old one, and its readout is already the new text.
      for (var i = 0; i < 5 && _charts.evaluate().length < 2; i++) {
        await tester.pump();
      }
      expect(_readout(tester), contains('%'));
      expect(_readout(tester), isNot(contains('°C')));
      expect(_charts, findsNWidgets(2), reason: 'old and new chart while fading');
      await tester.pump(PitchyMotion.standard);
      await tester.pumpAndSettle();
      expect(_charts, findsOneWidget);
    });
  });

  group('selected-hour marker', () {
    testWidgets('glides to the tapped hour; the readout and selection change at once', (
      tester,
    ) async {
      await _pumpCard(tester);
      final from = _selectedIndex(tester);
      final oldX = _markerX(tester);
      final target = from + 1;
      final newText = _readout(tester);
      await tester.tapAt(_hourPoint(tester, target));
      await tester.pump(); // the rebuild with the new selection
      expect(_selectedIndex(tester), target);
      expect(_readout(tester), isNot(newText));
      final newX = _layout(tester).xOf(_layout(tester).series.points[target].middle);
      expect(newX, greaterThan(oldX));
      await tester.pump(const Duration(milliseconds: 60));
      final mid = _markerX(tester);
      expect(mid, greaterThan(oldX));
      expect(mid, lessThan(newX));
      await tester.pumpAndSettle();
      expect(_markerX(tester), closeTo(newX, 0.01));
    });

    testWidgets('keyboard moves glide too', (tester) async {
      await _pumpCard(tester);
      await tester.tapAt(_hourPoint(tester, 0));
      await tester.pumpAndSettle();
      final oldX = _markerX(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final newX = _layout(tester).xOf(_layout(tester).series.points[1].middle);
      expect(_markerX(tester), inExclusiveRange(oldX, newX));
      await tester.pumpAndSettle();
    });

    testWidgets('reduced: the marker is at the new hour after one pump, no ticker', (
      tester,
    ) async {
      await _pumpCard(tester, reduced: true);
      final target = _selectedIndex(tester) + 1;
      await tester.tapAt(_hourPoint(tester, target));
      await tester.pump();
      final newX = _layout(tester).xOf(_layout(tester).series.points[target].middle);
      expect(_markerX(tester), closeTo(newX, 0.01));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('a scrub follows the finger without the spring', (tester) async {
      await _pumpCard(tester);
      final g = await tester.startGesture(_hourPoint(tester, 2));
      await tester.pump();
      await g.moveTo(_hourPoint(tester, 1));
      await tester.pump();
      await g.moveTo(_hourPoint(tester, 0));
      await tester.pump();
      final l = _layout(tester);
      expect(_selectedIndex(tester), 0);
      expect(_markerX(tester), closeTo(l.xOf(l.series.points[0].middle), 0.01));
      await g.up();
      await tester.pumpAndSettle();
    });
  });

  group('edge haptic', () {
    testWidgets('one tick per arrival at the first or last hour', (tester) async {
      var ticks = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'HapticFeedback.vibrate' &&
            call.arguments == 'HapticFeedbackType.selectionClick') {
          ticks++;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pumpCard(tester);
      final last = _layout(tester).series.points.length - 1;
      final g = await tester.startGesture(_hourPoint(tester, 1));
      await tester.pump();
      expect(ticks, 0);
      await g.moveTo(_hourPoint(tester, 0));
      await tester.pump();
      expect(ticks, 1);
      // Held at the edge (and a little past it): no more ticks.
      for (var i = 0; i < 4; i++) {
        await g.moveBy(const Offset(-3, 0));
        await tester.pump();
      }
      expect(ticks, 1);
      await g.moveTo(_hourPoint(tester, 1));
      await tester.pump();
      expect(ticks, 1);
      await g.moveTo(_hourPoint(tester, last));
      await tester.pump();
      expect(ticks, 2);
      await g.moveBy(const Offset(2, 0));
      await tester.pump();
      expect(ticks, 2);
      await g.up();
      await tester.pumpAndSettle();
      // A tap on an edge hour is not a scrub.
      await tester.tapAt(_hourPoint(tester, 0));
      await tester.pumpAndSettle();
      expect(ticks, 2);
    });
  });

  group('press scale on the dashboard', () {
    testWidgets('buttons press; weather cards do not', (tester) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch(), size: const Size(390, 2400));
      expect(
        find.ancestor(of: find.byTooltip('Refresh'), matching: find.byType(PitchyPressScale)),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: find.text('Show as table'), matching: find.byType(PitchyPressScale)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(WeatherValueCard), matching: find.byType(PitchyPressScale)),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byType(WeatherValueCard).first,
          matching: find.byType(PitchyPressScale),
        ),
        findsNothing,
      );
    });
  });
}

class _NoAnimations implements AccessibilityFeatures {
  @override
  bool get disableAnimations => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => false;
}
