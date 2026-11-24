// Live check against the deployed backend (not part of the normal test run):
//   flutter test test_live
// Uses the app's own HTTP client and models, so every reply is parsed exactly as
// the app parses it. Creates one throwaway match context and may send one
// update request; the backend's PAGASA limits apply as for any user.

import 'package:flutter_test/flutter_test.dart';
import 'package:pitchy/core/config/app_config.dart';
import 'package:pitchy/core/errors/api_failure.dart';
import 'package:pitchy/core/network/http_pitchy_api.dart';
import 'package:pitchy/shared/models/match.dart';

void main() {
  final api = HttpPitchyApi(baseUrl: Uri.parse(AppConfig.defaultApiBaseUrl));

  test('the live backend answers in the shapes the app expects', () async {
    final venues = await api.listVenues();
    expect(venues.map((v) => v.scopeKey), containsAll(['rizal_memorial', 'new_clark_city']));

    final now = DateTime.now().toUtc();
    final kickoff = DateTime.utc(now.year, now.month, now.day, now.hour).add(
      const Duration(hours: 4),
    );
    final match = await api.createMatchContext(
      MatchContextCreate(venueScopeKey: 'rizal_memorial', kickoffAt: kickoff),
    );
    final status = await api.getWeatherStatus(match.id);
    final weather = await api.getWeather(match.id);
    final alerts = await api.getAlerts(match.id);
    expect(match.ageGroup, AgeGroup.senior); // backend default (B4)
    final assessment = await api.getAssessment(match.id);
    // ignore: avoid_print
    print(
      'assessment: rules_approved=${assessment.rulesApproved} '
      'rule_version=${assessment.ruleVersion} '
      'hazards=${assessment.indicators.map((i) => '${i.hazard.wire}:${i.status.wire}').join(', ')}',
    );
    // ignore: avoid_print
    print(
      'sources: ${status.sources.map((s) => '${s.sourceId}=${s.state.wire}').join(', ')}; '
      'ingestion_needed=${status.ingestionNeeded}; active=${status.activeJobIds.length}; '
      'quantities=${weather.quantities.length}; alerts=${alerts.alerts.length} '
      '(${alerts.status.state.wire})',
    );

    try {
      final result = await api.requestIngestion(match.id);
      // ignore: avoid_print
      print('202: ${result.jobs.map((j) => '${j.state.wire} reused=${j.reusedExistingJob}')}');
      for (final j in result.jobs) {
        final polled = await api.getIngestionJob(j.id);
        // ignore: avoid_print
        print('job ${j.id}: ${polled.state.wire}');
      }
    } on ApiError catch (e) {
      // ignore: avoid_print
      print('${e.statusCode} ${e.code.wire} retry_at=${e.retryAt}');
      expect([409, 429], contains(e.statusCode));
      if (e.statusCode == 429) expect(e.retryAt, isNotNull);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
