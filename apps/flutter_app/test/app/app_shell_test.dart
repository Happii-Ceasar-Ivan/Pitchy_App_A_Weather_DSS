import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/app.dart';
import 'package:pitchy/core/config/app_config.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';
import 'package:pitchy/core/theme/theme_controller.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';
import 'package:pitchy/shared/widgets/pitchy_logo.dart';

Future<ThemeController> _pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  final theme = ThemeController();
  await tester.pumpWidget(
    PitchyApp(
      config: AppConfig(apiBaseUrl: Uri.parse('https://api.example.test'), useMocks: true),
      api: MockPitchyApi(latency: Duration.zero),
      theme: theme,
    ),
  );
  await tester.pumpAndSettle();
  return theme;
}

void main() {
  testWidgets('phone width: bottom navigation; every screen shows the logo left of its name', (
    tester,
  ) async {
    await _pumpApp(tester, const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    for (final (tab, title) in [
      ('PitChyAT', 'PitChyAT'),
      ('Settings', 'Settings'),
      ('Dashboard', 'Dashboard'),
    ]) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
      await tester.pumpAndSettle();
      final appBar = find.byType(AppBar);
      expect(find.descendant(of: appBar, matching: find.byType(PitchyLogo)), findsOneWidget);
      expect(find.descendant(of: appBar, matching: find.text(title)), findsOneWidget);
      final logoX = tester
          .getCenter(find.descendant(of: appBar, matching: find.byType(PitchyLogo)))
          .dx;
      final titleX = tester.getCenter(find.descendant(of: appBar, matching: find.text(title))).dx;
      expect(logoX, lessThan(titleX));
    }
  });

  testWidgets('wide window (Windows): navigation rail instead of a bottom bar', (tester) async {
    await _pumpApp(tester, const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('PitChyAT states that answers are not official decisions', (tester) async {
    await _pumpApp(tester, const Size(390, 844));
    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('PitChyAT')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('not official decisions'), findsOneWidget);
  });

  testWidgets('Settings switches themes; Custom shows the fixed colour set', (tester) async {
    final theme = await _pumpApp(tester, const Size(390, 844));
    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pitch Green'));
    await tester.pumpAndSettle();
    expect(theme.mode, PitchyThemeMode.pitchGreen);
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Bar colour: ')), findsNWidgets(customSwatches.length));
    expect(find.textContaining('Warning and safety colours never change'), findsOneWidget);
  });

  testWidgets('Credits carries the Open-Meteo attribution and link', (tester) async {
    await _pumpApp(tester, const Size(390, 844));
    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credits'));
    await tester.pumpAndSettle();
    expect(find.text('Weather data by Open-Meteo.com'), findsOneWidget);
    expect(find.text('https://open-meteo.com/'), findsOneWidget);
  });
}
