import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/shared/models/weather.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/widgets/weather_icons.dart';
import 'package:pitchy/shared/widgets/weather_value_card.dart';

import '../helpers.dart';

void main() {
  test('every quantity the backend sends has a matching icon (P-27 B)', () {
    const expected = {
      'air_temperature': Icons.thermostat,
      'heat_index': Icons.device_thermostat,
      'dew_point': Icons.water_drop_outlined,
      'relative_humidity': Icons.opacity,
      'rain': Icons.grain,
      'rain_probability': Icons.umbrella_outlined,
      'wind_speed': Icons.air,
      'wind_gusts': Icons.air,
      'wind_direction': Icons.explore_outlined,
      'cloud_cover': Icons.cloud_outlined,
      'shortwave_radiation': Icons.wb_sunny_outlined,
      'direct_normal_irradiance': Icons.wb_sunny_outlined,
      'diffuse_radiation': Icons.wb_sunny_outlined,
      'cape': Icons.stacked_line_chart,
    };
    for (final e in expected.entries) {
      expect(weatherIconFor(e.key), e.value, reason: e.key);
    }
  });

  test('CAPE never gets a storm or lightning icon', () {
    expect(weatherIconFor('cape'), isNot(anyOf(Icons.bolt, Icons.thunderstorm, Icons.flash_on)));
  });

  test('an unknown quantity gets no icon', () {
    expect(weatherIconFor('visibility'), isNull);
  });

  testWidgets('tiles show their icon, which screen readers skip', (tester) async {
    final semantics = tester.ensureSemantics();
    final w = ConsolidatedWeather.fromJson(
      consolidatedWeatherJson(now: testNow, kickoff: testKickoff),
    );
    await pumpThemed(tester, WeatherCardGrid(weather: w, kickoff: testKickoff));
    expect(find.byIcon(Icons.thermostat), findsOneWidget);
    expect(find.byIcon(Icons.device_thermostat), findsOneWidget);
    expect(find.byIcon(Icons.opacity), findsOneWidget);
    expect(find.byIcon(Icons.grain), findsOneWidget);
    // Decorative: inside ExcludeSemantics, and the spoken label is unchanged.
    final icon = find.byIcon(Icons.thermostat);
    expect(find.ancestor(of: icon, matching: find.byType(ExcludeSemantics)), findsWidgets);
    expect(find.bySemanticsLabel(RegExp(r'^Air temperature: \d')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a tile with an unknown quantity has no icon and keeps its label', (tester) async {
    final json = consolidatedWeatherJson(now: testNow, kickoff: testKickoff);
    final quantities = (json['quantities']! as List).cast<Map<String, Object?>>();
    quantities.first['quantity'] = 'visibility';
    final w = ConsolidatedWeather.fromJson(json);
    await pumpThemed(tester, WeatherCardGrid(weather: w, kickoff: testKickoff));
    expect(find.byIcon(Icons.thermostat), findsNothing);
    expect(find.text('Air temperature'), findsOneWidget);
  });

  testWidgets('the icon doesn\'t change the tile or skeleton height at 200 % text', (tester) async {
    final w = ConsolidatedWeather.fromJson(
      consolidatedWeatherJson(now: testNow, kickoff: testKickoff),
    );
    Future<double> labelRowHeight(Widget child) async {
      await pumpThemed(
        tester,
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: child,
        ),
      );
      return tester.getSize(find.byType(Card).first).height;
    }

    final loaded = await labelRowHeight(WeatherCardGrid(weather: w, kickoff: testKickoff));
    final skeleton = await labelRowHeight(const WeatherCardGridSkeleton());
    expect(loaded, closeTo(skeleton, 1));
  });
}
