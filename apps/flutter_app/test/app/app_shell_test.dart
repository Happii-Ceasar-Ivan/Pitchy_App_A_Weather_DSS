import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';
import 'package:pitchy/shared/widgets/link_text.dart';
import 'package:pitchy/shared/widgets/pitchy_logo.dart';

import '../app_harness.dart';

Finder _inBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Quick settings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone: three-tab bottom bar; settings button, then logo, then screen name', (
    tester,
  ) async {
    await pumpPitchyApp(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(3));

    for (final tab in ['PitChyAT', 'Safety', 'Dashboard']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
      await tester.pumpAndSettle();
      final settingsX = tester.getCenter(_inBar(find.byTooltip('Quick settings'))).dx;
      final logoX = tester.getCenter(_inBar(find.byType(PitchyLogo))).dx;
      final titleX = tester.getCenter(_inBar(find.text(tab))).dx;
      expect(settingsX, lessThan(logoX));
      expect(logoX, lessThan(titleX));
    }
  });

  testWidgets('wide window (Windows): navigation rail instead of a bottom bar', (tester) async {
    await pumpPitchyApp(tester, size: const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('Quick settings: switch, updates with version, about, full settings', (
    tester,
  ) async {
    await pumpPitchyApp(tester);
    await _openDrawer(tester);
    expect(find.text('Dark mode'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Pitchy 1.0.0 (build 1)'), findsOneWidget);
    expect(find.text('About Pitchy'), findsOneWidget);
    expect(find.text('Open full settings'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsNothing);
  });

  testWidgets('Esc closes the drawer (Windows)', (tester) async {
    await pumpPitchyApp(tester, size: const Size(1280, 800));
    await _openDrawer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsNothing);
  });

  testWidgets('Dark switch returns to the last light-family theme, and is saved', (tester) async {
    final (_, prefs) = await pumpPitchyApp(
      tester,
      prefs: {PrefKeys.themeMode: 'pitchGreen', PrefKeys.lastLightMode: 'pitchGreen'},
    );
    await _openDrawer(tester);
    expect(find.text('Pitch Green theme'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Dark theme'), findsOneWidget);
    expect(prefs.getString(PrefKeys.themeMode), 'dark');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(prefs.getString(PrefKeys.themeMode), PitchyThemeMode.pitchGreen.name);
  });

  testWidgets('Check for updates says plainly that updates aren’t set up', (tester) async {
    await pumpPitchyApp(tester);
    await _openDrawer(tester);
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You have Pitchy 1.0.0 (build 1)'), findsOneWidget);
    expect(find.textContaining('aren’t set up yet'), findsOneWidget);
  });

  testWidgets('Full settings has every row; rows without content are disabled', (tester) async {
    await pumpPitchyApp(tester);
    await _openDrawer(tester);
    await tester.tap(find.text('Open full settings'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Settings')),
      findsOneWidget,
    );
    for (final row in [
      'Light',
      'Dark',
      'Pitch Green',
      'Custom',
      'Send feedback',
      'Contact support',
      'Support development',
      'Check for updates',
      'About Pitchy',
      'Credits',
      'Privacy policy',
      'Safety disclaimer',
    ]) {
      await tester.scrollUntilVisible(
        find.text(row),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(row), findsOneWidget, reason: row);
    }
    final privacy = tester.widget<ListTile>(
      find.ancestor(of: find.text('Privacy policy'), matching: find.byType(ListTile)),
    );
    expect(privacy.enabled, isFalse);
  });

  testWidgets('Custom theme shows the fixed colour set', (tester) async {
    await pumpPitchyApp(tester, prefs: {PrefKeys.themeMode: 'custom'});
    await _openDrawer(tester);
    await tester.tap(find.text('Open full settings'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Bar colour: ')), findsNWidgets(customSwatches.length));
    expect(find.textContaining('Warning and safety colours never change'), findsOneWidget);
  });

  testWidgets('About shows the version and links to Credits with the Open-Meteo link', (
    tester,
  ) async {
    await pumpPitchyApp(tester);
    await _openDrawer(tester);
    await tester.tap(find.text('About Pitchy'));
    await tester.pumpAndSettle();
    expect(find.text('Version 1.0.0 (build 1)'), findsOneWidget);
    await tester.tap(find.text('Credits'));
    await tester.pumpAndSettle();
    expect(find.text('Weather data by Open-Meteo.com'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is LinkText && w.url == 'https://open-meteo.com/'),
      findsOneWidget,
    );
  });

  testWidgets('a screen opened directly offers Back to dashboard', (tester) async {
    await pumpPitchyApp(tester, location: '/settings');
    await tester.tap(find.byTooltip('Back to dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('No match set up'), findsOneWidget);
  });

  testWidgets('pushed screens show Back in place of the settings button', (tester) async {
    await pumpPitchyApp(tester);
    await _openDrawer(tester);
    await tester.tap(find.text('Open full settings'));
    await tester.pumpAndSettle();
    expect(_inBar(find.byType(BackButton)), findsOneWidget);
    expect(_inBar(find.byTooltip('Quick settings')), findsNothing);
  });

  testWidgets('PitChyAT without a match offers to set one up', (tester) async {
    await pumpPitchyApp(tester);
    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('PitChyAT')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome to PitChyAT'), findsOneWidget);
    expect(find.text('Set up a match'), findsOneWidget);
  });
}
