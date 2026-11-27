// Ask Pitchy on the smallest phone (360x640) at 2.0x text: notice and composer
// plus the conversation must not overflow.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/preferences.dart';

import '../app_harness.dart';
import '../helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final withMessage in [false, true]) {
    testWidgets(
      'chat fits 360x640 at 2.0x text (${withMessage ? 'with a reply' : 'empty'})',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpPitchyApp(
          tester,
          size: const Size(360, 640),
          location: Routes.chat,
          prefs: {...withActiveMatch(), PrefKeys.chatRole: 'coach'},
        );
        await tester.ensureVisible(find.text('Start chatting'));
        await tester.tap(find.text('Start chatting'));
        await tester.pumpAndSettle();
        if (withMessage) {
          await tester.enterText(find.byType(TextField), 'Is it safe to play?');
          await tester.pump();
          await tester.tap(find.byTooltip('Send question'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Send question'), findsOneWidget);
      },
    );
  }
}
