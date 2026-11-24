import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/app.dart';
import 'package:pitchy/core/config/app_config.dart';
import 'package:pitchy/core/config/app_info.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';

import 'helpers.dart';

const testInfo = AppInfo(version: '1.0.0', buildNumber: '1');

/// Pumps the whole app with the mock backend, in-memory preferences and a fixed
/// clock, at a given window size.
Future<(MockPitchyApi, MemoryPreferences)> pumpPitchyApp(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  MockScenario scenario = MockScenario.allCurrent,
  Map<String, String>? prefs,
  String location = Routes.dashboard,
  Duration latency = Duration.zero,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final api = MockPitchyApi(scenario: scenario, clock: () => testNow, latency: latency);
  final preferences = MemoryPreferences(prefs);
  await tester.pumpWidget(
    PitchyApp(
      config: AppConfig(apiBaseUrl: Uri.parse('https://api.example.test'), useMocks: true),
      info: testInfo,
      api: api,
      preferences: preferences,
      initialLocation: location,
      clock: () => testNow,
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return (api, preferences);
}

/// A saved active match, so the dashboard opens on it.
Map<String, String> withActiveMatch() => {PrefKeys.activeMatchId: rizalMemorialId};
