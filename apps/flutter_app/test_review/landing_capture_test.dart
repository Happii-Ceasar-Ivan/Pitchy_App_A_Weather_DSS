// Landing-page screenshot candidates (not part of the normal run):
//   flutter test test_review/landing_capture_test.dart --update-goldens
// Output: .impeccable/review/landing/*.png (git-ignored). The landing page
// labels every shot "App screen with sample data": these use the mock
// backend's synthetic data, rendered like a release build (no demo strip).

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
import 'package:pitchy/features/dashboard/trend/trend_card.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';
import 'package:pitchy/shared/widgets/weather_value_card.dart';

/// 12:00 PM PHT on match day; kickoff is 3:00 PM PHT.
final _now = DateTime.utc(2026, 11, 28, 4);
const _phone = Size(390, 880);
const _desktop = Size(1280, 926);

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

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder _menu(String label) => find.byWidgetPredicate(
  (w) => w is DropdownMenu && w.label is Text && (w.label! as Text).data == label,
);

Future<void> _shot(
  WidgetTester tester,
  String name, {
  Size size = _phone,
  String location = Routes.dashboard,
  PitchyThemeMode mode = PitchyThemeMode.light,
  Future<void> Function(WidgetTester, MockPitchyApi)? act,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  addTearDown(tester.view.reset);
  final prefs = MemoryPreferences({
    PrefKeys.themeMode: mode.name,
    PrefKeys.activeMatchId: rizalMemorialId,
  });
  final saved = SavedCopyStore(prefs, clock: () => _now);
  final api = MockPitchyApi(latency: Duration.zero, clock: () => _now, savedCopies: saved);
  await tester.pumpWidget(
    PitchyApp(
      // Release-like: no "Demo data" strip; the landing page labels the data.
      config: AppConfig(apiBaseUrl: Uri.parse('https://api.example.test'), useMocks: false),
      info: const AppInfo(version: '1.1.0', buildNumber: '1'),
      api: api,
      preferences: prefs,
      savedCopies: saved,
      initialLocation: location,
      clock: () => _now,
    ),
  );
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(Scaffold).first);
    await precacheImage(const AssetImage('assets/images/pitchy_logo_placeholder.png'), ctx);
  });
  await _settle(tester);
  if (act != null) {
    await act(tester, api);
    await _settle(tester);
  }
  await expectLater(
    find.byType(PitchyApp),
    matchesGoldenFile('../.impeccable/review/landing/$name.png'),
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

Future<void> _scrollTo(WidgetTester t, Finder target, {double alignment = 0}) async {
  await t.scrollUntilVisible(target, 300, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
  await t.ensureVisible(target);
  await Scrollable.ensureVisible(t.element(target), alignment: alignment);
  await _settle(t);
}

void main() {
  setUpAll(_loadFonts);

  // Story step 1: the board as it opens.
  testWidgets('phone board top', (t) => _shot(t, 'phone-a2-board'));

  // New candidate: the hourly trend card on its own.
  testWidgets(
    'phone trend',
    (t) => _shot(
      t,
      'phone-a2b-trend',
      act: (t, _) => _scrollTo(t, find.byType(TrendCard)),
    ),
  );

  testWidgets(
    'phone trend before kickoff',
    (t) => _shot(
      t,
      'phone-a2c-trend-before-kickoff',
      act: (t, _) async {
        await _scrollTo(t, find.byType(TrendCard));
        await t.tap(_menu('Range'));
        await _settle(t);
        await t.tap(find.text('6 h before kickoff').hitTestable().last);
        await _settle(t);
      },
    ),
  );

  // New candidate: the tiles with their icons.
  testWidgets(
    'phone tiles',
    (t) => _shot(
      t,
      'phone-a2d-tiles',
      act: (t, _) => _scrollTo(t, find.byType(WeatherCardGrid)),
    ),
  );

  // Story step 2 and 3 (unchanged screens, re-taken on the current build).
  testWidgets('phone safety', (t) => _shot(t, 'phone-a3-safety', location: Routes.safety));
  testWidgets('phone chat entry', (t) => _shot(t, 'phone-a4-chat-entry', location: Routes.chat));

  // Trust section: the labelled saved copy when the server can't be reached.
  testWidgets(
    'phone saved copy',
    (t) => _shot(
      t,
      'phone-b1-board-saved-copy',
      act: (t, api) async {
        api.scenario = MockScenario.offline;
        await t.tap(find.byTooltip('Refresh'));
        await _settle(t);
      },
    ),
  );

  // Windows section.
  testWidgets('desktop board', (t) => _shot(t, 'desktop-board', size: _desktop));
  testWidgets(
    'desktop board dark',
    (t) => _shot(
      t,
      'desktop-board-dark',
      size: _desktop,
      mode: PitchyThemeMode.dark,
    ),
  );
}
