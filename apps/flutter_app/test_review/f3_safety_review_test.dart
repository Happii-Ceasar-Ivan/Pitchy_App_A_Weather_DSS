// Review captures for the F3 Safety tab (not part of the normal test run).
//   flutter test test_review --plain-name f3 --update-goldens
// Output: .impeccable/review/ (git-ignored working material).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/app.dart';
import 'package:pitchy/core/config/app_config.dart';
import 'package:pitchy/core/config/app_info.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/preferences.dart';
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

/// The mock's clock is fixed so the live lightning scenarios fall in their window.
final _now = DateTime.utc(2026, 11, 23, 4);

Future<void> _shot(
  WidgetTester tester,
  String name, {
  required Size size,
  SafetyScenario safety = SafetyScenario.heatBelow,
  PitchyThemeMode mode = PitchyThemeMode.light,
  Duration latency = Duration.zero,
  bool settle = true,
  Future<void> Function(WidgetTester)? act,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PitchyApp(
      config: AppConfig(apiBaseUrl: Uri.parse('https://api.example.test'), useMocks: true),
      info: const AppInfo(version: '1.0.0', buildNumber: '1'),
      api: MockPitchyApi(safety: safety, clock: () => _now, latency: latency),
      preferences: MemoryPreferences({
        PrefKeys.themeMode: mode.name,
        PrefKeys.activeMatchId: rizalMemorialId,
      }),
      initialLocation: Routes.safety,
      clock: () => _now,
    ),
  );
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(Scaffold).first);
    await precacheImage(const AssetImage('assets/images/pitchy_logo_placeholder.png'), ctx);
  });
  if (settle) await _settle(tester);
  if (act != null) {
    await act(tester);
    await _settle(tester);
  }
  await expectLater(find.byType(PitchyApp), matchesGoldenFile('../.impeccable/review/$name.png'));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 10));
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openFirstExpander(WidgetTester t) async {
  await t.tap(find.text('How this was worked out').first);
}

void main() {
  setUpAll(_loadFonts);
  const phone = Size(390, 1900);
  const desktop = Size(1280, 1500);

  testWidgets(
    'f3 phone heat below',
    (t) => _shot(t, 'f3-phone-heat-below', size: phone),
  );
  testWidgets(
    'f3 phone cooling breaks expanded',
    (t) => _shot(
      t,
      'f3-phone-cooling-breaks',
      size: const Size(390, 2600),
      safety: SafetyScenario.coolingBreaks,
      act: _openFirstExpander,
    ),
  );
  testWidgets(
    'f3 phone lightning near',
    (t) => _shot(t, 'f3-phone-lightning-near', size: phone, safety: SafetyScenario.lightningNear),
  );
  testWidgets(
    'f3 phone lightning stale',
    (t) => _shot(t, 'f3-phone-lightning-stale', size: phone, safety: SafetyScenario.lightningStale),
  );
  testWidgets(
    'f3 phone heat missing',
    (t) => _shot(t, 'f3-phone-heat-missing', size: phone, safety: SafetyScenario.heatMissing),
  );
  testWidgets(
    'f3 phone youth',
    (t) => _shot(t, 'f3-phone-youth', size: phone, safety: SafetyScenario.youth),
  );
  testWidgets(
    'f3 phone rules draft',
    (t) => _shot(t, 'f3-phone-rules-draft', size: phone, safety: SafetyScenario.rulesDraft),
  );
  testWidgets(
    'f3 phone not ready',
    (t) => _shot(
      t,
      'f3-phone-not-ready',
      size: const Size(390, 1100),
      safety: SafetyScenario.notReady,
    ),
  );
  testWidgets(
    'f3 phone skeleton',
    (t) => _shot(
      t,
      'f3-phone-skeleton',
      size: phone,
      latency: const Duration(seconds: 2),
      settle: false,
      act: (t) => t.pump(const Duration(milliseconds: 2100)),
    ),
  );
  testWidgets(
    'f3 desktop dark lightning near',
    (t) => _shot(
      t,
      'f3-desktop-dark-lightning',
      size: desktop,
      safety: SafetyScenario.lightningNear,
      mode: PitchyThemeMode.dark,
      act: _openFirstExpander,
    ),
  );
}
