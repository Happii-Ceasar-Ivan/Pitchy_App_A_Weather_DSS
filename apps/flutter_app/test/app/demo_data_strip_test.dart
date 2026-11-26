// A build that runs on mock data must say so on every screen: invented weather
// must never look real (project rule: never invent measurements). Release
// builds use PITCHY_USE_MOCKS=false, and then the strip never shows.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/app.dart';
import 'package:pitchy/core/config/app_config.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';

import '../app_harness.dart';
import '../helpers.dart';

const _strip = 'Demo data: not real weather';

void main() {
  for (final location in [Routes.dashboard, Routes.safety, Routes.chat, Routes.settings]) {
    testWidgets('mock build: the strip is on $location', (tester) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch(), location: location);
      expect(find.text(_strip), findsOneWidget);
      // It sits above the screen's own top bar.
      expect(
        tester.getRect(find.text(_strip)).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(AppBar).first).top),
      );
    });
  }

  testWidgets('screen readers hear it once, as a plain statement', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPitchyApp(tester);
    expect(find.bySemanticsLabel('Demo data. This is not real weather.'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('live build: no strip', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PitchyApp(
        config: AppConfig(apiBaseUrl: Uri.parse('https://api.example.test'), useMocks: false),
        info: testInfo,
        api: MockPitchyApi(clock: () => testNow, latency: Duration.zero),
        preferences: MemoryPreferences(withActiveMatch()),
        clock: () => testNow,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_strip), findsNothing);
  });
}
