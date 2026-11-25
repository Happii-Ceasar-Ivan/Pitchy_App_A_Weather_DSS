import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/errors/api_failure.dart';
import 'package:pitchy/core/state/loadable.dart';
import 'package:pitchy/core/theme/app_theme.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';
import 'package:pitchy/features/dashboard/ingestion_controller.dart';
import 'package:pitchy/shared/models/alerts.dart';
import 'package:pitchy/shared/models/ingestion.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';
import 'package:pitchy/shared/widgets/alerts_panel.dart';
import 'package:pitchy/shared/widgets/source_rail.dart';

import '../app_harness.dart';
import '../helpers.dart';

/// A mock whose job polls never finish, or always fail.
class _StuckApi extends MockPitchyApi {
  _StuckApi({required this.failPolls})
    : super(scenario: MockScenario.someStale, clock: () => testNow, latency: Duration.zero);

  final bool failPolls;

  @override
  Future<IngestionJob> getIngestionJob(String jobId) async {
    if (failPolls) throw const NetworkFailure();
    return IngestionJob.fromJson(ingestionJobJson(id: jobId, state: 'running', created: testNow));
  }
}

/// Clock that moves with the test's fake time.
class _Clock {
  _Clock(this.tester) : _start = tester.binding.clock.now();
  final WidgetTester tester;
  final DateTime _start;
  DateTime call() => testNow.add(tester.binding.clock.now().difference(_start));
}

void main() {
  group('ingestion controller', () {
    (IngestionController, MockPitchyApi, List<int>) make(
      MockScenario scenario, {
      MockPitchyApi? api,
      DateTime Function()? clock,
    }) {
      final mock =
          api ?? MockPitchyApi(scenario: scenario, clock: () => testNow, latency: Duration.zero);
      final reloads = <int>[];
      final c = IngestionController(
        api: mock,
        matchContextId: rizalMemorialId,
        onFinished: () async => reloads.add(1),
        clock: clock ?? () => testNow,
      );
      addTearDown(c.dispose);
      return (c, mock, reloads);
    }

    testWidgets('one request at a time; jobs are polled until done, then the board reloads', (
      tester,
    ) async {
      final (c, mock, reloads) = make(MockScenario.someStale);
      final first = c.request();
      unawaited(c.request()); // a double tap
      await first;
      expect(mock.ingestionRequests, 1);
      expect(c.phase, IngestPhase.polling);
      expect(c.jobCount, 2);
      expect(c.canRequest, isFalse);
      unawaited(c.request()); // still ignored while polling
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      expect(mock.ingestionRequests, 1);
      expect(c.phase, IngestPhase.idle);
      expect(c.outcome, isA<IngestUpdated>());
      expect(reloads, hasLength(1));
    });

    testWidgets('409: nothing to update, and the board reloads', (tester) async {
      final (c, _, reloads) = make(MockScenario.allCurrent);
      await c.request();
      expect(c.outcome, isA<IngestNotNeeded>());
      expect(reloads, hasLength(1));
      expect(c.canRequest, isTrue);
    });

    testWidgets('429: holds further requests until retry_at, then allows one again', (
      tester,
    ) async {
      final clock = _Clock(tester);
      final api = MockPitchyApi(
        scenario: MockScenario.unavailable,
        clock: clock.call,
        latency: Duration.zero,
      );
      final (c, _, reloads) = make(MockScenario.unavailable, api: api, clock: clock.call);
      await c.request();
      final outcome = c.outcome;
      expect(outcome, isA<IngestMustWait>());
      expect((outcome! as IngestMustWait).retryAt, isNotNull);
      expect(c.canRequest, isFalse);
      expect(reloads, isEmpty);
      await c.request();
      expect(api.ingestionRequests, 1);
      await tester.pump(const Duration(minutes: 15, seconds: 1));
      expect(c.canRequest, isTrue);
    });

    testWidgets('failed jobs are reported with the backend’s messages', (tester) async {
      final (c, _, reloads) = make(MockScenario.ingestFails);
      await c.request();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      final outcome = c.outcome;
      expect(outcome, isA<IngestJobsFailed>());
      expect((outcome! as IngestJobsFailed).failures.single.message, 'Source did not respond.');
      expect(reloads, hasLength(1));
    });

    testWidgets('a request that doesn’t get through can be sent again', (tester) async {
      final (c, mock, _) = make(MockScenario.offline);
      await c.request();
      expect(c.outcome, isA<IngestRequestFailed>());
      expect(c.canRequest, isTrue);
      mock.scenario = MockScenario.someStale;
      await c.request();
      expect(c.phase, IngestPhase.polling);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
    });

    testWidgets('stops checking after repeated failed polls', (tester) async {
      final (c, _, reloads) = make(MockScenario.someStale, api: _StuckApi(failPolls: true));
      await c.request();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      expect(c.outcome, isA<IngestStoppedChecking>());
      expect(c.phase, IngestPhase.idle);
      expect(reloads, isEmpty);
    });

    testWidgets('stops checking after the time limit when jobs never finish', (tester) async {
      final clock = _Clock(tester);
      final (c, _, _) = make(
        MockScenario.someStale,
        api: _StuckApi(failPolls: false),
        clock: clock.call,
      );
      await c.request();
      for (var i = 0; i < 81; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      expect(c.outcome, isA<IngestStoppedChecking>());
    });

    testWidgets('running jobs are watched without sending a request, and only once', (
      tester,
    ) async {
      final (c, mock, reloads) = make(MockScenario.updating);
      c.watch([pagasaJobId]);
      expect(c.phase, IngestPhase.polling);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      expect(mock.ingestionRequests, 0);
      expect(reloads, hasLength(1));
      c.watch([pagasaJobId]); // the reload may still list it
      expect(c.phase, IngestPhase.idle);
    });
  });

  group('dashboard update flow', () {
    setUpAll(loadAppFonts);

    testWidgets('no Update when the backend says nothing is needed', (tester) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch());
      expect(find.text('Update'), findsNothing);
    });

    testWidgets('Update shows when the backend reports ingestion_needed', (tester) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch(), scenario: MockScenario.someStale);
      expect(find.text('Update'), findsOneWidget);
    });

    testWidgets('Update: one request, progress, then the refreshed board and a confirmation', (
      tester,
    ) async {
      final (api, _) = await pumpPitchyApp(
        tester,
        prefs: withActiveMatch(),
        scenario: MockScenario.someStale,
      );
      final semantics = tester.ensureSemantics();
      await tester.tap(find.text('Update'));
      await tester.pump();
      expect(find.text('Update'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Updating weather data, 0 of 2')), findsOneWidget);
      semantics.dispose();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(api.ingestionRequests, 1);
      expect(find.text('Weather data updated.'), findsOneWidget);
      expect(find.text('Update'), findsNothing); // backend now says all current
      await tester.pump(const Duration(seconds: 5)); // snack bar leaves
      await tester.pumpAndSettle();
    });

    testWidgets('429 shows when updating is possible again, in PHT', (tester) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch(), scenario: MockScenario.unavailable);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(find.text('Update again at 12:15 PM PHT'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(of: find.text('Update'), matching: find.bySubtype<ButtonStyleButton>()),
      );
      expect(button.onPressed, isNull);
      // The reason stays on screen as long as the button is held.
      expect(find.byTooltip('Dismiss'), findsNothing);
    });

    testWidgets('large text: card headers wrap instead of cutting the PHT time', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpPitchyApp(tester, prefs: withActiveMatch(), scenario: MockScenario.someStale);
      for (final header in [
        find.textContaining('Sources · checked'),
        find.textContaining('Alerts · checked'),
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(header);
        expect(paragraph.didExceedMaxLines, isFalse);
      }
    });

    testWidgets('a failed job is explained per source and the data stays as reported', (
      tester,
    ) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch(), scenario: MockScenario.ingestFails);
      await tester.tap(find.text('Update'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();
      expect(find.text('The update didn’t finish'), findsOneWidget);
      expect(find.text('PAGASA ECMWF: Source did not respond.'), findsOneWidget);
      expect(find.byType(SourceRail), findsOneWidget);
    });

    testWidgets('no connection: the update is not sent and can be tried again', (tester) async {
      final (api, _) = await pumpPitchyApp(
        tester,
        prefs: withActiveMatch(),
        scenario: MockScenario.someStale,
      );
      api.scenario = MockScenario.offline;
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(find.text('Update not sent: no connection'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(of: find.text('Update'), matching: find.bySubtype<ButtonStyleButton>()),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('official alerts', () {
    setUpAll(loadAppFonts);

    testWidgets('shown above the board; expanding shows the text as plain text', (tester) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch(), scenario: MockScenario.someStale);
      final panel = tester.getRect(find.byType(AlertsPanel));
      expect(panel.bottom, lessThan(tester.getRect(find.byType(SourceRail)).top));
      expect(find.text('SYNTHETIC: Thunderstorm advisory for Metro Manila'), findsOneWidget);
      await tester.tap(find.text('SYNTHETIC: Thunderstorm advisory for Metro Manila'));
      await tester.pumpAndSettle();
      // Markup in source text is shown as typed, never interpreted.
      expect(find.text('SYNTHETIC demo text. <b>Never rendered as HTML.</b>'), findsOneWidget);
      expect(
        find.text('Official PAGASA information, shown as issued. Not a Pitchy classification.'),
        findsOneWidget,
      );
      expect(find.textContaining('PHT'), findsWidgets);
    });

    testWidgets('no alerts and a current check: says so', (tester) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch());
      expect(find.text('No official alerts for this venue'), findsOneWidget);
    });

    testWidgets('never says "no alerts" when the check is stale or unavailable', (tester) async {
      Loadable<VenueAlerts> alerts(String state) {
        final json = alertsJson(now: testNow);
        (json['status']! as Map<String, Object?>)['state'] = state;
        return Loaded(VenueAlerts.fromJson(json));
      }

      await pumpThemed(tester, AlertsPanel(alerts: alerts('stale')));
      expect(find.text('No official alerts for this venue'), findsNothing);
      expect(find.text('No alerts in the last check'), findsOneWidget);
      await pumpThemed(tester, AlertsPanel(alerts: alerts('unavailable')));
      expect(find.text('Official alerts unavailable'), findsOneWidget);
    });

    testWidgets('a failed alerts check doesn’t hide the weather and can be retried', (
      tester,
    ) async {
      var retried = false;
      await pumpThemed(
        tester,
        AlertsPanel(alerts: const Failed(NetworkFailure()), onRetry: () => retried = true),
      );
      expect(find.text('Couldn’t load official alerts'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });
  });

  group('alert panel polish (F3)', () {
    setUpAll(loadAppFonts);

    Loadable<VenueAlerts> withAlert() =>
        Loaded(VenueAlerts.fromJson(alertsJson(now: testNow, withAlert: true)));

    testWidgets('the collapsed alert row says "Details", then "Hide" when open', (tester) async {
      await pumpThemed(tester, AlertsPanel(alerts: withAlert()));
      expect(find.text('Details'), findsOneWidget);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Hide'), findsOneWidget);
    });

    testWidgets('at 1.6x text the expanded fields stack and nothing overflows', (tester) async {
      tester.view.physicalSize = const Size(360, 800) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(PitchyPalette.light),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: SingleChildScrollView(child: AlertsPanel(alerts: withAlert())),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final label = tester.getTopLeft(find.text('Issued by'));
      final value = tester.getTopLeft(find.text('PAGASA'));
      expect(value.dy, greaterThan(label.dy), reason: 'value sits under its label');
    });
  });

  group('alert rows wrap on phones (review P1-2, user 2026-11-26)', () {
    setUpAll(loadAppFonts);

    for (final width in [347.0, 360.0, 390.0]) {
      testWidgets('${width.toInt()} px at 100% text: headline, level, until and area are whole', (
        tester,
      ) async {
        await pumpPitchyApp(
          tester,
          size: Size(width, 1600),
          prefs: withActiveMatch(),
          scenario: MockScenario.someStale, // has an official alert
        );
        final panel = find.byType(AlertsPanel);
        expect(
          find.descendant(
            of: panel,
            matching: find.text('SYNTHETIC: Thunderstorm advisory for Metro Manila'),
          ),
          findsOneWidget,
        );
        final detail = find.descendant(
          of: panel,
          matching: find.textContaining(RegExp(r'^Advisory · until .+ PHT · Metro Manila$')),
        );
        expect(detail, findsOneWidget);
        final cut = [
          for (final e in find.descendant(of: panel, matching: find.byType(RichText)).evaluate())
            if ((e.renderObject! as RenderParagraph).didExceedMaxLines)
              (e.widget as RichText).text.toPlainText(),
        ];
        expect(cut, isEmpty);
      });
    }
  });

  group('skeletons (F2 parts)', () {
    setUpAll(loadAppFonts);

    for (final scenario in [
      MockScenario.allCurrent,
      MockScenario.someStale,
      MockScenario.missing,
      MockScenario.unavailable,
    ]) {
      testWidgets('alerts panel and rail land where their skeletons were (${scenario.name})', (
        tester,
      ) async {
        await pumpPitchyApp(
          tester,
          prefs: withActiveMatch(),
          scenario: scenario,
          latency: const Duration(milliseconds: 300),
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 350));
        final alertsSkeleton = tester.getRect(find.byType(AlertsPanelSkeleton));
        final railSkeleton = tester.getRect(find.byType(SourceRailSkeleton));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        final alerts = tester.getRect(find.byType(AlertsPanel));
        final rail = tester.getRect(find.byType(SourceRail));
        expect(alerts.topLeft, alertsSkeleton.topLeft);
        if (scenario == MockScenario.someStale) {
          // An official alert wraps in full on phones (its validity time and
          // area are never cut; user 2026-11-26), so the panel may grow, but
          // only downwards; the rail moves down by the same amount.
          final grew = alerts.height - alertsSkeleton.height;
          expect(grew, greaterThanOrEqualTo(-1.5));
          expect((rail.top - railSkeleton.top - grew).abs(), lessThan(1.5));
        } else {
          expect((alerts.height - alertsSkeleton.height).abs(), lessThan(1.5));
          expect((rail.top - railSkeleton.top).abs(), lessThan(1.5));
        }
        expect((rail.height - railSkeleton.height).abs(), lessThan(1.5));
      });
    }
  });
}

void unawaited(Future<void> f) {}
