// Support Pitchy (user, 2026-11-26; P-26): the Maya / QR Ph code with an
// honest note, and "Save QR to Photos" on Android. The app never handles or
// verifies money.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/config/donations.dart';
import 'package:pitchy/core/theme/app_theme.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';
import 'package:pitchy/features/settings/support_screen.dart';

import '../helpers.dart';

class _FakeSaver implements QrSaver {
  _FakeSaver(this.result);

  final QrSaveResult result;
  final saved = <(int, String)>[];

  @override
  Future<QrSaveResult> save(Uint8List bytes, String fileName) async {
    saved.add((bytes.length, fileName));
    return result;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  PitchyPalette palette = PitchyPalette.light,
  Size size = const Size(390, 844),
  QrSaver? saver,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(palette),
      home: SupportScreen(qr: Donations.maya!, saver: saver),
    ),
  );
  await tester.pumpAndSettle();
}

String _allText(WidgetTester tester) => [
  for (final e in find.byType(Text).evaluate()) (e.widget as Text).data ?? '',
].join('\n');

void main() {
  setUpAll(loadAppFonts);

  test('the QR the user supplied is bundled', () async {
    final qr = Donations.maya!;
    expect(qr.accountName, 'CEASAR IVAN CAIGA');
    final bytes = await rootBundle.load(qr.imageAsset);
    expect(bytes.lengthInBytes, greaterThan(10000));
  });

  testWidgets('shows the QR, the account name and the honest note', (tester) async {
    await _pump(tester, size: const Size(390, 1600));
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Support Pitchy')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Maya QR Ph code for CEASAR IVAN CAIGA'), findsOneWidget);
    final text = _allText(tester);
    for (final fact in [
      'Pitchy is a student project. Donations help pay for hosting.',
      'optional',
      'Scan it with Maya or any bank app that reads QR Ph.',
      'check that your app shows the name CEASAR IVAN CAIGA',
      'Pitchy never sees your payment details',
      'can’t confirm, refund or record a payment',
    ]) {
      expect(text, contains(fact), reason: fact);
    }
    expect(text, isNot(contains('PayPal')));
    expect(text, isNot(contains('Ko-fi')));
    expect(find.text('Save QR to Photos'), findsNothing, reason: 'no saver on this device');
  });

  group('Save QR to Photos (Android)', () {
    testWidgets('saves the bundled image and says where it went', (tester) async {
      final saver = _FakeSaver(QrSaveResult.saved);
      await _pump(tester, size: const Size(390, 1600), saver: saver);
      expect(_allText(tester), contains('Save it, then upload it in Maya or any bank app'));
      await tester.tap(find.text('Save QR to Photos'));
      await tester.pumpAndSettle();
      expect(saver.saved.single.$2, 'pitchy-maya-qr.jpg');
      expect(saver.saved.single.$1, greaterThan(10000));
      expect(
        find.text(
          'Saved to Photos (Pictures/Pitchy). In Maya or your bank app, upload it from your photos.',
        ),
        findsOneWidget,
      );
    });

    for (final (result, message) in [
      (QrSaveResult.failed, 'Couldn’t save the QR. Take a screenshot instead.'),
      (
        QrSaveResult.unsupported,
        'This Android version can’t save it from Pitchy. Take a screenshot instead.',
      ),
    ]) {
      testWidgets('${result.name}: says so, never "saved"', (tester) async {
        await _pump(tester, size: const Size(390, 1600), saver: _FakeSaver(result));
        await tester.tap(find.text('Save QR to Photos'));
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(find.textContaining('Saved to Photos'), findsNothing);
      });
    }
  });

  for (final palette in [PitchyPalette.light, PitchyPalette.dark]) {
    testWidgets('360 px and 200% text (${palette.brightness.name}): nothing overflows', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(
        tester,
        palette: palette,
        size: const Size(360, 780),
        saver: _FakeSaver(QrSaveResult.saved),
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
