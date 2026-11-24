import 'package:flutter_test/flutter_test.dart';
import 'package:pitchy/core/errors/api_failure.dart';
import 'package:pitchy/core/state/loadable.dart';
import 'package:pitchy/features/safety/safety_controller.dart';
import 'package:pitchy/features/safety/safety_level.dart';
import 'package:pitchy/shared/models/assessment.dart';
import 'package:pitchy/shared/models/lightning.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';

import '../helpers.dart';

/// Counts calls and can fail lightning on demand.
class _CountingApi extends MockPitchyApi {
  _CountingApi({super.safety}) : super(clock: () => testNow, latency: Duration.zero);

  int assessmentCalls = 0;
  int lightningCalls = 0;
  bool failLightning = false;

  @override
  Future<SafetyAssessment> getAssessment(String matchContextId) {
    assessmentCalls++;
    return super.getAssessment(matchContextId);
  }

  @override
  Future<VenueLightning> getLightning(String matchContextId) {
    lightningCalls++;
    if (failLightning) return Future.error(const NetworkFailure());
    return super.getLightning(matchContextId);
  }
}

class _FlakyAssessmentApi extends MockPitchyApi {
  _FlakyAssessmentApi() : super(clock: () => testNow, latency: Duration.zero);

  bool fail = false;

  @override
  Future<SafetyAssessment> getAssessment(String matchContextId) =>
      fail ? Future.error(const NetworkFailure()) : super.getAssessment(matchContextId);
}

void main() {
  SafetyController make(_CountingApi api) =>
      SafetyController(api: api, matchContextId: rizalMemorialId);

  group('safety controller', () {
    test('loads the assessment and the live lightning reading as sent', () async {
      final c = make(_CountingApi(safety: SafetyScenario.lightningNear));
      await c.load();
      final a = (c.assessment as Loaded<SafetyAssessment>).value;
      final l = (c.lightning as Loaded<VenueLightning>).value;
      final heat = a.indicators.firstWhere((i) => i.hazard == Hazard.heat);
      expect(heat.level, isNotNull);
      expect(l.inLiveWindow, isTrue);
      expect(l.flashCount, 3);
      c.dispose();
    });

    test('a failed lightning check never hides the assessment', () async {
      final api = _CountingApi()..failLightning = true;
      final c = make(api);
      await c.load();
      expect(c.assessment, isA<Loaded<SafetyAssessment>>());
      expect(c.lightning, isA<Failed<VenueLightning>>());
      c.dispose();
    });

    test('a 501 from the assessment is a failure, lightning still loads', () async {
      final c = make(_CountingApi(safety: SafetyScenario.notReady));
      await c.load();
      final failed = c.assessment as Failed<SafetyAssessment>;
      expect((failed.failure as ApiError).code, ApiErrorCode.notImplemented);
      expect(c.lightning, isA<Loaded<VenueLightning>>());
      c.dispose();
    });

    test('a failed assessment refresh keeps the last one only as Not current', () async {
      final api = _FlakyAssessmentApi();
      final c = SafetyController(api: api, matchContextId: rizalMemorialId);
      await c.load();
      expect(c.assessment, isA<Loaded<SafetyAssessment>>());
      expect(c.notCurrentAssessment, isNull, reason: 'nothing is old while loaded');
      api.fail = true;
      await c.load();
      expect(c.assessment, isA<Failed<SafetyAssessment>>());
      expect(c.notCurrentAssessment, isNotNull);
      api.fail = false;
      await c.load();
      expect(c.notCurrentAssessment, isNull);
      c.dispose();
    });

    testWidgets('one failed lightning check mid-match does not stop the refresh', (t) async {
      final api = _CountingApi(safety: SafetyScenario.lightningNear);
      final c = make(api)..setVisible(true);
      await c.load();
      expect(c.autoRefreshing, isTrue);
      api.failLightning = true;
      await t.pump(const Duration(seconds: 61));
      expect(c.lightning, isA<Failed<VenueLightning>>());
      expect(c.autoRefreshing, isTrue);
      api.failLightning = false;
      await t.pump(const Duration(seconds: 61));
      expect(c.lightning, isA<Loaded<VenueLightning>>());
      c.dispose();
    });

    test('a failed refresh replaces older data, never keeps it as current', () async {
      final api = _CountingApi(safety: SafetyScenario.lightningNear);
      final c = make(api);
      await c.load();
      expect(c.lightning, isA<Loaded<VenueLightning>>());
      api.failLightning = true;
      await c.load();
      expect(c.lightning, isA<Failed<VenueLightning>>());
      c.dispose();
    });

    testWidgets('refreshes every 60 s only while visible and in the live window', (t) async {
      {
        final api = _CountingApi(safety: SafetyScenario.lightningNear);
        final c = make(api);
        await c.load();
        expect(api.lightningCalls, 1);
        expect(c.autoRefreshing, isFalse, reason: 'not visible yet');

        c.setVisible(true);
        expect(c.autoRefreshing, isTrue);
        await t.pump(const Duration(seconds: 61));
        expect(api.lightningCalls, 2);
        expect(api.assessmentCalls, 2);

        c.setVisible(false);
        expect(c.autoRefreshing, isFalse);
        await t.pump(const Duration(minutes: 5));
        expect(api.lightningCalls, 2, reason: 'no refresh while hidden');
        c.dispose();
      }
    });

    testWidgets('outside the live window it never refreshes on its own', (t) async {
      {
        final api = _CountingApi(); // heatBelow: kickoff 3 h away, outside the window
        final c = make(api);
        await c.load();
        c.setVisible(true);
        expect(c.autoRefreshing, isFalse);
        await t.pump(const Duration(minutes: 5));
        expect(api.lightningCalls, 1);
        c.dispose();
      }
    });

    testWidgets('dispose stops the refresh', (t) async {
      {
        final api = _CountingApi(safety: SafetyScenario.lightningNear);
        final c = make(api);
        await c.load();
        c
          ..setVisible(true)
          ..dispose();
        await t.pump(const Duration(minutes: 3));
        expect(api.lightningCalls, 1);
      }
    });
  });

  group('safety level colours (P-19)', () {
    test('known rule ids map to the fixed ramp; everything else is neutral', () {
      expect(safetyToneOf('cooling_breaks_required'), SafetyTone.warning);
      expect(safetyToneOf('within_30_second_distance'), SafetyTone.danger);
      expect(safetyToneOf('below_cooling_break_level'), isNull);
      expect(safetyToneOf('something_new'), isNull);
      expect(safetyToneOf(null), isNull);
    });
  });
}
