// F4 P2 layout leftovers on the chat (Ask Pitchy): phone height used by the
// notice and composer, reference text size, and the measure on wide windows.
// Real Roboto glyphs, so heights and widths are the ones a device draws.

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/preferences.dart';

import '../app_harness.dart';
import '../helpers.dart';

final _notice = find.byKey(const ValueKey('chat-notice'));
final _composer = find.byKey(const ValueKey('chat-composer'));

Future<void> _openStarted(WidgetTester tester, Size size) async {
  await pumpPitchyApp(
    tester,
    size: size,
    location: Routes.chat,
    prefs: {...withActiveMatch(), PrefKeys.chatRole: 'coach'},
  );
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

  group('phone', () {
    testWidgets('notice and composer leave the conversation most of the height', (tester) async {
      await _openStarted(tester, const Size(390, 844));
      final chrome = tester.getSize(_notice).height + tester.getSize(_composer).height;
      // Was 204 px (F4 P2). The safety line and the match stay.
      expect(chrome, lessThanOrEqualTo(150));
      // Review P1-3: still says who decides, on one line.
      final safety = find.text('AI explanations, not decisions. Officials decide.');
      expect(safety, findsOneWidget);
      final line = tester.renderObject<RenderParagraph>(safety);
      // As tall as the same text laid out with no width limit: one line.
      expect(
        line.size.height,
        lessThanOrEqualTo(line.getMinIntrinsicHeight(double.infinity) + 0.5),
      );
      expect(find.textContaining('About Rizal Memorial Stadium'), findsOneWidget);
    });

    testWidgets('the role stays visible and changeable from the composer row', (tester) async {
      await _openStarted(tester, const Size(390, 844));
      // Review P1-1: a visible short role name and a caret, not an icon only.
      expect(find.text('Ask about this match'), findsOneWidget);
      final button = find.byTooltip('Asking as Coach. Change who’s asking');
      expect(find.descendant(of: button, matching: find.text('Coach')), findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.byIcon(Icons.arrow_drop_down)),
        findsOneWidget,
      );
      expect(button, findsOneWidget);
      final size = tester.getSize(button);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(
        (tester.getCenter(button).dy - tester.getCenter(find.byType(TextField)).dy).abs(),
        lessThan(24),
      );

      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Referee').last);
      await tester.pumpAndSettle();
      final referee = find.byTooltip('Asking as Referee. Change who’s asking');
      expect(find.descendant(of: referee, matching: find.text('Referee')), findsOneWidget);
    });

    testWidgets('reference and limitation lines are 14 px, not 12', (tester) async {
      await _openStarted(tester, const Size(390, 1600));
      await _ask(tester, 'Do we need cooling breaks?');
      final reference = find.textContaining('Demo heat guidance');
      final limitation = find.textContaining('keyword search');
      for (final f in [reference, limitation]) {
        expect(f, findsOneWidget);
        final style = (tester.renderObject<RenderParagraph>(f).text as TextSpan).style!;
        expect(style.fontSize, greaterThanOrEqualTo(14));
      }
    });
  });

  testWidgets('phone: the longest role keeps a short name, and the input stays wide', (
    tester,
  ) async {
    await pumpPitchyApp(
      tester,
      size: const Size(360, 780),
      location: Routes.chat,
      prefs: {...withActiveMatch(), PrefKeys.chatRole: 'match_official'},
    );
    await tester.tap(find.text('Start chatting'));
    await tester.pumpAndSettle();
    final button = find.byTooltip('Asking as Match Official/Commissioner. Change who’s asking');
    expect(find.descendant(of: button, matching: find.text('Official')), findsOneWidget);
    expect(tester.getSize(find.byType(TextField)).width, greaterThanOrEqualTo(170));
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen readers can name and open the entry screen role menu', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPitchyApp(tester, location: Routes.chat, prefs: withActiveMatch());
    // Found on a phone with uiautomator: no name and no tap action.
    final menu = find.bySemanticsLabel('What role are you?');
    expect(menu, findsOneWidget);
    final data = tester.getSemantics(menu).getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.value, 'None selected');

    tester.semantics.tap(find.semantics.byLabel('What role are you?'));
    await tester.pumpAndSettle();
    expect(find.text('Referee'), findsWidgets);
    await tester.tap(find.text('Referee').last);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(menu).getSemanticsData().value, 'Referee');
    semantics.dispose();
  });

  group('wide window', () {
    testWidgets('notice, conversation and composer share one 720 px column in the pane', (
      tester,
    ) async {
      await _openStarted(tester, const Size(1280, 800));
      await _ask(tester, 'Do we need cooling breaks?');
      final pane = tester.getRect(_composer);
      final field = tester.getRect(find.byType(TextField));
      final send = tester.getRect(find.byTooltip('Send question'));
      final noticeIcon = tester.getRect(
        find.descendant(of: _notice, matching: find.byIcon(Icons.info_outline)),
      );
      final reply = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Ask Pitchy reply',
        ),
      );
      final left = (pane.width - 720) / 2 + pane.left;
      // Column left edge: notice icon, reply card and the composer's first control.
      expect(noticeIcon.left, moreOrLessEquals(left, epsilon: 0.5));
      expect(reply.left, moreOrLessEquals(left, epsilon: 0.5));
      expect(send.right, moreOrLessEquals(left + 720, epsilon: 0.5));
      // The role row stays above the input on wide windows.
      expect(find.text('Asking as Coach'), findsOneWidget);
      expect(field.left, moreOrLessEquals(left, epsilon: 0.5));
    });
  });
}
