// Review captures for the F5 saved copy (DEC-13), not part of the normal run.
//   flutter test test_review --plain-name f5 --update-goldens
// Output: .impeccable/review/ (git-ignored working material).
//
// Each shot seeds the device store with replies received 40 minutes earlier,
// then cold-starts the app with the mock backend offline.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/app.dart';
import 'package:pitchy/core/config/app_config.dart';
import 'package:pitchy/core/config/app_info.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/core/storage/saved_copies.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';

Future<void> _loadFonts() async {
  final switzer = FontLoader('Switzer');
  for (final w in ['Regular', 'Medium', 'Semibold', 'Bold']) {
    switzer.addFont(rootBundle.load('assets/fonts/switzer/Switzer-$w.otf'));
  }
  await switzer.load();
  final plex = FontLoader('IBMPlexMono');
  for (final w in ['Regular', 'Medium', 'SemiBold']) {
    plex.addFont(rootBundle.load('assets/fonts/ibm_plex_mono/IBMPlexMono-$w.ttf'));
  }
  await plex.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'D:\dev\flutter';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
  await loader.load();
}

final _now = DateTime.utc(2026, 11, 23, 4);
final _savedAt = _now.subtract(const Duration(minutes: 40));

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(
  WidgetTester tester,
  String name, {
  required Size size,
  String location = Routes.dashboard,
  PitchyThemeMode mode = PitchyThemeMode.light,
  MockScenario seededAs = MockScenario.someStale,
  double textScale = 1,
  bool online = false,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final prefs = MemoryPreferences({
    PrefKeys.themeMode: mode.name,
    PrefKeys.activeMatchId: rizalMemorialId,
  });

  // Earlier, online: the replies the app saved.
  final seed = MockPitchyApi(
    scenario: seededAs,
    clock: () => _savedAt,
    latency: Duration.zero,
    savedCopies: SavedCopyStore(prefs, clock: () => _savedAt),
  );
  await tester.runAsync(() async {
    await seed.getMatchContext(rizalMemorialId);
    await seed.getWeatherStatus(rizalMemorialId);
    await seed.getWeather(rizalMemorialId);
    await seed.getAlerts(rizalMemorialId);
    await seed.getAssessment(rizalMemorialId);
  });

  // Now: cold start with the server unreachable.
  final store = SavedCopyStore(prefs, clock: () => _now);
  await tester.pumpWidget(
    PitchyApp(
      config: AppConfig(apiBaseUrl: Uri.parse('https://api.example.test'), useMocks: true),
      info: const AppInfo(version: '1.0.0', buildNumber: '1'),
      api: MockPitchyApi(
        scenario: online ? seededAs : MockScenario.offline,
        clock: () => _now,
        latency: Duration.zero,
        savedCopies: store,
      ),
      preferences: prefs,
      savedCopies: store,
      initialLocation: location,
      clock: () => _now,
    ),
  );
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(Scaffold).first);
    await precacheImage(const AssetImage('assets/images/pitchy_logo_placeholder.png'), ctx);
  });
  await _settle(tester);
  await expectLater(find.byType(PitchyApp), matchesGoldenFile('../.impeccable/review/$name.png'));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  setUpAll(_loadFonts);
  const phone = Size(390, 844);
  const tallPhone = Size(390, 1500);
  const narrow = Size(360, 1500);
  const desktop = Size(1280, 900);

  testWidgets(
    'f5 phone board offline',
    (t) => _shot(t, 'f5-phone-board-offline', size: tallPhone),
  );
  testWidgets(
    'f5 phone board offline, all current when saved',
    (t) => _shot(
      t,
      'f5-phone-board-offline-was-current',
      size: tallPhone,
      seededAs: MockScenario.allCurrent,
    ),
  );
  testWidgets(
    'f5 phone board offline dark',
    (t) => _shot(t, 'f5-phone-board-offline-dark', size: tallPhone, mode: PitchyThemeMode.dark),
  );
  testWidgets(
    'f5 narrow board offline large text',
    (t) => _shot(t, 'f5-narrow-board-offline-large-text', size: narrow, textScale: 2),
  );
  testWidgets(
    'f5 narrow board live large text (comparison)',
    (t) => _shot(t, 'f5-narrow-board-live-large-text', size: narrow, textScale: 2, online: true),
  );
  testWidgets(
    'f5 desktop board offline',
    (t) => _shot(t, 'f5-desktop-board-offline', size: desktop),
  );
  testWidgets(
    'f5 phone safety offline',
    (t) => _shot(t, 'f5-phone-safety-offline', size: tallPhone, location: Routes.safety),
  );
  testWidgets(
    'f5 phone first screen offline',
    (t) => _shot(t, 'f5-phone-first-screen-offline', size: phone),
  );
}
