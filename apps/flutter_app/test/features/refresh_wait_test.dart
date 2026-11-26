import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/features/dashboard/ingest_widgets.dart';
import 'package:pitchy/shared/models/ingestion.dart';
import 'package:pitchy/shared/models/weather.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';
import 'package:pitchy/shared/widgets/wait_text.dart';

import '../app_harness.dart';
import '../helpers.dart';

/// Answers the update with a 202 that leaves PAGASA waiting (P-27 A4).
class _WaitingApi extends MockPitchyApi {
  _WaitingApi()
    : super(scenario: MockScenario.someStale, clock: () => testNow, latency: Duration.zero);

  @override
  Future<IngestionRequestResult> requestIngestion(String matchContextId) async {
    ingestionRequests++;
    return IngestionRequestResult.fromJson(
      ingestionRequestJson(
        now: testNow,
        waiting: [
          {
            'source_ids': ['pagasa_atmo', 'pagasa_ecmwf'],
            'retry_at': testNow.add(const Duration(hours: 1, minutes: 40)).toIso8601String(),
            'reason': 'min_interval',
          },
        ],
      ),
    );
  }
}

void main() {
  final at = testNow.add(const Duration(minutes: 15)); // 12:15 PM PHT

  group('wording', () {
    test('each reason has its own words, with the backend time in PHT', () {
      expect(
        waitLine(WaitReason.minInterval, at, now: testNow),
        'Next check 12:15 PM PHT: asked recently, and Pitchy limits how often',
      );
      expect(
        waitLine(WaitReason.sourceRefused, at, now: testNow),
        'Next check 12:15 PM PHT: the source refused the last request',
      );
      expect(
        waitLine(WaitReason.failureCooldown, at, now: testNow),
        'Next try 12:15 PM PHT: the last try failed',
      );
      expect(waitLine(WaitReason.other, at, now: testNow), 'Next check 12:15 PM PHT');
      expect(waitLine(null, at, now: testNow), 'Next check 12:15 PM PHT');
    });

    test('a time on another PHT day names the day', () {
      final tomorrow = testNow.add(const Duration(days: 1));
      expect(waitLine(null, tomorrow, now: testNow), startsWith('Next check Tue 24 Nov, '));
    });

    test('no next_request_at, no line (older backend, or can ask now)', () {
      final s = SourceStatus.fromJson({
        'source_id': 'open_meteo',
        'source_name': 'Open-Meteo',
        'state': 'current',
        'covers_match_time': true,
        'provenance': null,
      });
      expect(sourceWaitLine(s, now: testNow), isNull);
    });

    test('a 202 waiting list in words', () {
      final status = WeatherStatus.fromJson(
        weatherStatusJson(MockScenario.someStale, now: testNow, kickoff: testKickoff),
      );
      final text = waitingSummary(
        [
          IngestionWait(
            sourceIds: const ['pagasa_atmo', 'pagasa_ecmwf'],
            retryAt: at,
            reason: WaitReason.minInterval,
          ),
        ],
        status.sources,
        now: testNow,
      );
      expect(
        text,
        'PAGASA ATMO and PAGASA ECMWF: next check 12:15 PM PHT: asked recently, '
        'and Pitchy limits how often',
      );
      expect(waitingSummary(const [], status.sources, now: testNow), isNull);
    });
  });

  group('on the dashboard', () {
    testWidgets('the rail says when a stale source is asked again, and why', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpPitchyApp(tester, prefs: withActiveMatch(), scenario: MockScenario.someStale);
      if (find.byTooltip('Show source details').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Show source details'));
        await tester.pumpAndSettle();
      }
      // Mock: PAGASA ATMO stale, next check 1 h 40 min after testNow (1:40 PM PHT).
      expect(
        find.text('Next check 1:40 PM PHT: asked recently, and Pitchy limits how often'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^PAGASA ATMO \(panahon\.gov\.ph\): Stale\..*Next check 1:40 PM PHT'),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('a source that can be asked now has no wait line', (tester) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch());
      if (find.byTooltip('Show source details').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Show source details'));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('Next check'), findsNothing);
      expect(find.textContaining('Next try'), findsNothing);
    });

    testWidgets('a 429 lists each waiting source with its own time', (tester) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch(), scenario: MockScenario.unavailable);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(find.text('Update again at 12:15 PM PHT'), findsOneWidget);
      expect(find.text('PAGASA ECMWF: Next try 12:15 PM PHT: the last try failed'), findsOneWidget);
    });

    testWidgets('a 202 that leaves sources waiting says so after the update', (tester) async {
      final api = _WaitingApi();
      await pumpPitchyApp(tester, prefs: withActiveMatch(), api: api);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle(const Duration(seconds: 4));
      for (var i = 0; i < 5 && find.byType(SnackBar).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      expect(
        find.textContaining(
          'Weather data updated. PAGASA ATMO and PAGASA ECMWF: next check 1:40 PM PHT',
        ),
        findsOneWidget,
      );
    });
  });
}
