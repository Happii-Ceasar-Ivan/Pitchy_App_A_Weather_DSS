// P-27 review captures (not part of the normal test run): the hourly trend
// card and the tile icons on the dashboard, for the end-of-feature design
// review.  flutter test test_review/p27_trend_review_test.dart --update-goldens
// Output: .impeccable/review/p27/ (git-ignored working material).

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
import 'package:pitchy/features/dashboard/trend/trend_card.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';
import 'package:pitchy/shared/widgets/weather_value_card.dart';

final _now = DateTime.utc(2026, 11, 28, 4);

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

Future<void> _shot(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  PitchyThemeMode mode = PitchyThemeMode.light,
  MockScenario scenario = MockScenario.allCurrent,
  String? quantity,
  double textScale = 1,
  Duration latency = Duration.zero,
  bool settle = true,
  Finder? scrollTo,
  Future<void> Function(WidgetTester)? act,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    PitchyApp(
      config: AppConfig(apiBaseUrl: Uri.parse('https://api.example.test'), useMocks: true),
      info: const AppInfo(version: '1.0.0', buildNumber: '1'),
      api: MockPitchyApi(scenario: scenario, latency: latency, clock: () => _now),
      preferences: MemoryPreferences({
        PrefKeys.themeMode: mode.name,
        PrefKeys.activeMatchId: rizalMemorialId,
        TrendCard.quantityPref: ?quantity,
      }),
      initialLocation: Routes.dashboard,
      clock: () => _now,
    ),
  );
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(Scaffold).first);
    await precacheImage(const AssetImage('assets/images/pitchy_logo_placeholder.png'), ctx);
  });
  if (settle) await _settle(tester);
  final target = scrollTo ?? find.byType(TrendCard);
  if (settle) {
    // The board list builds off-screen children lazily: scroll until built.
    await tester.scrollUntilVisible(target.first, 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(target.first);
    await _settle(tester);
  }
  if (act != null) {
    await act(tester);
    await _settle(tester);
  }
  await expectLater(
    find.byType(PitchyApp),
    matchesGoldenFile('../.impeccable/review/p27/$name.png'),
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 10));
}

Finder _menu(String label) => find.byWidgetPredicate(
  (w) => w is DropdownMenu && w.label is Text && (w.label! as Text).data == label,
);

Future<void> _pick(WidgetTester t, String menu, String entry) async {
  await t.tap(_menu(menu));
  await _settle(t);
  await t.tap(find.text(entry).hitTestable().last);
  await _settle(t);
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('phone light: default trend', (t) => _shot(t, 'phone-light-default'));

  testWidgets(
    'phone dark: stale heat index',
    (t) => _shot(
      t,
      'phone-dark-stale-heat-index',
      mode: PitchyThemeMode.dark,
      scenario: MockScenario.someStale,
      quantity: 'heat_index',
    ),
  );

  testWidgets(
    'phone light: 6 h before kickoff (gaps, past hours)',
    (t) => _shot(
      t,
      'phone-light-6h-before',
      act: (t) => _pick(t, 'Range', '6 h before kickoff'),
    ),
  );

  testWidgets(
    'phone light: rain bars to +5 h',
    (t) => _shot(
      t,
      'phone-light-rain-plus5',
      quantity: 'rain',
      act: (t) => _pick(t, 'Range', 'Kickoff to +5 h (match and after)'),
    ),
  );

  testWidgets(
    'phone light: table open',
    (t) => _shot(
      t,
      'phone-light-table',
      act: (t) async {
        await t.ensureVisible(find.text('Show as table'));
        await t.tap(find.text('Show as table'));
        await _settle(t);
        await t.ensureVisible(find.text('Hide table'));
      },
    ),
  );

  testWidgets(
    'phone 200 % text',
    (t) => _shot(t, 'phone-200pct', textScale: 2, size: const Size(360, 2400)),
  );

  testWidgets(
    'phone: tile icons',
    (t) => _shot(t, 'phone-tiles', scrollTo: find.byType(WeatherCardGrid)),
  );

  testWidgets('wide light', (t) => _shot(t, 'wide-light', size: const Size(1400, 900)));

  testWidgets(
    'wide dark, stale',
    (t) => _shot(
      t,
      'wide-dark-stale',
      size: const Size(1400, 900),
      mode: PitchyThemeMode.dark,
      scenario: MockScenario.someStale,
      act: (t) async {
        if (find.byTooltip('Show source details').evaluate().isNotEmpty) {
          await t.tap(find.byTooltip('Show source details'));
        }
      },
    ),
  );
}
