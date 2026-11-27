// Overflow sweep after the font change (P-28, plan v1 §6 / v2 §8): every
// screen at phone, landscape phone, tablet and desktop widths, at 100% and
// 200% text, in light and dark, with the real Switzer and Plex Mono glyphs.
// Any RenderFlex overflow or other layout error fails the test.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';

import '../app_harness.dart';
import '../helpers.dart';

const _routes = [
  Routes.dashboard,
  Routes.safety,
  Routes.chat,
  Routes.matchSetup,
  Routes.settings,
  Routes.about,
  Routes.credits,
  Routes.privacy,
  Routes.disclaimer,
];

const _sizes = [
  (Size(360, 780), 'phone'),
  (Size(780, 360), 'landscape'),
  (Size(768, 1024), 'tablet'),
  (Size(1280, 800), 'desktop'),
];

void main() {
  setUpAll(loadAppFonts);

  for (final route in _routes) {
    for (final (size, name) in _sizes) {
      for (final scale in [1.0, 2.0]) {
        for (final mode in ['light', 'dark']) {
          testWidgets('$route, $name, ${scale}x, $mode: no overflow', (tester) async {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
            await pumpPitchyApp(
              tester,
              size: size,
              location: route,
              scenario: MockScenario.someStale,
              prefs: {...withActiveMatch(), PrefKeys.themeMode: mode},
            );
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
}
