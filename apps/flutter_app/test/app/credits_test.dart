// Credits (P-13): every outside source the app shows or ships is listed, and
// the bundled font's licence is part of the open-source licences page.

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

  test('the bundled Roboto licence is registered for the licences page', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerAppLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final roboto = entries.where((e) => e.packages.contains('Roboto font'));
    expect(roboto, hasLength(1));
    final text = roboto.single.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('Apache License'));
  });
}
