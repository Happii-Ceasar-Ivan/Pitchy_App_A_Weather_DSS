// S7 wiring: a range longer than the loaded window asks the backend once for
// that many hours (never more than 24); covered ranges send nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../app_harness.dart';
import '../helpers.dart';

Finder _menu(String label) => find.byWidgetPredicate(
  (w) => w is DropdownMenu && w.label is Text && (w.label! as Text).data == label,
);

Future<void> _pickRange(WidgetTester tester, String range) async {
  await tester.ensureVisible(_menu('Range'));
  await tester.tap(_menu('Range'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(range).hitTestable().last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Kickoff to +24 h fetches 24 hours once', (tester) async {
    final (api, _) = await pumpPitchyApp(tester, prefs: withActiveMatch());
    final before = api.weatherQueries.length;
    await _pickRange(tester, 'Kickoff to +24 h');
    expect(api.weatherQueries.skip(before), [(hours: 24, hoursBefore: 6)]);
    // Back to a covered range and to +24 h again: nothing more is asked.
    await _pickRange(tester, 'Kickoff to +6 h');
    await _pickRange(tester, 'Kickoff to +24 h');
    expect(api.weatherQueries.length, before + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kickoff to +12 h then +24 h asks 12 then 24', (tester) async {
    final (api, _) = await pumpPitchyApp(tester, prefs: withActiveMatch());
    final before = api.weatherQueries.length;
    await _pickRange(tester, 'Kickoff to +12 h');
    await _pickRange(tester, 'Kickoff to +24 h');
    expect(api.weatherQueries.skip(before), [
      (hours: 12, hoursBefore: 6),
      (hours: 24, hoursBefore: 6),
    ]);
  });
}
