// S5 (copy a reply) on Ask Pitchy, and S8: one set of suggested questions.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/preferences.dart';

import '../app_harness.dart';
import '../helpers.dart';

Future<void> _openStarted(WidgetTester tester, {Size size = const Size(390, 844)}) async {
  await pumpPitchyApp(
    tester,
    size: size,
    location: Routes.chat,
    prefs: {...withActiveMatch(), PrefKeys.chatRole: 'coach'},
  );
  await tester.ensureVisible(find.text('Start chatting'));
  await tester.tap(find.text('Start chatting'));
  await tester.pumpAndSettle();
}

Future<void> _ask(WidgetTester tester, String q) async {
  await tester.enterText(find.byType(TextField), q);
  await tester.pump();
  await tester.tap(find.byTooltip('Send question'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  // S8: Ask Pitchy already offers "Try asking" questions on the empty chat
  // (existing feature), so no second set of chips was added; the existing
  // list must stay the only one.
  testWidgets('S8: one set of suggested questions, the existing "Try asking"', (tester) async {
    await _openStarted(tester);
    expect(find.text('Try asking'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
  });

  group('S5 copy reply', () {
    testWidgets('copy only on assistant replies; tap copies and confirms', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _openStarted(tester);
      await _ask(tester, 'Typed question');
      // One reply, one copy button; none for the user's message.
      expect(find.byTooltip('Copy reply'), findsOneWidget);
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('Copy reply'));
      await tester.tap(find.byTooltip('Copy reply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(copied, startsWith('Demo reply'));
      expect(copied, contains('Based on'));
      expect(find.text('Reply copied'), findsOneWidget);
      expect(tester.getSize(find.byTooltip('Copy reply')).height, greaterThanOrEqualTo(48));
    });
  });
}
