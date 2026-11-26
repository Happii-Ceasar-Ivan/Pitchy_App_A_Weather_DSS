// Renders the dashboard from live backend replies (fetched first, then served
// from memory) into .impeccable/review/live-*.png. Not part of the normal run:
//   flutter test test_live --update-goldens

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/app.dart';
import 'package:pitchy/core/config/app_config.dart';
import 'package:pitchy/core/config/app_info.dart';
import 'package:pitchy/core/network/http_pitchy_api.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/shared/models/alerts.dart';
import 'package:pitchy/shared/models/match.dart';
import 'package:pitchy/shared/models/weather.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';

/// Serves one live snapshot; everything else falls back to the mock.
class _LiveSnapshot extends MockPitchyApi {
  _LiveSnapshot(this.match, this.status, this.weather, this.trend, this.alerts)
    : super(latency: Duration.zero);
  final MatchContext match;
  final WeatherStatus status;
  final ConsolidatedWeather weather;

  /// The P-27 trend window (`hours_before=6&hours=5`).
  final ConsolidatedWeather trend;
  final VenueAlerts alerts;
  @override
  Future<MatchContext> getMatchContext(String id) async => match;
  @override
  Future<WeatherStatus> getWeatherStatus(String id) async => status;
  @override
  Future<ConsolidatedWeather> getWeather(String id, {int? hours, int? hoursBefore}) async =>
      hoursBefore == null ? weather : trend;
  @override
  Future<VenueAlerts> getAlerts(String id) async => alerts;
}

/// The test binding fakes HTTP; the base class makes real clients.
class _RealHttp extends HttpOverrides {}

Future<void> _fonts() async {
  final roboto = FontLoader('Roboto');
  for (final f in ['regular', 'medium', 'bold']) {
    roboto.addFont(rootBundle.load('assets/fonts/roboto-$f.ttf'));
  }
  await roboto.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? r'D:\dev\flutter';
  final icons = File('$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  final l = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
  await l.load();
}

void main() {
  setUpAll(_fonts);

  testWidgets('live dashboard', (tester) async {
    late _LiveSnapshot api;
    await tester.runAsync(() async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final http = HttpPitchyApi(baseUrl: Uri.parse(AppConfig.defaultApiBaseUrl));
        final now = DateTime.now().toUtc();
        final kickoff = DateTime.utc(now.year, now.month, now.day, now.hour + 4);
        final m = await http.createMatchContext(
          MatchContextCreate(venueScopeKey: 'rizal_memorial', kickoffAt: kickoff),
        );
        api = _LiveSnapshot(
          m,
          await http.getWeatherStatus(m.id),
          await http.getWeather(m.id),
          await http.getWeather(m.id, hours: 5, hoursBefore: 6),
          await http.getAlerts(m.id),
        );
      }, _RealHttp());
    });
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PitchyApp(
        config: AppConfig(apiBaseUrl: Uri.parse(AppConfig.defaultApiBaseUrl), useMocks: false),
        info: const AppInfo(version: '1.0.0', buildNumber: '1'),
        api: api,
        preferences: MemoryPreferences({PrefKeys.activeMatchId: api.match.id}),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(
      find.byType(PitchyApp),
      matchesGoldenFile('../.impeccable/review/live-phone.png'),
    );
    await tester.tap(find.byIcon(Icons.expand_more).first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(
      find.byType(PitchyApp),
      matchesGoldenFile('../.impeccable/review/live-phone-alert.png'),
    );
    // P-27: the hourly trend from the live trend window.
    await tester.scrollUntilVisible(
      find.text('Hourly trend'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(
      find.byType(PitchyApp),
      matchesGoldenFile('../.impeccable/review/live-phone-trend.png'),
    );
  });
}
