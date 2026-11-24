import 'package:flutter_test/flutter_test.dart';
import 'package:pitchy/shared/models/assessment.dart';
import 'package:pitchy/shared/models/lightning.dart';
import 'package:pitchy/shared/models/match.dart';
import 'package:pitchy/shared/models/weather.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';

void main() {
  final now = DateTime.utc(2026, 11, 23, 4);

  SafetyAssessment assessment(SafetyScenario s) => SafetyAssessment.fromJson(
    assessmentJson(now: now, kickoff: safetyKickoff(s, now), scenario: s),
  );
  VenueLightning lightning(SafetyScenario s) => VenueLightning.fromJson(
    lightningJson(now: now, kickoff: safetyKickoff(s, now), scenario: s),
  );
  HazardIndicator indicator(SafetyAssessment a, Hazard h) =>
      a.indicators.firstWhere((i) => i.hazard == h);

  test('every scenario parses as an assessment and as lightning', () {
    for (final s in SafetyScenario.values) {
      expect(assessment(s).indicators.map((i) => i.hazard), [
        Hazard.heat,
        Hazard.lightning,
        Hazard.rainfall,
      ], reason: s.name);
      expect(lightning(s).flashes, isA<List<Flash>>());
    }
  });

  group('assessment', () {
    test('heatBelow reads the level verbatim; lightning and rainfall have no level', () {
      final a = assessment(SafetyScenario.heatBelow);
      final heat = indicator(a, Hazard.heat);
      expect(a.rulesApproved, isTrue);
      expect(a.ageGroup, AgeGroup.senior);
      expect(heat.status, IndicatorStatus.available);
      expect(heat.indicatorValue, closeTo(29.9, 0.05));
      expect(heat.classification, 'below_cooling_break_level');
      expect(heat.level!.label, 'Below the cooling-break level');
      expect(heat.level!.source.authority, 'FIFA');
      expect(heat.level!.alsoSupportedBy.single.documentId, 'afc_com_2026');
      expect(heat.decidedBy, contains('match management team'));
      expect(indicator(a, Hazard.lightning).status, IndicatorStatus.unavailable);
      expect(indicator(a, Hazard.lightning).level, isNull);
      final rain = indicator(a, Hazard.rainfall);
      expect(rain.classification, isNull);
      expect(rain.limitations.single.code, 'NO_APPROVED_RULE');
      expect(a.limitations.single.code, 'OFFICIALS_DECIDE');
      expect(a.officialNotices, hasLength(1));
    });

    test('coolingBreaks has two points with one used, hourly values and notices', () {
      final heat = indicator(assessment(SafetyScenario.coolingBreaks), Hazard.heat);
      expect(heat.classification, 'cooling_breaks_required');
      expect(heat.level!.label, 'At or above the cooling-break level (WBGT 32 °C)');
      expect(heat.indicatorValue, greaterThanOrEqualTo(32));
      expect(heat.points, hasLength(2));
      expect(heat.points.where((p) => p.usedForLevel), hasLength(1));
      expect(heat.points.last.at.difference(heat.points.first.at), const Duration(minutes: 30));
      expect(heat.hourly, hasLength(3));
      expect(heat.hourly.any((p) => p.usedForLevel), isFalse);
      expect(heat.notices.single.id, 'pff_avoid_midday');
      expect(heat.inputs, hasLength(5));
    });

    test('youth uses the 28 °C level set and the youth age group', () {
      final a = assessment(SafetyScenario.youth);
      expect(a.ageGroup, AgeGroup.youthU20);
      expect(a.matchContext.ageGroup, AgeGroup.youthU20);
      final heat = indicator(a, Hazard.heat);
      expect(heat.indicatorValue, lessThan(32));
      expect(heat.classification, 'cooling_breaks_required');
      expect(heat.level!.label, contains('youth cooling-break level (WBGT 28'));
      expect(heat.level!.source.documentId, 'afc_com_2026');
    });

    test('a youth match makes the default scenario youth too', () {
      final a = SafetyAssessment.fromJson(
        assessmentJson(
          now: now,
          kickoff: safetyKickoff(SafetyScenario.heatBelow, now),
          ageGroup: 'youth_u20',
        ),
      );
      expect(a.ageGroup, AgeGroup.youthU20);
      expect(a.matchContext.ageGroup, AgeGroup.youthU20);
    });

    test('heatMissing has no value, classification or level and lists missing inputs', () {
      final heat = indicator(assessment(SafetyScenario.heatMissing), Hazard.heat);
      expect(heat.status, IndicatorStatus.unavailable);
      expect(heat.indicatorValue, isNull);
      expect(heat.classification, isNull);
      expect(heat.level, isNull);
      expect(heat.points.every((p) => p.value == null && p.missing.isNotEmpty), isTrue);
      expect(heat.points.any((p) => p.usedForLevel), isFalse);
      expect(heat.limitations.map((l) => l.code), contains('MISSING_INPUT'));
    });

    test('lightningNear shows the level and the procedure', () {
      final light = indicator(assessment(SafetyScenario.lightningNear), Hazard.lightning);
      expect(light.status, IndicatorStatus.available);
      expect(light.indicatorValue, 8.2);
      expect(light.classification, 'within_30_second_distance');
      expect(light.level!.label, 'Lightning within about 10 km (AFC 30-second distance)');
      expect(light.procedure, hasLength(3));
      expect(light.guidance.single.documentId, 'afc_com_2026');
    });

    test('lightningStale has no level and a stale limitation', () {
      final light = indicator(assessment(SafetyScenario.lightningStale), Hazard.lightning);
      expect(light.status, IndicatorStatus.unavailable);
      expect(light.level, isNull);
      expect(light.procedure, isEmpty);
      expect(light.limitations.map((l) => l.code), contains('STALE_INPUT'));
    });

    test('rulesDraft is not approved', () {
      final a = assessment(SafetyScenario.rulesDraft);
      expect(a.rulesApproved, isFalse);
      expect(a.limitations.map((l) => l.code), contains('RULES_NOT_APPROVED'));
    });
  });

  group('lightning', () {
    test('outside the live window nothing was checked', () {
      final l = lightning(SafetyScenario.heatBelow);
      expect(l.inLiveWindow, isFalse);
      expect(l.status.state, WeatherDataState.missing);
      expect(l.flashCount, isNull);
      expect(l.flashes, isEmpty);
      expect(l.level, isNull);
      expect(l.guidance, isNull);
      expect(l.attribution.text, 'Powered by Vaisala Xweather');
    });

    test('lightningNear is current with flashes nearest first, level and guidance', () {
      final l = lightning(SafetyScenario.lightningNear);
      expect(l.inLiveWindow, isTrue);
      expect(l.status.state, WeatherDataState.current);
      expect(l.flashCount, 3);
      expect(l.nearestKm, 8.2);
      expect(l.flashes, hasLength(3));
      final km = l.flashes.map((f) => f.distanceKm).toList();
      expect(km, [...km]..sort());
      expect(km.first, l.nearestKm);
      expect(l.level!.id, 'within_30_second_distance');
      expect(l.guidance!.shownBecause, ['LIGHTNING_DETECTED']);
      expect(l.guidance!.procedure, hasLength(3));
      expect(l.note, contains('Officials on site decide'));
    });

    test('lightningStale is stale with an error code and no level or guidance', () {
      final l = lightning(SafetyScenario.lightningStale);
      expect(l.inLiveWindow, isTrue);
      expect(l.status.state, WeatherDataState.stale);
      expect(l.status.lastErrorCode, 'HTTP_503');
      expect(now.difference(l.status.lastCheckedAt!), const Duration(minutes: 9));
      expect(l.level, isNull);
      expect(l.guidance, isNull);
    });
  });
}
