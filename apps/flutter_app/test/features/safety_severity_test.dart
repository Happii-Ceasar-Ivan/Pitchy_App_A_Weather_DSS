import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/features/safety/safety_level.dart';

import '../helpers.dart';

void main() {
  group('P-19 option A: colour from the backend severity', () {
    test('severity wins over the level-id table', () {
      expect(
        safetyToneFor(severity: 'advisory', levelId: 'below_cooling_break_level'),
        SafetyTone.advisory,
      );
      expect(safetyToneFor(severity: 'warning', levelId: 'anything_new'), SafetyTone.warning);
      expect(safetyToneFor(severity: 'danger', levelId: null), SafetyTone.danger);
      // Backend says advisory for a level the old table called warning: the
      // backend decides.
      expect(
        safetyToneFor(severity: 'advisory', levelId: 'cooling_breaks_required'),
        SafetyTone.advisory,
      );
    });

    test('no or unknown severity falls back to the P-19 table', () {
      expect(safetyToneFor(levelId: 'cooling_breaks_required'), SafetyTone.warning);
      expect(
        safetyToneFor(severity: 'extreme', levelId: 'within_30_second_distance'),
        SafetyTone.danger,
      );
      expect(safetyToneFor(levelId: 'below_cooling_break_level'), isNull);
      expect(safetyToneFor(), isNull);
    });

    testWidgets('advisory is a calm info pill, not amber', (tester) async {
      await pumpThemed(
        tester,
        const SafetyLevelPill(
          levelId: 'below_cooling_break_level',
          severity: 'advisory',
          label: 'Below the cooling-break level',
        ),
      );
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });
  });
}
