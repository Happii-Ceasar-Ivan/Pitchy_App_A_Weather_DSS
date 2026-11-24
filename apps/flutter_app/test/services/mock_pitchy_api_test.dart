import 'package:flutter_test/flutter_test.dart';
import 'package:pitchy/core/errors/api_failure.dart';
import 'package:pitchy/shared/models/ingestion.dart';
import 'package:pitchy/shared/models/weather.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';

void main() {
  final now = DateTime.utc(2026, 11, 23, 4);
  MockPitchyApi api(MockScenario s) =>
      MockPitchyApi(scenario: s, clock: () => now, latency: Duration.zero);

  test('each scenario produces the matching backend states', () async {
    expect(
      (await api(MockScenario.allCurrent).getWeatherStatus(rizalMemorialId)).sources
          .map((s) => s.state)
          .toSet(),
      {WeatherDataState.current},
    );
    final stale = await api(MockScenario.someStale).getWeatherStatus(rizalMemorialId);
    expect(stale.ingestionNeeded, isTrue);
    expect(stale.sources.where((s) => s.state == WeatherDataState.stale), hasLength(1));
    final updating = await api(MockScenario.updating).getWeatherStatus(rizalMemorialId);
    expect(updating.activeJobIds, isNotEmpty);
    expect(updating.ingestionNeeded, isFalse);
    final unavailable = await api(MockScenario.unavailable).getWeatherStatus(rizalMemorialId);
    expect(unavailable.nextIngestionAt, isNotNull);
  });

  test('offline and service errors throw the shared failures', () async {
    await expectLater(api(MockScenario.offline).listVenues(), throwsA(isA<NetworkFailure>()));
    await expectLater(
      api(MockScenario.serviceError).listVenues(),
      throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', 503)),
    );
  });

  test('ingestion jobs progress to succeeded on polling', () async {
    final mock = api(MockScenario.someStale);
    final result = await mock.requestIngestion(rizalMemorialId);
    expect(result.jobs, hasLength(2));
    expect(result.jobs.where((j) => j.reusedExistingJob), hasLength(1));
    expect(mock.scenario, MockScenario.updating);
    final id = result.jobs.first.id;
    final states = [for (var i = 0; i < 3; i++) (await mock.getIngestionJob(id)).state];
    expect(states, [
      IngestionJobState.queued,
      IngestionJobState.running,
      IngestionJobState.succeeded,
    ]);
    expect(mock.scenario, MockScenario.allCurrent);
  });

  test('a failing update job ends failed and the next request must wait', () async {
    final mock = api(MockScenario.ingestFails);
    final result = await mock.requestIngestion(rizalMemorialId);
    final pagasa = result.jobs.firstWhere((j) => j.id == pagasaJobId);
    IngestionJob job = pagasa;
    for (var i = 0; i < 3; i++) {
      job = await mock.getIngestionJob(pagasa.id);
    }
    expect(job.state, IngestionJobState.failed);
    expect(job.failures, isNotEmpty);
    await expectLater(
      mock.requestIngestion(rizalMemorialId),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', ApiErrorCode.rateLimited)),
    );
  });

  test('ingestion is refused when not needed or during cooldown', () async {
    await expectLater(
      api(MockScenario.allCurrent).requestIngestion(rizalMemorialId),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', ApiErrorCode.ingestionNotNeeded)),
    );
    await expectLater(
      api(MockScenario.unavailable).requestIngestion(rizalMemorialId),
      throwsA(isA<ApiError>().having((e) => e.retryAt, 'retryAt', isNotNull)),
    );
  });

  test('alert text is kept verbatim (plain text, not interpreted)', () async {
    final alerts = await api(MockScenario.someStale).getAlerts(rizalMemorialId);
    expect(alerts.alerts.single.message, contains('<b>'));
  });
}
