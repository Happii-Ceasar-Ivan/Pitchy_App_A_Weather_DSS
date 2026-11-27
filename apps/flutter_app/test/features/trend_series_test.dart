import 'package:flutter_test/flutter_test.dart';
import 'package:pitchy/features/dashboard/trend/trend_series.dart';
import 'package:pitchy/shared/models/weather.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';

import '../helpers.dart';

ConsolidatedWeather _trend({
  MockScenario scenario = MockScenario.allCurrent,
  bool trendContract = true,
  DateTime? now,
}) => ConsolidatedWeather.fromJson(
  trendWeatherJson(
    scenario: scenario,
    now: now ?? testNow,
    kickoff: testKickoff,
    trendContract: trendContract,
  ),
);

TrendSeries _series(
  ConsolidatedWeather w,
  String quantity,
  TrendRange range,
) => TrendSeries.build(
  w,
  w.quantities.firstWhere((q) => q.quantity == quantity),
  range,
  matchKickoff: testKickoff,
);

void main() {
  group('ranges', () {
    test('each preset holds exactly its hours', () {
      final w = _trend();
      const h = Duration(hours: 1);
      for (final (range, count, first) in [
        (TrendRange.sixBefore, 6, testKickoff.subtract(h * 6)),
        (TrendRange.twoBefore, 2, testKickoff.subtract(h * 2)),
        (TrendRange.kickoffPlus3, 3, testKickoff),
        (TrendRange.kickoffPlus5, 5, testKickoff),
      ]) {
        final s = _series(w, 'air_temperature', range);
        expect(s.points, hasLength(count), reason: range.name);
        expect(s.points.first.from, first, reason: range.name);
        expect(s.end, testKickoff.add(h * range.toHours), reason: range.name);
      }
    });

    test('all four presets come from one reply with the P-27 fields', () {
      expect(availableRanges(_trend(), testKickoff), [
        for (final r in TrendRange.values)
          if (!r.isLong) r,
      ]);
    });

    test('an older backend (no kickoff_at) hides the hours before kickoff', () {
      expect(availableRanges(_trend(trendContract: false), testKickoff), [
        TrendRange.kickoffPlus3,
        TrendRange.kickoffPlus5,
      ]);
    });

    test('a kickoff at :30 counts hours from the hour it falls in', () {
      final json = trendWeatherJson(
        now: testNow,
        kickoff: testKickoff.add(const Duration(minutes: 30)),
      );
      final w = ConsolidatedWeather.fromJson(json);
      final s = TrendSeries.build(
        w,
        w.quantities.first,
        TrendRange.kickoffPlus3,
        matchKickoff: testKickoff,
      );
      expect(s.points.first.from, testKickoff);
      expect(s.kickoff, testKickoff.add(const Duration(minutes: 30)));
    });
  });

  group('values list', () {
    test('only quantities with a value, in tile order, without wind direction', () {
      final names = chartableQuantities(_trend()).map((q) => q.quantity).toList();
      expect(names, [
        'air_temperature',
        'heat_index',
        'relative_humidity',
        'rain',
        'rain_probability',
        'wind_speed',
      ]);
      expect(names, isNot(contains('wind_direction')));
      expect(names, isNot(contains('cloud_cover'))); // every hour null
    });
  });

  group('gaps and states', () {
    test('a null hour is a gap: never joined, never filled', () {
      final s = _series(_trend(), 'heat_index', TrendRange.kickoffPlus5);
      expect(s.points.map((p) => p.value), [40, 38, 36, null, 34]);
      expect(s.gapCount, 1);
      final joined = s.links.map((l) => (l.from, l.to)).toList();
      expect(joined, [(0, 1), (1, 2)]);
      expect(joined, isNot(contains((2, 3))));
      expect(joined, isNot(contains((3, 4))));
    });

    test('hours before the fetch started are gaps', () {
      final s = _series(_trend(), 'air_temperature', TrendRange.sixBefore);
      expect(s.points.take(2).map((p) => p.value), [null, null]);
      expect(s.points.first.state, WeatherDataState.unavailable);
    });

    test('stale hours stay stale and their links are dashed', () {
      final s = _series(
        _trend(scenario: MockScenario.someStale),
        'heat_index',
        TrendRange.kickoffPlus3,
      );
      expect(s.withValues.every((p) => p.state == WeatherDataState.stale), isTrue);
      expect(s.links.every((l) => l.dashed), isTrue);
      expect(s.overallState, WeatherDataState.stale);
    });

    test('current hours are drawn solid', () {
      final s = _series(_trend(), 'air_temperature', TrendRange.kickoffPlus3);
      expect(s.links.any((l) => l.dashed), isFalse);
      expect(s.overallState, WeatherDataState.current);
    });

    test('a range with no value at all is empty and Missing', () {
      final w = _trend();
      final s = TrendSeries.build(
        w,
        w.quantities.firstWhere((q) => q.quantity == 'cloud_cover'),
        TrendRange.kickoffPlus3,
        matchKickoff: testKickoff,
      );
      expect(s.isEmpty, isTrue);
      expect(s.overallState, WeatherDataState.missing);
      expect(s.summary(now: testNow), contains('no source has a value'));
    });

    test('a source change mid-range keeps each hour\'s own source and label', () {
      final s = _series(_trend(), 'rain', TrendRange.kickoffPlus3);
      expect(s.points.every((p) => p.sourceId != null), isTrue);
      expect(s.points.first.sourceId, 'pagasa_atmo');
      expect(s.points.last.sourceId, 'open_meteo');
      expect(s.points.last.fallbackLabel, contains('Open-Meteo'));
      expect(s.usesSource('open_meteo'), isTrue);
      expect(s.kind, TrendKind.bars);
    });

    test('hours that ended before checked_at are past forecasts', () {
      // checked_at is 3 h before kickoff in the fixture.
      final s = _series(_trend(), 'air_temperature', TrendRange.sixBefore);
      expect(s.points.where((p) => p.past), hasLength(3));
      expect(s.summary(now: testNow), contains('forecasts, not measurements'));
    });
  });

  group('axis', () {
    test('percentages use 0–100', () {
      final s = _series(_trend(), 'relative_humidity', TrendRange.kickoffPlus3);
      expect((s.axis.min, s.axis.max), (0, 100));
    });

    test('rain bars start at 0', () {
      final s = _series(_trend(), 'rain', TrendRange.kickoffPlus5);
      expect(s.axis.min, 0);
      expect(s.axis.max, greaterThanOrEqualTo(2.0));
    });

    test('other values fit the data with round ticks and no thresholds', () {
      final s = _series(_trend(), 'air_temperature', TrendRange.kickoffPlus5);
      expect(s.axis.min, lessThanOrEqualTo(30.1));
      expect(s.axis.max, greaterThanOrEqualTo(32.4));
      expect(s.axis.ticks.first, s.axis.min);
      expect(s.axis.ticks.last, s.axis.max);
      expect(s.axis.ticks.length, inInclusiveRange(2, 6));
    });

    test('a flat series still has room', () {
      final a = TrendAxis.forValues([20, 20], unit: '°C', kind: TrendKind.line);
      expect(a.max, greaterThan(a.min));
    });
  });

  group('labels', () {
    test('hour ranges are PHT and name the day when it isn\'t today', () {
      final s = _series(_trend(), 'air_temperature', TrendRange.kickoffPlus3);
      // Kickoff 07:00 UTC = 3 PM PHT.
      expect(TrendSeries.hourRange(s.points.first, now: testNow), '3–4 PM PHT');
      final tomorrow = testNow.subtract(const Duration(days: 1));
      expect(TrendSeries.hourRange(s.points.first, now: tomorrow), startsWith('Mon 23 Nov, '));
    });

    test('an hour crossing noon names both halves', () {
      final p = TrendPoint(
        from: DateTime.utc(2026, 11, 23, 3),
        until: DateTime.utc(2026, 11, 23, 4),
        value: 1,
        state: WeatherDataState.current,
        sourceId: 'open_meteo',
        sourceName: 'Open-Meteo',
        fallbackLabel: null,
        range: null,
        past: false,
      );
      expect(TrendSeries.hourRange(p, now: testNow), '11 AM–12 PM PHT');
      expect(TrendSeries.hourLabel(p.from), '11 AM');
    });

    test('the summary names values, gaps, source and range', () {
      final s = _series(_trend(), 'heat_index', TrendRange.kickoffPlus5);
      final text = s.summary(now: testNow);
      expect(
        text,
        startsWith('Heat index (PAGASA), Kickoff to +5 h (match and after): 40 °C at 3–4 PM PHT'),
      );
      expect(text, contains('highest 40 °C'));
      expect(text, contains('1 hour has no value.'));
      expect(text, contains('Source: PAGASA ATMO'));
    });
  });
}
