// P-22: "Ask Pitchy" is longer than the old name; it must fit whole in the
// bottom bar (phone) and the rail (wide), at 100% and 200% text. Real Roboto
// glyphs, so the widths are the ones a device draws.

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../app_harness.dart';
import '../helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final (size, scale) in [
    (const Size(360, 780), 1.0),
    (const Size(360, 780), 2.0),
    (const Size(1280, 800), 1.0),
    (const Size(1280, 800), 2.0),
  ]) {
    testWidgets('the Ask Pitchy label fits whole at ${size.width.toInt()} px, ${scale}x text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpPitchyApp(tester, size: size);
      final nav = size.width >= 600 ? find.byType(NavigationRail) : find.byType(NavigationBar);
      final label = find.descendant(of: nav, matching: find.text('Ask Pitchy'));
      expect(label, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(paragraph.didExceedMaxLines, isFalse);
      // Not clipped: the painted text is no wider than the box it got.
      expect(
        paragraph.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(paragraph.size.width + 0.5),
      );
      final navBox = tester.getRect(nav);
      final labelBox = tester.getRect(label);
      expect(navBox.left <= labelBox.left && labelBox.right <= navBox.right, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
