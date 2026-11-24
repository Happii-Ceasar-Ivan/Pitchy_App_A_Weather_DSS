import '../../../core/errors/api_failure.dart';
import '../../../core/network/pitchy_api.dart';
import '../../models/alerts.dart';
import '../../models/assessment.dart';
import '../../models/conversation.dart';
import '../../models/ingestion.dart';
import '../../models/match.dart';
import '../../models/weather.dart';
import 'fixtures.dart';

/// [PitchyApi] backed by contract-shaped fixtures, so the UI can be built and
/// tested before or without the backend. Data is synthetic.
class MockPitchyApi implements PitchyApi {
  MockPitchyApi({
    this.scenario = MockScenario.allCurrent,
    DateTime Function()? clock,
    this.latency = const Duration(milliseconds: 350),
  }) : _clock = clock ?? DateTime.now;

  /// The state the mock backend is in. Change it to demo or test each UI state.
  MockScenario scenario;
  final DateTime Function() _clock;
  final Duration latency;

  DateTime get _now => _clock().toUtc();

  /// Kickoff for demo match contexts: three hours from now, on the hour.
  DateTime get _kickoff {
    final t = _now.add(const Duration(hours: 3));
    return DateTime.utc(t.year, t.month, t.day, t.hour);
  }

  final Map<String, int> _jobPolls = {};

  /// Matches created through this mock, so later reads return what was set up.
  final Map<String, MatchContext> _matches = {};

  DateTime _kickoffFor(String id) => _matches[id]?.kickoffAt ?? _kickoff;

  Future<T> _respond<T>(T Function() build) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    switch (scenario) {
      case MockScenario.offline:
        throw const NetworkFailure();
      case MockScenario.serviceError:
        throw ApiError.fromEnvelope(
          503,
          errorJson('SERVICE_UNAVAILABLE', 'The service is temporarily unavailable.'),
        );
      case _:
        return build();
    }
  }

  @override
  Future<List<Venue>> listVenues() => _respond(() => venueListFromJson(venuesJson()));

  @override
  Future<MatchContext> createMatchContext(MatchContextCreate request) => _respond(() {
    final match = MatchContext.fromJson(
      matchContextJson(
        id: request.venueScopeKey == 'new_clark_city' ? newClarkCityId : rizalMemorialId,
        venue: request.venueScopeKey,
        kickoff: request.kickoffAt,
        created: _now,
        pitchSurface: request.pitchSurface,
      ),
    );
    return _matches[match.id] = match;
  });

  @override
  Future<MatchContext> getMatchContext(String matchContextId) => _respond(
    () =>
        _matches[matchContextId] ??
        MatchContext.fromJson(
          matchContextJson(id: matchContextId, kickoff: _kickoff, created: _now),
        ),
  );

  @override
  Future<WeatherStatus> getWeatherStatus(String matchContextId) => _respond(
    () => WeatherStatus.fromJson(
      weatherStatusJson(
        scenario,
        now: _now,
        kickoff: _kickoffFor(matchContextId),
        id: matchContextId,
      ),
    ),
  );

  @override
  Future<ConsolidatedWeather> getWeather(String matchContextId, {int? hours}) => _respond(
    () => ConsolidatedWeather.fromJson(
      consolidatedWeatherJson(
        scenario: scenario,
        now: _now,
        kickoff: _kickoffFor(matchContextId),
        id: matchContextId,
      ),
    ),
  );

  @override
  Future<VenueAlerts> getAlerts(String matchContextId) => _respond(
    () =>
        VenueAlerts.fromJson(alertsJson(now: _now, withAlert: scenario == MockScenario.someStale)),
  );

  /// Update requests sent, for tests that check no duplicate is sent.
  int ingestionRequests = 0;

  /// What the mock backend does with an update request, by scenario:
  /// all current → 409; unavailable → 429 with retry_at; otherwise 202 with two
  /// group jobs (one reused) and the status turns Updating. Jobs then succeed
  /// (the status turns Current), or fail in [MockScenario.ingestFails] (the
  /// status then answers 429 for the cooldown).
  @override
  Future<IngestionRequestResult> requestIngestion(String matchContextId) => _respond(() {
    ingestionRequests++;
    if (scenario == MockScenario.unavailable) {
      throw ApiError.fromEnvelope(
        429,
        errorJson(
          'RATE_LIMITED',
          'Try again later.',
          retryAt: _now.add(const Duration(minutes: 15)),
        ),
      );
    }
    if (scenario == MockScenario.allCurrent) {
      throw ApiError.fromEnvelope(
        409,
        errorJson('INGESTION_NOT_NEEDED', 'Data is already current.'),
      );
    }
    _jobsFail = scenario == MockScenario.ingestFails;
    _jobPolls.clear();
    if (!_jobsFail) scenario = MockScenario.updating;
    return IngestionRequestResult.fromJson(ingestionRequestJson(now: _now, id: matchContextId));
  });

  bool _jobsFail = false;

  /// Jobs move queued -> running -> succeeded (or failed) over successive polls.
  @override
  Future<IngestionJob> getIngestionJob(String jobId) => _respond(() {
    final polls = _jobPolls.update(jobId, (n) => n + 1, ifAbsent: () => 0);
    final end = _jobsFail && jobId == pagasaJobId ? 'failed' : 'succeeded';
    final state = switch (polls) {
      0 => 'queued',
      1 => 'running',
      _ => end,
    };
    if (state == 'failed') scenario = MockScenario.unavailable;
    if (state == 'succeeded' && scenario == MockScenario.updating && polls >= 2) {
      scenario = MockScenario.allCurrent;
    }
    return IngestionJob.fromJson(
      ingestionJobJson(
        id: jobId,
        state: state,
        created: _now.subtract(Duration(seconds: polls * 5)),
        sources: jobId == openMeteoJobId
            ? const ['open_meteo']
            : const ['pagasa_atmo', 'pagasa_ecmwf'],
      ),
    );
  });

  @override
  Future<SafetyAssessment> getAssessment(String matchContextId) =>
      _respond(() => SafetyAssessment.fromJson(assessmentJson(now: _now, kickoff: _kickoff)));

  @override
  Future<SessionCreated> createSession() =>
      _respond(() => SessionCreated.fromJson(sessionJson(now: _now)));

  @override
  Future<ConversationResponse> askQuestion(
    String matchContextId,
    ConversationRequest request, {
    required String sessionToken,
  }) => _respond(
    () => ConversationResponse.fromJson(
      conversationJson(now: _now, role: request.role.wire, id: matchContextId),
    ),
  );
}
