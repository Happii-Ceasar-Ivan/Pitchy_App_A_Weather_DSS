// OpenWeather as a third forecast source (P-30): its own fixed line colour,
// a short label, and the visible "Weather data © OpenWeather" credit its
// licence (ODbL) asks for wherever its data is shown.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/theme/fixed_colors.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';
import 'package:pitchy/shared/models/weather.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/widgets/link_text.dart';
import 'package:pitchy/shared/widgets/source_rail.dart';
import 'package:pitchy/shared/widgets/weather_value_card.dart';

import '../app_harness.dart';
import '../helpers.dart';

Finder _creditLink(String name) => find.bySemanticsLabel('$name, opens in the browser');

void main() {
  setUpAll(loadAppFonts);

  group('line colour', () {
    for (final p in [PitchyPalette.light, PitchyPalette.dark]) {
      test('${p.brightness.name}: its own colour, not the fallback or another line', () {
        final c = p.lineFor(openWeatherId);
        expect(p.lines.containsKey(openWeatherId), isTrue);
        expect(c, isNot(p.inkMuted), reason: 'not the unknown-source fallback');
        final others = {...p.lines}..remove(openWeatherId);
        expect(others.values, isNot(contains(c)));
        expect(c, isNot(p.accent));
      });
    }

    test('never a hazard colour', () {
      const s = SafetyColors.fixed;
      for (final p in [PitchyPalette.light, PitchyPalette.dark]) {
        expect([s.advisory, s.warning, s.danger], isNot(contains(p.lineFor(openWeatherId))));
      }
    });
  });

  test('short label: the API product name is dropped', () {
    expect(shortSourceName('OpenWeather One Call 3.0'), 'OpenWeather');
    expect(shortSourceName('PAGASA ATMO (panahon.gov.ph)'), 'PAGASA ATMO');
    expect(shortSourceName('Open-Meteo'), 'Open-Meteo');
  });

  group('credit under the source rail', () {
    WeatherStatus status() => WeatherStatus.fromJson(
      weatherStatusJson(MockScenario.allCurrent, now: testNow, kickoff: testKickoff),
    );

    Future<void> pumpRail(WidgetTester tester, List<Attribution> attributions) => pumpThemed(
      tester,
      SourceRail(
        sources: status().sources,
        checkedAt: status().checkedAt,
        coverage: status().coverage,
        kickoff: testKickoff,
        now: testNow,
        attributions: attributions,
      ),
    );

    const ow = Attribution(
      sourceId: 'openweather',
      text: 'Weather data © OpenWeather',
      url: 'https://openweathermap.org/',
    );
    const om = Attribution(
      sourceId: 'open_meteo',
      text: 'Weather data by Open-Meteo.com',
      url: 'https://open-meteo.com/',
    );

    testWidgets('shown, with its link, when OpenWeather data is in the response', (tester) async {
      await pumpRail(tester, const [om, ow]);
      expect(find.text('Weather data © '), findsOneWidget);
      expect(_creditLink('OpenWeather'), findsOneWidget);
      expect(_creditLink('Open-Meteo.com'), findsOneWidget);
      expect(tester.getSize(find.byType(WeatherCredit).last).height, greaterThanOrEqualTo(48));
    });

    testWidgets('not shown when the backend lists no OpenWeather credit', (tester) async {
      await pumpRail(tester, const [om]);
      expect(find.text('Weather data © '), findsNothing);
      expect(_creditLink('Open-Meteo.com'), findsOneWidget);
    });
  });

  testWidgets('dashboard: rail label, credit and the trend footer credit', (tester) async {
    await pumpPitchyApp(tester, prefs: withActiveMatch(), size: const Size(390, 3200));
    expect(_creditLink('OpenWeather'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is LinkText && w.label == 'Weather data © OpenWeather'),
      findsOneWidget,
      reason: 'the trend chart footer credits it too',
    );
  });

  testWidgets('Credits page lists OpenWeather with its licence and link', (tester) async {
    await pumpPitchyApp(tester, location: Routes.credits, size: const Size(390, 1600));
    expect(find.text('Weather data © OpenWeather'), findsOneWidget);
    expect(find.textContaining('Open Database License (ODbL)'), findsOneWidget);
  });
}
