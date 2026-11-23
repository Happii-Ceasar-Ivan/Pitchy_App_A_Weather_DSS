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
  final roboto = FontLoader('Roboto');
  for (final f in ['regular', 'medium', 'bold']) {
    roboto.addFont(rootBundle.load('assets/fonts/roboto-$f.ttf'));
  }
  await roboto.load();
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
}) async {
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
