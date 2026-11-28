// Privacy policy and Safety disclaimer (approved by the user 2026-11-26, P-25):
// static app text opened from Settings. Facts checked against the backend
// (hashed IP and session token only; question and answer text never stored).

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/features/settings/policy_pages.dart';

import '../app_harness.dart';
import '../helpers.dart';

String _allText(WidgetTester tester) => [
  for (final e in find.byType(Text).evaluate()) (e.widget as Text).data ?? '',
].join('\n');

void main() {
  setUpAll(loadAppFonts);

  for (final (row, title) in [
    ('Privacy policy', 'Privacy policy'),
    ('Safety disclaimer', 'Safety disclaimer'),
  ]) {
    testWidgets('Settings > $row opens its page', (tester) async {
      await pumpPitchyApp(tester, location: Routes.settings, size: const Size(390, 2400));
      final tile = tester.widget<ListTile>(
        find.ancestor(of: find.text(row), matching: find.byType(ListTile)),
      );
      expect(tile.enabled, isTrue);
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(AppBar), matching: find.text(title)), findsOneWidget);
    });
  }

  testWidgets('privacy policy states the checked facts', (tester) async {
    await pumpPitchyApp(tester, location: Routes.privacy, size: const Size(390, 6000));
    final text = _allText(tester);
    for (final fact in [
      'Pitchy has no sign-up or login.',
      'The text of your question and of the answer is never stored',
      'never the address itself',
      'Don’t type names or other personal details into Ask Pitchy.',
      'Google Gemini, Groq or OpenRouter',
      'Open-Meteo, OpenWeather, PAGASA and Vaisala Xweather',
      'Supabase (Tokyo)',
      'Last updated: 28 November 2026',
    ]) {
      expect(text, contains(fact), reason: fact);
    }
    expect(text, isNot(contains('[confirm]')));
  });

  testWidgets('safety disclaimer keeps the safety rules', (tester) async {
    await pumpPitchyApp(tester, location: Routes.disclaimer, size: const Size(390, 6000));
    final text = _allText(tester);
    for (final fact in [
      'It does not make those decisions.',
      'Officials decide.',
      'No level is not “safe”.',
      'If you see lightning or hear thunder, follow your lightning procedure straight away',
      'Ask Pitchy can be wrong.',
      'call local emergency services',
    ]) {
      expect(text, contains(fact), reason: fact);
    }
  });

  for (final route in [Routes.privacy, Routes.disclaimer]) {
    testWidgets('$route at 360 px and 200% text: nothing overflows', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpPitchyApp(tester, location: route, size: const Size(360, 780));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('S11: on a wide window lines stop at about 70 characters (${scale}x)', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpPitchyApp(tester, location: Routes.privacy, size: const Size(2400, 900));
      final intro = find.text(PolicyPages.privacy.intro);
      final width = tester.getSize(intro).width;
      final measure = PolicyScreen.measure(tester.element(intro));
      expect(width, lessThanOrEqualTo(measure + 0.5));
      // 70 characters of body text: roughly 30-38 em at 16 px.
      expect(measure / (16 * scale), inInclusiveRange(28, 40));
      // Centred, so the column doesn't hug the left edge.
      final rect = tester.getRect(intro);
      expect(rect.left, greaterThan(200));
    });
  }

  test('every section has a heading and some text', () {
    for (final page in [PolicyPages.privacy, PolicyPages.disclaimer]) {
      for (final s in page.sections) {
        expect(s.heading, isNotEmpty);
        expect(s.paragraphs.length + s.bullets.length, greaterThan(0), reason: s.heading);
      }
    }
  });

  testWidgets('privacy policy names Maya for donations, not Ko-fi', (tester) async {
    await pumpPitchyApp(tester, location: Routes.privacy, size: const Size(390, 6000));
    final text = _allText(tester);
    expect(text, contains('Support development shows a Maya QR code.'));
    expect(text, contains('Pitchy never sees your payment details'));
    expect(text, isNot(contains('Ko-fi')));
  });

  testWidgets('Support development opens the Maya QR screen', (tester) async {
    await pumpPitchyApp(tester, location: Routes.settings, size: const Size(390, 2400));
    final tile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Support development'), matching: find.byType(ListTile)),
    );
    expect(tile.enabled, isTrue);
    expect(find.text('Optional donations through Maya (QR Ph).'), findsOneWidget);
    await tester.tap(find.text('Support development'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Support Pitchy')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Maya QR Ph code for CEASAR IVAN CAIGA'), findsOneWidget);
    // Tests run on the desktop host: no save button there.
    expect(find.text('Save QR to Photos'), findsNothing);
  });
}
