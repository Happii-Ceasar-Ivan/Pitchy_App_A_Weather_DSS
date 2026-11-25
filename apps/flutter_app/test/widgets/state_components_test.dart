import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/errors/api_failure.dart';
import 'package:pitchy/core/state/loadable.dart';
import 'package:pitchy/core/theme/app_theme.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';
import 'package:pitchy/shared/models/alerts.dart';
import 'package:pitchy/shared/models/weather.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/widgets/data_state_badge.dart';
import 'package:pitchy/shared/widgets/request_states.dart';
import 'package:pitchy/shared/widgets/source_rail.dart';
import 'package:pitchy/shared/widgets/weather_value_card.dart';

import '../helpers.dart';

void main() {
  testWidgets('each data state badge shows its word and announces it', (tester) async {
    for (final s in WeatherDataState.values) {
      await pumpThemed(tester, DataStateBadge(state: s));
      expect(find.text(s.name.toUpperCase()), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Data state: ', caseSensitive: false)), findsOneWidget);
    }
  });

  testWidgets('LoadableView shows loading, data and error', (tester) async {
    await pumpThemed(
      tester,
      SizedBox(
        height: 300,
        child: LoadableView<String>(value: const Loading(), builder: (_, v) => Text(v)),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await pumpThemed(
      tester,
      SizedBox(
        height: 300,
        child: LoadableView<String>(value: const Loaded('ok'), builder: (_, v) => Text(v)),
      ),
    );
    expect(find.text('ok'), findsOneWidget);

    var retried = false;
    await pumpThemed(
      tester,
      SizedBox(
        height: 400,
        child: LoadableView<String>(
          value: const Failed(NetworkFailure()),
          builder: (_, v) => Text(v),
          onRetry: () => retried = true,
        ),
      ),
    );
    expect(find.text('No connection'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('a 429 says when to try again, in PHT, and offers retry only after it', (
    tester,
  ) async {
    final failure = ApiError.fromEnvelope(
      429,
      errorJson('RATE_LIMITED', 'Later.', retryAt: DateTime.utc(2026, 11, 23, 7, 15)),
    );
    await pumpThemed(
      tester,
      SizedBox(
        height: 400,
        child: ErrorState(
          failure: failure,
          onRetry: () {},
          clock: () => DateTime.utc(2026, 11, 23, 7, 5),
        ),
      ),
    );
    expect(find.textContaining('3:15 PM PHT'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    await tester.pump(const Duration(minutes: 10, seconds: 2));
    expect(find.text('You can try again now'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a 501 reads as "Not available yet", not as a failure to retry', (tester) async {
    final failure = ApiError.fromEnvelope(501, errorJson('NOT_IMPLEMENTED', 'Not yet.'));
    await pumpThemed(
      tester,
      SizedBox(
        height: 400,
        child: ErrorState(failure: failure, onRetry: () {}),
      ),
    );
    expect(find.text('Not available yet'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('saved-copy banner never claims the data is current', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(PitchyPalette.light),
        home: Builder(
          builder: (context) => Scaffold(body: NoticeBanner.savedCopy(context, savedAt: testNow)),
        ),
      ),
    );
    expect(find.textContaining('Saved copy from 12:00 PM PHT, not live'), findsOneWidget);
    expect(find.textContaining('Current'), findsNothing);
  });

  group('source rail', () {
    // Real fonts: row shapes must be compared as users will see them.
    setUpAll(loadAppFonts);

    WeatherStatus status(MockScenario s) =>
        WeatherStatus.fromJson(weatherStatusJson(s, now: testNow, kickoff: testKickoff));

    Future<void> pumpRail(WidgetTester tester, WeatherStatus st, {bool expanded = true}) =>
        pumpThemed(
          tester,
          SourceRail(
            sources: st.sources,
            checkedAt: st.checkedAt,
            coverage: st.coverage,
            kickoff: testKickoff,
            now: testNow,
            initiallyExpanded: expanded,
          ),
        );

    testWidgets('the collapsed rail has the skeleton shape, in every backend state', (
      tester,
    ) async {
      await pumpThemed(tester, const SourceRailSkeleton());
      final skeleton = tester.getSize(find.byType(SourceRailSkeleton)).height;
      for (final scenario in [
        MockScenario.allCurrent,
        MockScenario.someStale,
        MockScenario.updating,
        MockScenario.missing,
        MockScenario.unavailable,
      ]) {
        await pumpRail(tester, status(scenario), expanded: false);
        final rail = tester.getSize(find.byType(SourceRail)).height;
        expect((rail - skeleton).abs(), lessThan(1.5), reason: scenario.name);
      }
    });

    testWidgets('collapsed: names and state words side by side; opens to the full lines', (
      tester,
    ) async {
      await pumpRail(tester, status(MockScenario.someStale), expanded: false);
      expect(find.text('Open-Meteo'), findsOneWidget);
      expect(find.text('STALE'), findsOneWidget);
      expect(find.text('CURRENT'), findsNWidgets(2));
      expect(find.byType(ValidityBar), findsNothing);
      final names = [
        for (final n in ['Open-Meteo', 'PAGASA ATMO', 'PAGASA ECMWF'])
          tester.getTopLeft(find.text(n)),
      ];
      expect(names.map((o) => o.dy).toSet().length, 1, reason: 'one horizontal row');
      await tester.tap(find.byTooltip('Show source details'));
      await tester.pumpAndSettle();
      expect(find.byType(ValidityBar), findsNWidgets(3));
      expect(find.textContaining('9 h ago'), findsOneWidget);
    });

    testWidgets('shows every source with the backend state, never upgraded', (tester) async {
      await pumpRail(tester, status(MockScenario.someStale));
      expect(find.text('Open-Meteo'), findsOneWidget);
      expect(find.text('PAGASA ATMO'), findsOneWidget);
      expect(find.text('STALE'), findsOneWidget);
      expect(find.text('CURRENT'), findsNWidgets(2));
      expect(find.textContaining('9 h ago'), findsOneWidget);
      expect(find.textContaining('Current until 2:00 PM PHT'), findsNWidgets(2));
    });

    testWidgets('unavailable shows the backend limitation message', (tester) async {
      await pumpRail(tester, status(MockScenario.unavailable));
      expect(find.text('UNAVAILABLE'), findsOneWidget);
      expect(find.text('The last fetch from this source failed.'), findsOneWidget);
    });

    testWidgets('missing and updating are labelled', (tester) async {
      await pumpRail(tester, status(MockScenario.missing));
      expect(find.text('MISSING'), findsNWidgets(3));
      await pumpRail(tester, status(MockScenario.updating));
      expect(find.text('UPDATING'), findsNWidgets(3));
    });
  });

  group('weather cards (P-13)', () {
    ConsolidatedWeather weatherFor(MockScenario s) => ConsolidatedWeather.fromJson(
      consolidatedWeatherJson(scenario: s, now: testNow, kickoff: testKickoff),
    );

    Future<void> pumpGrid(WidgetTester tester, ConsolidatedWeather w) =>
        pumpThemed(tester, WeatherCardGrid(weather: w, kickoff: testKickoff));

    testWidgets('at most 4 cards until "Show N more"', (tester) async {
      final w = weatherFor(MockScenario.allCurrent);
      await pumpGrid(tester, w);
      expect(find.byType(WeatherValueCard), findsNWidgets(4));
      await tester.tap(find.text('Show ${w.quantities.length - 4} more'));
      await tester.pumpAndSettle();
      expect(find.byType(WeatherValueCard), findsNWidgets(w.quantities.length));
    });

    testWidgets('collapsed: data only; expanded: source, timestamps and spread', (tester) async {
      await pumpGrid(tester, weatherFor(MockScenario.allCurrent));
      expect(find.text('Source'), findsNothing);
      await tester.tap(find.text('Heat index'));
      await tester.pumpAndSettle();
      expect(find.text('Source'), findsOneWidget);
      expect(find.text('PAGASA ATMO (panahon.gov.ph)'), findsOneWidget);
      expect(find.text('Fetched'), findsOneWidget);
      expect(find.text('Valid'), findsOneWidget);
      expect(find.textContaining('across 2 sources'), findsOneWidget);
    });

    testWidgets('values from a stale source are stamped STALE on the collapsed card', (
      tester,
    ) async {
      await pumpGrid(tester, weatherFor(MockScenario.someStale));
      // Heat index and Rain come from PAGASA ATMO, which is stale in this scenario.
      expect(find.text('STALE'), findsNWidgets(2));
    });

    testWidgets('no usable data is labelled, never shown as a number', (tester) async {
      await pumpGrid(tester, weatherFor(MockScenario.missing));
      expect(find.text('No value'), findsNWidgets(4));
      expect(find.text('UNAVAILABLE'), findsNWidgets(4));
    });

    testWidgets('expanded card takes a full row; other rows stay full and equal height', (
      tester,
    ) async {
      await pumpGrid(tester, weatherFor(MockScenario.someStale));
      await tester.tap(find.text('Air temperature'));
      await tester.pumpAndSettle();
      final cards = find.byType(WeatherValueCard);
      final expanded = tester.getSize(find.ancestor(of: find.text('Source'), matching: cards));
      final others = [
        for (final label in ['Heat index', 'Relative humidity'])
          tester.getRect(find.ancestor(of: find.text(label), matching: cards)),
      ];
      expect(expanded.width, greaterThan(others.first.width * 1.9));
      // The next two cards close up into one row beside each other, same height.
      expect(others[0].top, others[1].top);
      expect(others[0].height, others[1].height);
    });

    test('a slot without a state falls back to its source state, never Current', () {
      final json = consolidatedWeatherJson(
        scenario: MockScenario.someStale,
        now: testNow,
        kickoff: testKickoff,
      );
      final heat = (json['quantities']! as List).cast<Map<String, Object?>>()[1];
      ((heat['slots']! as List).cast<Map<String, Object?>>()[1])['state'] = null;
      final w = ConsolidatedWeather.fromJson(json);
      expect(slotState(w.quantities[1].slots[1], w.sources), WeatherDataState.stale);
    });

    test('short source names drop only the trailing domain', () {
      expect(shortSourceName('PAGASA ATMO (panahon.gov.ph)'), 'PAGASA ATMO');
      expect(shortSourceName('Open-Meteo'), 'Open-Meteo');
    });
  });

  test('alert text stays plain text in the model (rendered with Text, never HTML)', () {
    final alerts = VenueAlerts.fromJson(alertsJson(now: testNow, withAlert: true));
    expect(alerts.alerts.single.message, contains('<b>'));
  });
}
