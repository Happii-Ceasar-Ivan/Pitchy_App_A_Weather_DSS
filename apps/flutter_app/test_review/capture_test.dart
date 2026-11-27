// Review captures (not part of the normal test run). Renders the shell and the
// component gallery with the real bundled fonts and writes PNGs for design
// review:  flutter test test_review --update-goldens
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

Future<void> _shot(
  WidgetTester tester,
  String name, {
  required Size size,
  String location = Routes.dashboard,
  PitchyThemeMode mode = PitchyThemeMode.light,
  bool withMatch = false,
  MockScenario scenario = MockScenario.someStale,
  Duration latency = Duration.zero,
  bool settle = true,
  Future<void> Function(WidgetTester)? act,
  double textScale = 1,
  Map<String, String> prefs = const {},
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PitchyApp(
      config: AppConfig(apiBaseUrl: Uri.parse('https://api.example.test'), useMocks: true),
      info: const AppInfo(version: '1.0.0', buildNumber: '1'),
      api: MockPitchyApi(scenario: scenario, latency: latency),
      preferences: MemoryPreferences({
        PrefKeys.themeMode: mode.name,
        if (withMatch) PrefKeys.activeMatchId: rizalMemorialId,
        ...prefs,
      }),
      initialLocation: location,
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
  // Drain the slow mock's pending requests before the test ends.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 10));
}

/// Spinners never settle, so advance a fixed number of frames instead.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(_loadFonts);
  const phone = Size(390, 844);
  const desktop = Size(1280, 800);

  // P-28 redesign: Switzer + Plex Mono, Midnight Navy and Glacier. Every
  // theme, phone / landscape / tablet / desktop, 1.0x and 2.0x text.
  const small = Size(360, 780);
  const custom = {PrefKeys.customShell: 'Violet', PrefKeys.customAccent: 'Teal'};
  for (final (name, size, mode, scale, location, prefs) in [
    (
      'p28-phone-board',
      small,
      PitchyThemeMode.light,
      1.0,
      Routes.dashboard,
      const <String, String>{},
    ),
    (
      'p28-phone-board-2x',
      small,
      PitchyThemeMode.light,
      2.0,
      Routes.dashboard,
      const <String, String>{},
    ),
    (
      'p28-phone-board-dark',
      small,
      PitchyThemeMode.dark,
      1.0,
      Routes.dashboard,
      const <String, String>{},
    ),
    (
      'p28-phone-board-green',
      small,
      PitchyThemeMode.pitchGreen,
      1.0,
      Routes.dashboard,
      const <String, String>{},
    ),
    ('p28-phone-board-custom', small, PitchyThemeMode.custom, 1.0, Routes.dashboard, custom),
    (
      'p28-landscape-board',
      const Size(780, 360),
      PitchyThemeMode.light,
      1.0,
      Routes.dashboard,
      const <String, String>{},
    ),
    (
      'p28-tablet-board',
      const Size(768, 1024),
      PitchyThemeMode.light,
      1.0,
      Routes.dashboard,
      const <String, String>{},
    ),
    (
      'p28-desktop-board',
      desktop,
      PitchyThemeMode.light,
      1.0,
      Routes.dashboard,
      const <String, String>{},
    ),
    (
      'p28-desktop-board-dark',
      desktop,
      PitchyThemeMode.dark,
      1.0,
      Routes.dashboard,
      const <String, String>{},
    ),
    (
      'p28-desktop-board-2x',
      desktop,
      PitchyThemeMode.light,
      2.0,
      Routes.dashboard,
      const <String, String>{},
    ),
    (
      'p28-phone-safety',
      small,
      PitchyThemeMode.light,
      1.0,
      Routes.safety,
      const <String, String>{},
    ),
    (
      'p28-phone-safety-dark',
      small,
      PitchyThemeMode.dark,
      1.0,
      Routes.safety,
      const <String, String>{},
    ),
    ('p28-phone-safety-custom', small, PitchyThemeMode.custom, 1.0, Routes.safety, custom),
    ('p28-phone-chat', small, PitchyThemeMode.light, 1.0, Routes.chat, const <String, String>{}),
    (
      'p28-phone-chat-dark',
      small,
      PitchyThemeMode.dark,
      1.0,
      Routes.chat,
      const <String, String>{},
    ),
    (
      'p28-phone-settings',
      small,
      PitchyThemeMode.light,
      1.0,
      Routes.settings,
      const <String, String>{},
    ),
    (
      'p28-phone-credits',
      small,
      PitchyThemeMode.light,
      1.0,
      Routes.credits,
      const <String, String>{},
    ),
    (
      'p28-phone-match-setup',
      small,
      PitchyThemeMode.light,
      1.0,
      Routes.matchSetup,
      const <String, String>{},
    ),
    (
      'p28-phone-gallery',
      small,
      PitchyThemeMode.light,
      1.0,
      Routes.stateGallery,
      const <String, String>{},
    ),
    (
      'p28-phone-gallery-dark',
      small,
      PitchyThemeMode.dark,
      1.0,
      Routes.stateGallery,
      const <String, String>{},
    ),
  ]) {
    testWidgets(
      name,
      (t) => _shot(
        t,
        name,
        size: size,
        mode: mode,
        textScale: scale,
        location: location,
        prefs: prefs,
        withMatch: true,
      ),
    );
  }
  for (final mode in [PitchyThemeMode.light, PitchyThemeMode.dark]) {
    testWidgets(
      'p28 drawer ${mode.name}',
      (t) => _shot(
        t,
        'p28-phone-drawer-${mode.name}',
        size: small,
        mode: mode,
        withMatch: true,
        act: (t) => t.tap(find.byTooltip('Quick settings')),
      ),
    );
  }

  // F2: update flow and official alerts.
  testWidgets(
    'f2 phone update offered',
    (t) => _shot(t, 'f2-phone-update', size: phone, withMatch: true),
  );
  testWidgets(
    'f2 phone updating',
    (t) => _shot(
      t,
      'f2-phone-updating',
      size: phone,
      withMatch: true,
      act: (t) => t.tap(find.text('Update')),
    ),
  );
  testWidgets(
    'f2 phone must wait',
    (t) => _shot(
      t,
      'f2-phone-wait',
      size: phone,
      withMatch: true,
      scenario: MockScenario.unavailable,
      act: (t) => t.tap(find.text('Update')),
    ),
  );
  testWidgets(
    'f2 phone job failed',
    (t) => _shot(
      t,
      'f2-phone-failed',
      size: phone,
      withMatch: true,
      scenario: MockScenario.ingestFails,
      act: (t) async {
        await t.tap(find.text('Update'));
        for (var i = 0; i < 12; i++) {
          await t.pump(const Duration(seconds: 1));
        }
      },
    ),
  );
  testWidgets(
    'f2 phone updated',
    (t) => _shot(
      t,
      'f2-phone-updated',
      size: phone,
      withMatch: true,
      act: (t) async {
        await t.tap(find.text('Update'));
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(seconds: 1));
        }
      },
    ),
  );
  testWidgets(
    'f2 phone alert open',
    (t) => _shot(
      t,
      'f2-phone-alert-open',
      size: phone,
      withMatch: true,
      act: (t) => t.tap(find.text('SYNTHETIC: Thunderstorm advisory for Metro Manila')),
    ),
  );
  testWidgets(
    'f2 phone skeleton',
    (t) => _shot(
      t,
      'f2-phone-skeleton',
      size: phone,
      withMatch: true,
      latency: const Duration(seconds: 2),
      settle: false,
      act: (t) => t.pump(const Duration(milliseconds: 2100)),
    ),
  );
  testWidgets(
    'f2 desktop dark update',
    (t) => _shot(
      t,
      'f2-desktop-dark',
      size: desktop,
      withMatch: true,
      mode: PitchyThemeMode.dark,
      act: (t) => t.tap(find.text('Update')),
    ),
  );
  testWidgets('phone dashboard empty', (t) => _shot(t, 'phone', size: phone));
  testWidgets(
    'phone dashboard board',
    (t) => _shot(t, 'f1-phone-board', size: phone, withMatch: true),
  );
  testWidgets(
    'phone dashboard skeleton',
    (t) => _shot(
      t,
      'f1-phone-skeleton',
      size: phone,
      withMatch: true,
      // Match restore takes one delay; the weather request a second one. Capture between.
      latency: const Duration(seconds: 2),
      settle: false,
      act: (t) => t.pump(const Duration(milliseconds: 2100)),
    ),
  );
  testWidgets(
    'phone quick settings',
    (t) => _shot(
      t,
      'f1-phone-drawer',
      size: phone,
      withMatch: true,
      act: (t) => t.tap(find.byTooltip('Quick settings')),
    ),
  );
  testWidgets(
    'phone match setup',
    (t) => _shot(
      t,
      'f1-phone-setup',
      size: phone,
      act: (t) async {
        await t.tap(find.text('Set up a match'));
        await _settle(t);
        await t.tap(find.text('Rizal Memorial Stadium'));
      },
    ),
  );
  testWidgets(
    'phone match setup errors',
    (t) => _shot(
      t,
      'f1-phone-setup-errors',
      size: phone,
      act: (t) async {
        await t.tap(find.text('Set up a match'));
        await _settle(t);
        await t.tap(find.text('Show conditions'));
      },
    ),
  );
  testWidgets(
    'phone full settings',
    (t) => _shot(
      t,
      'f1-phone-settings',
      size: phone,
      withMatch: true,
      act: (t) async {
        await t.tap(find.byTooltip('Quick settings'));
        await _settle(t);
        await t.tap(find.text('Open full settings'));
      },
    ),
  );
  testWidgets(
    'phone about',
    (t) => _shot(
      t,
      'f1-phone-about',
      size: phone,
      withMatch: true,
      act: (t) async {
        await t.tap(find.byTooltip('Quick settings'));
        await _settle(t);
        await t.tap(find.text('About Pitchy'));
      },
    ),
  );
  testWidgets(
    'desktop dashboard board',
    (t) => _shot(t, 'f1-desktop-board', size: desktop, withMatch: true),
  );
  testWidgets(
    'desktop dashboard dark',
    (t) => _shot(t, 'f1-desktop-dark', size: desktop, withMatch: true, mode: PitchyThemeMode.dark),
  );
  testWidgets(
    'phone gallery',
    (t) => _shot(t, 'phone-gallery', size: phone, location: Routes.stateGallery),
  );
  testWidgets(
    'phone gallery board',
    (t) => _shot(
      t,
      'phone-gallery-board',
      size: phone,
      location: Routes.stateGallery,
      act: (t) async {
        await t.drag(find.byType(ListView), const Offset(0, -330));
        await _settle(t);
        await t.tap(find.text('Heat index'));
      },
    ),
  );
  testWidgets(
    'phone gallery dark',
    (t) => _shot(
      t,
      'phone-gallery-dark',
      size: phone,
      location: Routes.stateGallery,
      mode: PitchyThemeMode.dark,
      act: (t) => t.drag(find.byType(ListView), const Offset(0, -330)),
    ),
  );
  testWidgets(
    'phone settings custom',
    (t) => _shot(
      t,
      'phone-settings-custom',
      size: phone,
      location: Routes.settings,
      mode: PitchyThemeMode.custom,
    ),
  );
  testWidgets(
    'phone chat pitch green',
    (t) => _shot(
      t,
      'phone-chat-green',
      size: phone,
      location: Routes.chat,
      mode: PitchyThemeMode.pitchGreen,
    ),
  );
  testWidgets(
    'desktop gallery',
    (t) => _shot(
      t,
      'desktop-gallery',
      size: desktop,
      location: Routes.stateGallery,
      act: (t) => t.drag(find.byType(ListView), const Offset(0, -330)),
    ),
  );
}
