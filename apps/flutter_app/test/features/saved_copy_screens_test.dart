import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/saved_copies.dart';
import 'package:pitchy/features/safety/safety_widgets.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/widgets/request_states.dart';
import 'package:pitchy/shared/widgets/source_rail.dart';

import '../app_harness.dart';

/// DEC-13 on screen: a saved copy only while the server can't be reached,
/// always under the banner, never labelled live, with Update off.
void main() {
  Finder banner() => find.textContaining('not live');

  FilledButton updateButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.ancestor(
      of: find.text('Update'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    ),
  );

  group('dashboard', () {
    testWidgets('online: no banner, nothing says saved copy', (tester) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch());
      expect(banner(), findsNothing);
      expect(find.text('SAVED COPY'), findsNothing);
    });

    testWidgets('server unreachable: the saved board under the banner, never Current', (
      tester,
    ) async {
      final (api, _) = await pumpPitchyApp(
        tester,
        prefs: withActiveMatch(),
        scenario: MockScenario.someStale, // offers Update while online
      );
      expect(find.text('Update'), findsOneWidget);

      api.scenario = MockScenario.offline;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      expect(banner(), findsOneWidget);
      expect(find.textContaining('Saved copy from'), findsWidgets);
      expect(find.byType(SourceRail), findsOneWidget);
      expect(find.byType(ErrorState), findsNothing);
      // Nothing on the copy claims to be live.
      expect(find.text('CURRENT'), findsNothing);
      expect(find.text('UPDATING'), findsNothing);
      expect(find.text('No official alerts for this venue'), findsNothing);
      expect(find.textContaining('Alerts · saved copy from'), findsOneWidget);
      // Update is shown but off, with the reason.
      expect(updateButton(tester).onPressed, isNull);
      expect(find.byTooltip('Update is off while Pitchy can’t reach its server.'), findsOneWidget);
    });

    testWidgets('a fresh reply replaces the copy', (tester) async {
      final (api, _) = await pumpPitchyApp(tester, prefs: withActiveMatch());
      api.scenario = MockScenario.offline;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(banner(), findsOneWidget);

      api.scenario = MockScenario.allCurrent;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(banner(), findsNothing);
      expect(find.text('SAVED COPY'), findsNothing);
      expect(find.textContaining('Alerts · checked'), findsOneWidget);
    });

    testWidgets('cold start offline: the saved match and board, not an error', (tester) async {
      // First run online saves the copies on the device.
      final (_, prefs) = await pumpPitchyApp(tester, prefs: withActiveMatch());
      final stored = {
        for (final k in [SavedCopyStore.prefKey, 'match.activeId']) k: prefs.getString(k)!,
      };

      await tester.pumpWidget(const SizedBox());
      await pumpPitchyApp(tester, prefs: stored, scenario: MockScenario.offline);

      expect(find.text('Rizal Memorial Stadium, Manila'), findsOneWidget);
      expect(banner(), findsOneWidget);
      expect(find.byType(SourceRail), findsOneWidget);
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets('cold start offline with no copy: the error, as before', (tester) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch(), scenario: MockScenario.offline);
      expect(banner(), findsNothing);
      expect(find.byType(ErrorState), findsOneWidget);
    });

    testWidgets('copies older than 14 days are not shown', (tester) async {
      final (_, prefs) = await pumpPitchyApp(tester, prefs: withActiveMatch());
      final raw = prefs.getString(SavedCopyStore.prefKey)!;
      // Rewrite every saved_at to 15 days before the test clock.
      final old = raw.replaceAllMapped(
        RegExp(r'"saved_at":"[^"]+"'),
        (_) => '"saved_at":"2026-11-08T04:00:00.000Z"',
      );

      await tester.pumpWidget(const SizedBox());
      final (_, after) = await pumpPitchyApp(
        tester,
        prefs: {SavedCopyStore.prefKey: old, 'match.activeId': rizalMemorialId},
        scenario: MockScenario.offline,
      );
      expect(banner(), findsNothing);
      expect(find.byType(ErrorState), findsOneWidget);
      // Purged from the device at start.
      expect(after.getString(SavedCopyStore.prefKey), isNull);
    });
  });

  group('safety', () {
    testWidgets('server unreachable: the saved assessment, not current, under the banner', (
      tester,
    ) async {
      // A first run online on Safety saves the match and the assessment.
      final (_, prefs) = await pumpPitchyApp(
        tester,
        prefs: withActiveMatch(),
        location: Routes.safety,
      );
      expect(banner(), findsNothing);
      final stored = {
        for (final k in [SavedCopyStore.prefKey, 'match.activeId']) k: prefs.getString(k)!,
      };

      await tester.pumpWidget(const SizedBox());
      await pumpPitchyApp(
        tester,
        prefs: stored,
        location: Routes.safety,
        scenario: MockScenario.offline,
      );
      expect(banner(), findsOneWidget);
      expect(find.byType(NotCurrentLine), findsOneWidget);
      expect(find.byType(AssessmentFailureBanner), findsNothing);
    });
  });
}
