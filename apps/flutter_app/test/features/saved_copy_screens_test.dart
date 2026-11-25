import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/saved_copies.dart';
import 'package:pitchy/features/safety/safety_widgets.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/widgets/alerts_panel.dart';
import 'package:pitchy/shared/widgets/kickoff_strip.dart';
import 'package:pitchy/shared/widgets/request_states.dart';
import 'package:pitchy/shared/widgets/source_rail.dart';
import 'package:pitchy/shared/widgets/weather_value_card.dart';

import '../app_harness.dart';
import '../helpers.dart';

/// DEC-13 on screen: a saved copy only while the server can't be reached,
/// always under the banner, never labelled live, with Update off.
void main() {
  setUpAll(loadAppFonts);

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
      // F5 P2-1: a backend Stale card inside the copy says it is saved too, so
      // it never reads like a live Stale pill. Its state is not changed.
      expect(find.text('STALE · SAVED'), findsWidgets);
      expect(find.text('STALE'), findsNothing);
      // The header is just "Alerts": the banner gives the time, the pill says saved.
      expect(find.textContaining('Alerts · checked'), findsNothing);
      expect(find.text('Alerts'), findsOneWidget);
      // Update is shown but off, with the reason.
      expect(updateButton(tester).onPressed, isNull);
      // The tooltip is kept out of the semantics tree (the label below says it),
      // so match the widget itself.
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Update is off while Pitchy can’t reach its server.',
        ),
        findsOneWidget,
      );
      // Screen readers hear the reason too (the tooltip is out of reach on touch).
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Update, unavailable while Pitchy can’t reach its server'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('phone: the "newer alerts may exist" caveat is never cut', (tester) async {
      final (_, prefs) = await pumpPitchyApp(tester, prefs: withActiveMatch());
      final stored = {
        for (final k in [SavedCopyStore.prefKey, 'match.activeId']) k: prefs.getString(k)!,
      };
      await tester.pumpWidget(const SizedBox());
      await pumpPitchyApp(tester, prefs: stored, scenario: MockScenario.offline);

      final caveat = find.textContaining('Newer alerts may exist');
      expect(caveat, findsOneWidget);
      expect(tester.renderObject<RenderParagraph>(caveat).didExceedMaxLines, isFalse);
    });

    for (final offline in [false, true]) {
      testWidgets('360 px at 200% text (${offline ? 'saved copy' : 'live'}): '
          'no state word, value, title, venue, kickoff or alert is cut', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final (api, _) = await pumpPitchyApp(
          tester,
          size: const Size(360, 3000),
          prefs: withActiveMatch(),
          scenario: MockScenario.someStale,
        );
        if (offline) {
          api.scenario = MockScenario.offline;
          await tester.tap(find.byTooltip('Refresh'));
          await tester.pumpAndSettle();
          expect(banner(), findsOneWidget);
        }
        expect(find.textContaining('SYNTHETIC'), findsWidgets, reason: 'an alert is shown');
        for (final area in [
          find.byType(KickoffStrip),
          find.byType(AlertsPanel),
          find.byType(SourceRail),
          find.byType(WeatherCardGrid),
        ]) {
          final cut = [
            for (final e in find.descendant(of: area, matching: find.byType(RichText)).evaluate())
              if ((e.renderObject! as RenderParagraph).didExceedMaxLines)
                (e.widget as RichText).text.toPlainText(),
          ];
          expect(cut, isEmpty, reason: 'cut in ${area.describeMatch(Plurality.one)}');
        }
      });
    }

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

    testWidgets('screen readers hear each card once: title, value, source, state', (tester) async {
      final semantics = tester.ensureSemantics();
      final (api, _) = await pumpPitchyApp(
        tester,
        prefs: withActiveMatch(),
        scenario: MockScenario.someStale,
      );
      api.scenario = MockScenario.offline;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      final node = find.semantics
          .byPredicate((n) => n.label.contains('Heat index (PAGASA): 40'))
          .evaluate()
          .single;
      final label = node.label;
      // Found on the phone: the title and the state were each said twice,
      // and "Stale · saved" would be read with its dot.
      expect(RegExp('Heat index').allMatches(label), hasLength(1), reason: label);
      expect(RegExp('Stale, saved copy').allMatches(label), hasLength(1), reason: label);
      expect(label, isNot(contains('·')));
      expect(label, isNot(contains('Data state')));
      // The rail says it the same way.
      expect(
        find.bySemanticsLabel('PAGASA ATMO (panahon.gov.ph): Stale, saved copy'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('a repeated failed Try again says so (F5 P2-2)', (tester) async {
      final (api, _) = await pumpPitchyApp(tester, prefs: withActiveMatch());
      api.scenario = MockScenario.offline;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Pitchy can’t reach its server.'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Pitchy can’t reach its server.'), findsNothing);
      expect(find.text('Still can’t reach its server (try 2, 12:00 PM PHT).'), findsOneWidget);

      // Each try changes the words, so the live region speaks again.
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Still can’t reach its server (try 3, 12:00 PM PHT).'), findsOneWidget);

      // Back online: the count is gone with the copy.
      api.scenario = MockScenario.allCurrent;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(banner(), findsNothing);
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

  group('narrow phone, long real strings (platform QA F-1)', () {
    // Wed 25 Nov 12:00 UTC: the mock kickoff is three hours later, 11:00 PM PHT,
    // the longest time string the app shows.
    final late = DateTime.utc(2026, 11, 25, 12);

    for (final offline in [false, true]) {
      testWidgets('347 px at 100% text (${offline ? 'saved copy' : 'live'}): nothing is cut', (
        tester,
      ) async {
        final (api, _) = await pumpPitchyApp(
          tester,
          size: const Size(347, 2400),
          prefs: withActiveMatch(),
          now: late,
        );
        if (offline) {
          api.scenario = MockScenario.offline;
          await tester.tap(find.byTooltip('Refresh'));
          await tester.pumpAndSettle();
          expect(banner(), findsOneWidget);
        }
        expect(find.textContaining('11:00 PM PHT'), findsWidgets);
        for (final area in [
          find.byType(KickoffStrip),
          find.byType(AlertsPanel),
          find.byType(SourceRail),
          find.byType(WeatherCardGrid),
        ]) {
          final cut = [
            for (final e in find.descendant(of: area, matching: find.byType(RichText)).evaluate())
              if ((e.renderObject! as RenderParagraph).didExceedMaxLines)
                (e.widget as RichText).text.toPlainText(),
          ];
          expect(cut, isEmpty, reason: 'cut in ${area.describeMatch(Plurality.one)}');
        }
      });
    }
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
      // The banner gives the time once; no second "Not current" line.
      expect(find.byType(NotCurrentLine), findsNothing);
      expect(find.byType(AssessmentFailureBanner), findsNothing);
      expect(find.text('NOT CURRENT'), findsWidgets);

      // F5 P2-2: a second failed Try again changes the banner's words.
      expect(find.text('Pitchy can’t reach its server.'), findsOneWidget);
      // The banner's own Try again (lightning has one of its own).
      await tester.tap(
        find.descendant(of: find.byType(NoticeBanner), matching: find.text('Try again')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Still can’t reach its server (try 2, 12:00 PM PHT).'), findsOneWidget);
      expect(banner(), findsOneWidget);
    });
  });
}
