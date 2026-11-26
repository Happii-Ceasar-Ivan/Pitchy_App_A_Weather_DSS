import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/app.dart';
import 'package:pitchy/core/config/app_config.dart';
import 'package:pitchy/core/config/app_info.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/core/storage/saved_copies.dart';
import 'package:pitchy/features/settings/update_check.dart';
import 'package:pitchy/features/settings/update_installer.dart';
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
  DateTime? now,
  UpdateChecker? updates,
  UpdateInstaller? updateInstaller,
  bool checkForUpdatesOnOpen = false,
  MockPitchyApi? api,
}) async {
  final clockNow = now ?? testNow;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final preferences = MemoryPreferences(prefs);
  final savedCopies = SavedCopyStore(preferences, clock: () => clockNow);
  api ??= MockPitchyApi(
    scenario: scenario,
    clock: () => clockNow,
    latency: latency,
    savedCopies: savedCopies,
  );
  await tester.pumpWidget(
    PitchyApp(
      config: AppConfig(apiBaseUrl: Uri.parse('https://api.example.test'), useMocks: true),
      info: testInfo,
      api: api,
      preferences: preferences,
      savedCopies: savedCopies,
      initialLocation: location,
      clock: () => clockNow,
      // Never calls GitHub from tests: no release published.
      updates:
          updates ??
          UpdateChecker(
            installedVersion: testInfo.version,
            client: MockClient((_) async => http.Response('{}', 404)),
          ),
      updateInstaller:
          updateInstaller ??
          UpdateInstaller(
            platform: const NoUpdatePlatform(),
            client: MockClient((_) async => http.Response('', 404)),
          ),
      checkForUpdatesOnOpen: checkForUpdatesOnOpen,
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return (api, preferences);
}

/// A saved active match, so the dashboard opens on it.
Map<String, String> withActiveMatch() => {PrefKeys.activeMatchId: rizalMemorialId};
