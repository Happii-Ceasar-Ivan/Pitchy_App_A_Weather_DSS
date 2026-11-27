// Hazard severity is drawn one way everywhere (plan v2 §6.2, Q6, P-13):
// - hazard elements never take a themed colour (no palette.accent), so Light,
//   Dark, Pitch Green and Custom all draw a level identically;
// - one icon per level: advisory info, warning amber triangle, danger filled;
// - hazard elements never animate in.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';
import 'package:pitchy/features/safety/safety_level.dart';
import 'package:pitchy/shared/widgets/alert_level.dart';

import '../helpers.dart';

const _hazardFiles = [
  'lib/features/safety/safety_level.dart',
  'lib/shared/widgets/alert_level.dart',
];

final _customs = [
  for (final shell in customSwatches)
    for (final accent in customSwatches)
      if (shell != accent) PitchyPalette.custom(shell: shell.color, accent: accent.color),
];

BoxDecoration _decorationOf(WidgetTester tester, Finder of) {
  final box = tester.widget<Container>(
    find.descendant(of: of, matching: find.byType(Container)).first,
  );
  return box.decoration! as BoxDecoration;
}

void main() {
  test('hazard element code never reads the themed accent', () {
    for (final path in _hazardFiles) {
      final code = File(path).readAsStringSync();
      expect(code, isNot(contains('.accent')), reason: path);
    }
  });

  for (final severity in ['advisory', 'warning', 'danger']) {
    testWidgets('$severity safety pill looks the same in every light theme', (tester) async {
      Future<(Color?, BoxBorder?, IconData?)> look(PitchyPalette p) async {
        await pumpThemed(
          tester,
          SafetyLevelPill(levelId: 'x', severity: severity, label: 'Level'),
          palette: p,
        );
        final pill = find.byType(SafetyLevelPill);
        final d = _decorationOf(tester, pill);
        final icon = tester.widget<Icon>(find.descendant(of: pill, matching: find.byType(Icon)));
        return (d.color, d.border, icon.icon);
      }

      final reference = await look(PitchyPalette.light);
      for (final p in [PitchyPalette.pitchGreen, ..._customs.take(12)]) {
        expect(await look(p), reference);
      }
    });
  }

  testWidgets('one icon per level on safety pills and alert marks', (tester) async {
    const expected = {
      'advisory': Icons.info_outline,
      'warning': Icons.warning_amber_rounded,
      'danger': Icons.warning,
    };
    for (final e in expected.entries) {
      await pumpThemed(tester, SafetyLevelPill(levelId: 'x', severity: e.key, label: 'L'));
      expect(find.byIcon(e.value), findsOneWidget, reason: 'safety ${e.key}');
    }
    for (final (level, icon) in [
      (AlertLevel.advisory, Icons.info_outline),
      (AlertLevel.warning, Icons.warning_amber_rounded),
      (AlertLevel.danger, Icons.warning),
    ]) {
      await pumpThemed(tester, AlertLevelMark(level: level));
      expect(find.byIcon(icon), findsOneWidget, reason: 'alert $level');
    }
  });

  testWidgets('hazard elements render complete on the first frame', (tester) async {
    await pumpThemed(
      tester,
      const Column(
        children: [
          SafetyLevelPill(levelId: 'x', severity: 'danger', label: 'Danger level'),
          AlertLevelMark(level: AlertLevel.danger),
        ],
      ),
    );
    // No running ticker after the first frame: no fade, slide or pulse.
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    for (final hazard in [find.byType(SafetyLevelPill), find.byType(AlertLevelMark)]) {
      for (final moving in [FadeTransition, AnimatedOpacity, SlideTransition, AnimatedSwitcher]) {
        expect(find.descendant(of: hazard, matching: find.byType(moving)), findsNothing);
      }
    }
  });
}
