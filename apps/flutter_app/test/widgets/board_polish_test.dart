import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';
import 'package:pitchy/shared/models/match.dart';
import 'package:pitchy/shared/models/weather.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/widgets/kickoff_strip.dart';
import 'package:pitchy/shared/widgets/source_rail.dart';
import 'package:pitchy/shared/widgets/weather_value_card.dart';

import '../app_harness.dart';
import '../helpers.dart';

WeatherStatus _status(MockScenario s) =>
    WeatherStatus.fromJson(weatherStatusJson(s, now: testNow, kickoff: testKickoff));

SourceStatus _staleFetched(DateTime retrieved) {
  final base = _status(MockScenario.someStale).sources.firstWhere(
    (s) => s.state == WeatherDataState.stale,
  );
  return SourceStatus(
    sourceId: base.sourceId,
    sourceName: base.sourceName,
    state: WeatherDataState.stale,
    coversMatchTime: base.coversMatchTime,
    currentUntil: null,
    provenance: Provenance(
      sourceId: base.sourceId,
      sourceName: base.sourceName,
      retrievedAt: retrieved,
      sourceIssuedAt: null,
      forecastValidFrom: null,
      forecastValidUntil: null,
      expiresAt: null,
    ),
    limitations: const [],
  );
}

Widget _rail(List<SourceStatus> sources, {List<Attribution>? attributions}) {
  final st = _status(MockScenario.allCurrent);
  return SourceRail(
    sources: sources,
    checkedAt: testNow,
    coverage: st.coverage,
    kickoff: testKickoff,
    now: testNow,
    attributions: attributions,
    initiallyExpanded: true,
  );
}

void main() {
  setUpAll(loadAppFonts);

  group('S1 unit apart from value', () {
    testWidgets('unit is its own muted span; 2x2 grid fits at 360 px, 1.0x and 2.0x', (
      tester,
    ) async {
      final w = ConsolidatedWeather.fromJson(
        consolidatedWeatherJson(now: testNow, kickoff: testKickoff),
      );
      for (final scale in [1.0, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpThemed(
          tester,
          WeatherCardGrid(weather: w, kickoff: testKickoff),
          size: const Size(360, 780),
        );
        expect(tester.takeException(), isNull);
      }
      tester.platformDispatcher.textScaleFactorTestValue = 1.0;
      await pumpThemed(
        tester,
        WeatherCardGrid(weather: w, kickoff: testKickoff),
        size: const Size(360, 780),
      );
      final unit = w.quantities.first.unit;
      TextSpan? unitSpan;
      TextSpan? valueSpan;
      for (final p in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
        p.text.visitChildren((span) {
          if (span is TextSpan && span.text == ' $unit') unitSpan = span;
          if (span is TextSpan && span.text != null && num.tryParse(span.text!) != null) {
            valueSpan ??= span;
          }
          return true;
        });
      }
      expect(unitSpan, isNotNull);
      expect(valueSpan, isNotNull);
      expect(unitSpan!.style!.color, PitchyPalette.light.inkMuted);
      expect(unitSpan!.style!.fontSize, lessThan(valueSpan!.style!.fontSize!));
    });
  });

  group('S2 sources current in the kickoff strip', () {
    final match = MatchContext.fromJson(matchContextJson(kickoff: testKickoff, created: testNow));

    testWidgets('counts only Current from the given states', (tester) async {
      final sources = _status(MockScenario.someStale).sources;
      final current = sources.where((s) => s.state == WeatherDataState.current).length;
      expect(current, lessThan(sources.length));
      await pumpThemed(tester, KickoffStrip(match: match, sources: sources));
      expect(find.text('$current of ${sources.length} sources current'), findsOneWidget);
    });

    testWidgets('all current reads N of N; null or empty shows nothing', (tester) async {
      final sources = _status(MockScenario.allCurrent).sources;
      await pumpThemed(tester, KickoffStrip(match: match, sources: sources));
      expect(
        find.text('${sources.length} of ${sources.length} sources current'),
        findsOneWidget,
      );
      await pumpThemed(tester, KickoffStrip(match: match, sourcesPending: true));
      expect(find.textContaining('sources current'), findsNothing);
      await pumpThemed(tester, KickoffStrip(match: match, sources: const []));
      expect(find.textContaining('sources current'), findsNothing);
    });

    testWidgets('fits 360 px at 2.0x text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpThemed(
        tester,
        KickoffStrip(match: match, sources: _status(MockScenario.someStale).sources),
        size: const Size(360, 780),
      );
      expect(find.textContaining('sources current'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dashboard: hidden while weather loads, shown after', (tester) async {
      await pumpPitchyApp(
        tester,
        scenario: MockScenario.someStale,
        prefs: withActiveMatch(),
        latency: const Duration(seconds: 1),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 100));
      // Match loaded, weather still loading (each call takes 1 s).
      expect(find.textContaining('sources current'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.textContaining('sources current'), findsOneWidget);
      final shown = tester.widget<Text>(find.byKey(const ValueKey('sources-current')));
      expect(shown.data, matches(r'^\d of \d sources current$'));
    });
  });

  group('S3 Open-Meteo credit', () {
    testWidgets('caption and link show when Open-Meteo is a source', (tester) async {
      final w = ConsolidatedWeather.fromJson(
        consolidatedWeatherJson(now: testNow, kickoff: testKickoff),
      );
      await pumpThemed(
        tester,
        _rail(w.sources, attributions: w.attributions),
        size: const Size(360, 780),
      );
      expect(find.text('Weather data by '), findsOneWidget);
      expect(find.text('Open-Meteo.com'), findsOneWidget);
      final link = tester.widget<Text>(find.text('Open-Meteo.com'));
      expect(link.style!.color, PitchyPalette.light.accent);
    });

    testWidgets('absent when Open-Meteo is not among the sources', (tester) async {
      final others = _status(
        MockScenario.allCurrent,
      ).sources.where((s) => s.sourceId != openMeteoId).toList();
      await pumpThemed(tester, _rail(others, attributions: const []));
      expect(find.text('Open-Meteo.com'), findsNothing);
    });
  });

  group('S10 fetched age beyond 24 h', () {
    testWidgets('over 24 h adds the absolute PHT time with the day', (tester) async {
      // testNow is Mon 23 Nov 12:00 PM PHT; 2 days earlier is Sat 21 Nov, 11:00 AM PHT.
      final fetched = DateTime.utc(2026, 11, 21, 3);
      await pumpThemed(tester, _rail([_staleFetched(fetched)]));
      expect(
        find.textContaining('Fetched 2 d ago (Sat 21 Nov, 11:00 AM PHT)', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('under 24 h is unchanged', (tester) async {
      final fetched = testNow.subtract(const Duration(hours: 5));
      await pumpThemed(tester, _rail([_staleFetched(fetched)]));
      expect(
        find.textContaining('Fetched 7:00 AM PHT · 5 h ago', findRichText: true),
        findsOneWidget,
      );
    });
  });
}
