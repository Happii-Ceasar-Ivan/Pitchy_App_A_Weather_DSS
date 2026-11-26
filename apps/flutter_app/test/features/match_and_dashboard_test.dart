import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/core/storage/saved_copies.dart';
import 'package:pitchy/features/dashboard/trend/trend_card.dart';
import 'package:pitchy/features/match_management/match_controller.dart';
import 'package:pitchy/shared/models/match.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';
import 'package:pitchy/shared/widgets/request_states.dart';
import 'package:pitchy/shared/widgets/source_rail.dart';
import 'package:pitchy/shared/widgets/weather_value_card.dart';

import '../app_harness.dart';
import '../helpers.dart';

/// testNow is 12:00 PM PHT on Mon 23 Nov 2026.
String _draft({
  String? venue = 'rizal_memorial',
  String date = '2026-11-23',
  String? time = '15:0',
}) => jsonEncode({'venue': venue, 'date': date, 'time': time, 'surface': null});

void main() {
  group('match controller', () {
    MatchController controller([Map<String, String>? prefs]) => MatchController(
      api: MockPitchyApi(clock: () => testNow, latency: Duration.zero),
      preferences: MemoryPreferences(prefs),
      clock: () => testNow,
    );

    test('form checks: venue, date and time required; kickoff not in the past', () {
      final c = controller();
      expect(c.problems(), [DraftProblem.noVenue, DraftProblem.noDate, DraftProblem.noTime]);
      c.updateDraft(
        MatchDraft(
          venueKey: 'rizal_memorial',
          date: DateTime.utc(2026, 11, 23),
          time: const TimeOfDay(hour: 11, minute: 0), // 11 AM PHT, before testNow (12 PM PHT)
        ),
      );
      expect(c.problems(), [DraftProblem.kickoffInPast]);
      c.updateDraft(c.draft.copyWith(time: const TimeOfDay(hour: 15, minute: 0)));
      expect(c.problems(), isEmpty);
    });

    test('kickoff entered in PHT is sent to the backend in UTC', () async {
      final c = controller({PrefKeys.matchDraft: _draft()});
      final match = await c.submit();
      expect(match.kickoffAt, DateTime.utc(2026, 11, 23, 7)); // 3:00 PM PHT
      expect(match.venue.scopeKey, 'rizal_memorial');
    });

    test('the draft survives leaving the screen (saved on the device)', () {
      final prefs = MemoryPreferences();
      MatchController(
        api: MockPitchyApi(latency: Duration.zero),
        preferences: prefs,
      ).updateDraft(
        const MatchDraft(venueKey: 'new_clark_city', surface: PitchSurface.syntheticTurf),
      );
      final again = MatchController(
        api: MockPitchyApi(latency: Duration.zero),
        preferences: prefs,
      );
      expect(again.draft.venueKey, 'new_clark_city');
      expect(again.draft.surface, PitchSurface.syntheticTurf);
    });

    test('age group: senior by default, saved with the draft, sent to the backend', () async {
      final prefs = MemoryPreferences({PrefKeys.matchDraft: _draft()});
      final c = MatchController(
        api: MockPitchyApi(clock: () => testNow, latency: Duration.zero),
        preferences: prefs,
        clock: () => testNow,
      );
      expect(c.draft.ageGroup, AgeGroup.senior);
      expect(const MatchDraft(ageGroup: AgeGroup.youthU20).isEmpty, isTrue);
      c.updateDraft(c.draft.copyWith(ageGroup: AgeGroup.youthU20));
      final again = MatchController(
        api: MockPitchyApi(latency: Duration.zero),
        preferences: prefs,
      );
      expect(again.draft.ageGroup, AgeGroup.youthU20);
      final match = await c.submit();
      expect(match.ageGroup, AgeGroup.youthU20);
    });

    test('a request without a chosen age group leaves it to the backend', () {
      final json = MatchContextCreate(
        kickoffAt: DateTime.utc(2026, 11, 23, 7),
        venueScopeKey: 'rizal_memorial',
      ).toJson();
      expect(json.containsKey('age_group'), isFalse);
      expect(
        MatchContextCreate(
          kickoffAt: DateTime.utc(2026, 11, 23, 7),
          venueScopeKey: 'rizal_memorial',
          ageGroup: AgeGroup.youthU20,
        ).toJson()['age_group'],
        'youth_u20',
      );
    });

    test('a successful setup clears the draft and remembers the active match', () async {
      final prefs = MemoryPreferences({PrefKeys.matchDraft: _draft()});
      final c = MatchController(
        api: MockPitchyApi(clock: () => testNow, latency: Duration.zero),
        preferences: prefs,
        clock: () => testNow,
      );
      await c.submit();
      expect(c.draft.isEmpty, isTrue);
      expect(prefs.getString(PrefKeys.matchDraft), isNull);
      expect(prefs.getString(PrefKeys.activeMatchId), rizalMemorialId);
    });
  });

  group('match setup screen', () {
    testWidgets('no match: the dashboard offers one action, Set up a match', (tester) async {
      await pumpPitchyApp(tester);
      expect(find.text('No match set up'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('sending without a venue or time shows what is missing', (tester) async {
      await pumpPitchyApp(tester);
      await tester.tap(find.text('Set up a match'));
      await tester.pumpAndSettle();
      expect(find.text('Rizal Memorial Stadium'), findsOneWidget);
      expect(find.text('New Clark City Athletics Stadium'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Show conditions'), 200);
      await tester.tap(find.text('Show conditions'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a venue.'), findsOneWidget);
      expect(find.text('Choose a kickoff time.'), findsOneWidget);
    });

    testWidgets('age group is a visible two-way choice, Senior preselected', (tester) async {
      await pumpPitchyApp(tester, prefs: {PrefKeys.matchDraft: _draft()});
      await tester.tap(find.text('Set up a match'));
      await tester.pumpAndSettle();
      final choice = find.byType(SegmentedButton<AgeGroup>);
      await tester.scrollUntilVisible(choice, 200);
      expect(tester.widget<SegmentedButton<AgeGroup>>(choice).selected, {AgeGroup.senior});
      await tester.tap(find.text('Under-20 or younger'));
      await tester.pumpAndSettle();
      expect(tester.widget<SegmentedButton<AgeGroup>>(choice).selected, {AgeGroup.youthU20});
    });

    testWidgets('a kickoff earlier than now is refused', (tester) async {
      await pumpPitchyApp(tester, prefs: {PrefKeys.matchDraft: _draft(time: '9:0')});
      await tester.tap(find.text('Set up a match'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Show conditions'), 200);
      await tester.tap(find.text('Show conditions'));
      await tester.pumpAndSettle();
      expect(find.text('Kickoff has to be later than now.'), findsOneWidget);
    });

    testWidgets('a complete form opens the dashboard for that match, kickoff in PHT', (
      tester,
    ) async {
      await pumpPitchyApp(tester, prefs: {PrefKeys.matchDraft: _draft()});
      await tester.tap(find.text('Set up a match'));
      await tester.pumpAndSettle();
      expect(find.text('Mon 23 Nov'), findsOneWidget);
      expect(find.text('3:00 PM PHT'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Show conditions'), 200);
      await tester.tap(find.text('Show conditions'));
      await tester.pumpAndSettle();
      expect(find.text('Kickoff Mon 23 Nov, 3:00 PM PHT'), findsOneWidget);
      expect(find.byType(SourceRail), findsOneWidget);
      expect(find.byType(WeatherCardGrid), findsOneWidget);
    });
  });

  group('dashboard', () {
    // Real fonts: the geometry check must measure what users see.
    setUpAll(loadAppFonts);

    testWidgets('skeleton first, then the board lands in the same place', (tester) async {
      await pumpPitchyApp(
        tester,
        prefs: withActiveMatch(),
        latency: const Duration(milliseconds: 300),
        settle: false,
      );
      // Match restored (one request), weather still loading (second request).
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(SourceRailSkeleton), findsOneWidget);
      expect(find.byType(WeatherCardGridSkeleton), findsOneWidget);
      expect(find.byType(TrendCardSkeleton), findsOneWidget);
      final skeletonTrend = tester.getRect(find.byType(TrendCardSkeleton));
      final skeletonRail = tester.getRect(find.byType(SourceRailSkeleton));
      final skeletonGrid = tester.getRect(find.byType(WeatherCardGridSkeleton)).topLeft;
      final skeletonCardTops = [
        for (final e
            in find
                .descendant(of: find.byType(WeatherCardGridSkeleton), matching: find.byType(Card))
                .evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dy,
      ]..sort();

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final rail = tester.getRect(find.byType(SourceRail));
      expect(rail.topLeft, skeletonRail.topLeft);
      expect(rail.width, skeletonRail.width);
      expect((rail.height - skeletonRail.height).abs(), lessThan(1.5));
      final trend = tester.getRect(find.byType(TrendCard));
      expect((trend.top - skeletonTrend.top).abs(), lessThan(1.5));
      expect((trend.height - skeletonTrend.height).abs(), lessThan(1.5));
      final grid = tester.getRect(find.byType(WeatherCardGrid)).topLeft;
      expect((grid.dy - skeletonGrid.dy).abs(), lessThan(1.5));
      expect(grid.dx, skeletonGrid.dx);
      // Every card row lands where its skeleton row was (stale cards included).
      final skeletonCards = skeletonCardTops;
      final cards = [
        for (final e in find.byType(WeatherValueCard).evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dy,
      ]..sort();
      expect(cards.toSet().length, skeletonCards.toSet().length);
      for (final (i, y) in cards.toSet().indexed) {
        expect((y - skeletonCards.toSet().elementAt(i)).abs(), lessThan(1.5));
      }
    });

    testWidgets('the match strip shows venue and kickoff in PHT', (tester) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch());
      expect(find.text('Rizal Memorial Stadium, Manila'), findsOneWidget);
      expect(find.textContaining('Kickoff Mon 23 Nov'), findsOneWidget);
      expect(find.textContaining('PHT'), findsWidgets);
    });

    testWidgets('a server error with no saved copy shows a recoverable error', (tester) async {
      final (api, prefs) = await pumpPitchyApp(
        tester,
        prefs: withActiveMatch(),
        scenario: MockScenario.serviceError,
      );
      // Nothing was ever saved, so there is no copy to fall back to.
      expect(prefs.getString(SavedCopyStore.prefKey), isNull);
      expect(find.byType(SourceRail), findsNothing);
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Server temporarily unavailable'), findsOneWidget);
      api.scenario = MockScenario.allCurrent;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byType(SourceRail), findsOneWidget);
    });

    testWidgets('an ingestion job running for the venue shows Updating', (tester) async {
      await pumpPitchyApp(
        tester,
        prefs: withActiveMatch(),
        scenario: MockScenario.updating,
        settle: false, // the Updating spinner runs until the job ends
      );
      final semantics = tester.ensureSemantics();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.bySemanticsLabel(RegExp('Updating weather data')), findsOneWidget);
      semantics.dispose();
      expect(find.text('Update'), findsNothing); // no second request while a job runs
    });

    testWidgets('sources, trend, tiles stack on phones and wide windows alike', (
      tester,
    ) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch());
      var rail = tester.getRect(find.byType(SourceRail));
      var trend = tester.getRect(find.byType(TrendCard));
      var grid = tester.getRect(find.byType(WeatherCardGrid));
      // P-27: sources, then the hourly trend, then the tiles.
      expect(trend.top, greaterThan(rail.bottom));
      expect(grid.top, greaterThan(trend.bottom));

      await pumpPitchyApp(tester, prefs: withActiveMatch(), size: const Size(1400, 900));
      rail = tester.getRect(find.byType(SourceRail));
      trend = tester.getRect(find.byType(TrendCard));
      grid = tester.getRect(find.byType(WeatherCardGrid));
      // Wide: the same order, each across the full width (no empty column).
      expect(trend.top, greaterThan(rail.bottom));
      expect(grid.top, greaterThan(trend.bottom));
      expect((trend.left, trend.right), (rail.left, rail.right));
      expect((grid.left, grid.right), (rail.left, rail.right));
    });
  });
}
