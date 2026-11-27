// Credits (P-13): every outside source the app shows or ships is listed, and
// the bundled open-source font's licence is part of the licences page.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/app_licenses.dart';
import 'package:pitchy/features/settings/credits_screen.dart';
import 'package:pitchy/shared/widgets/link_text.dart';

void main() {
  testWidgets('lists the lightning source with the same credit and link the Safety tab shows', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CreditsScreen()));
    expect(find.text('Lightning data: Powered by Vaisala Xweather'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is LinkText && w.url == 'https://www.xweather.com/'),
      findsOneWidget,
    );
    // The Open-Meteo credit stays first (its licence requires it to be visible).
    expect(CreditsScreen.credits.first.$1, 'Weather data by Open-Meteo.com');
  });

  test('credits the Switzer and IBM Plex Mono fonts, and no longer the old font', () {
    final titles = CreditsScreen.credits.map((c) => c.$1).toList();
    expect(titles.any((t) => t.toLowerCase().contains('rob${'o'}to')), isFalse);

    final switzer = CreditsScreen.credits.singleWhere((c) => c.$1 == 'Switzer typeface');
    expect(switzer.$2, contains('Indian Type Foundry'));
    expect(switzer.$2, contains('ITF Free Font License'));
    expect(switzer.$3, 'https://www.fontshare.com/fonts/switzer');

    final plex = CreditsScreen.credits.singleWhere((c) => c.$1 == 'IBM Plex Mono');
    expect(plex.$2, contains('IBM'));
    expect(plex.$2, contains('SIL Open Font License 1.1'));
    expect(plex.$3, 'https://github.com/IBM/plex');
  });

  test(
    'the bundled IBM Plex Mono licence is registered; the old font and Switzer are not',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      registerAppLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      final plex = entries.where((e) => e.packages.contains('IBM Plex Mono font'));
      expect(plex, hasLength(1));
      final text = plex.single.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL OPEN FONT LICENSE'));
      expect(entries.any((e) => e.packages.any((p) => p.contains('Rob${'o'}to'))), isFalse);
      expect(entries.any((e) => e.packages.any((p) => p.contains('Switzer'))), isFalse);
    },
  );
}
