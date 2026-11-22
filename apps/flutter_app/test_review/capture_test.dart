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
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';
import 'package:pitchy/core/theme/theme_controller.dart';
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
  Future<void> Function(WidgetTester)? act,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  addTearDown(tester.view.reset);
  final theme = ThemeController()..setMode(mode);
  await tester.pumpWidget(
    PitchyApp(
      config: AppConfig(apiBaseUrl: Uri.parse('https://api.example.test'), useMocks: true),
      api: MockPitchyApi(latency: Duration.zero),
      theme: theme,
      initialLocation: location,
    ),
  );
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(Scaffold).first);
    await precacheImage(const AssetImage('assets/images/pitchy_logo_placeholder.png'), ctx);
  });
  await _settle(tester);
  if (act != null) {
    await act(tester);
    await _settle(tester);
  }
  await expectLater(find.byType(PitchyApp), matchesGoldenFile('../.impeccable/review/$name.png'));
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

  testWidgets('phone dashboard', (t) => _shot(t, 'phone', size: phone));
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
        await t.tap(find.text('Heat index (PAGASA)'));
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
  testWidgets('desktop dashboard', (t) => _shot(t, 'desktop', size: desktop));
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
