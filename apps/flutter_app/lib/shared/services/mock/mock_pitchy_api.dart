import '../../../core/errors/api_failure.dart';
import '../../../core/network/pitchy_api.dart';
import '../../../core/storage/saved_copies.dart';
import '../../models/alerts.dart';
import '../../models/assessment.dart';
import '../../models/conversation.dart';
import '../../models/ingestion.dart';
import '../../models/json.dart';
import '../../models/lightning.dart';
import '../../models/match.dart';
import '../../models/weather.dart';
import 'fixtures.dart';

/// [PitchyApi] backed by contract-shaped fixtures, so the UI can be built and
/// tested before or without the backend. Data is synthetic.
class MockPitchyApi implements PitchyApi {
  MockPitchyApi({
    this.scenario = MockScenario.allCurrent,
    this.safety = SafetyScenario.heatBelow,
    DateTime Function()? clock,
    this.chat = ChatScenario.answered,
    this.latency = const Duration(milliseconds: 350),
    this.savedCopies,
  }) : _clock = clock ?? DateTime.now;

  /// Where successful reads are saved (DEC-13), like the real client does, so
  /// the offline scenario can show a saved copy in demos.
  final SavedCopyStore? savedCopies;

  /// Parses [json] and saves it as the copy of [kind] for [matchId].
  T _keep<T>(String matchId, SavedKind kind, Json json, T Function(Json) parse) {
    final value = parse(json);
    savedCopies?.put(matchId, kind, json);
    return value;
  }

  /// The state the mock backend is in. Change it to demo or test each UI state.
  MockScenario scenario;

  /// The safety situation served by the assessment and lightning endpoints.
  final SafetyScenario safety;

  /// What Ask Pitchy does with a question (F4).
  ChatScenario chat;

  /// Sessions created and questions received, for tests.
  int sessionsCreated = 0;
  final List<String> tokensSeen = [];
  final DateTime Function() _clock;
  final Duration latency;

  DateTime get _now => _clock().toUtc();

  /// Kickoff for demo match contexts, on the hour: three hours from now (within the
  /// hour for the live lightning safety scenarios).
  DateTime get _kickoff => safetyKickoff(safety, _now);

  final Map<String, int> _jobPolls = {};

  /// Matches created through this mock, so later reads return what was set up.
  final Map<String, MatchContext> _matches = {};
  final Map<String, Json> _matchJson = {};

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
    final json = matchContextJson(
      id: request.venueScopeKey == 'new_clark_city' ? newClarkCityId : rizalMemorialId,
      venue: request.venueScopeKey,
      kickoff: request.kickoffAt,
      created: _now,
      pitchSurface: request.pitchSurface,
      ageGroup: request.ageGroup?.wire ?? 'senior',
    );
    final match = MatchContext.fromJson(json);
    _matchJson[match.id] = json;
    return _matches[match.id] = match;
  });

  @override
  Future<MatchContext> getMatchContext(String matchContextId) => _respond(
    () => _keep(
      matchContextId,
      SavedKind.match,
      _matchJson[matchContextId] ??
          matchContextJson(id: matchContextId, kickoff: _kickoff, created: _now),
      MatchContext.fromJson,
    ),
  );

  @override
  Future<WeatherStatus> getWeatherStatus(String matchContextId) => _respond(
    () => _keep(
      matchContextId,
      SavedKind.weatherStatus,
      weatherStatusJson(
        scenario,
        now: _now,
        kickoff: _kickoffFor(matchContextId),
        id: matchContextId,
      ),
      WeatherStatus.fromJson,
    ),
  );

  @override
  Future<ConsolidatedWeather> getWeather(String matchContextId, {int? hours}) => _respond(() {
    final json = consolidatedWeatherJson(
      scenario: scenario,
      now: _now,
      kickoff: _kickoffFor(matchContextId),
      id: matchContextId,
    );
    return hours == null
        ? _keep(matchContextId, SavedKind.weather, json, ConsolidatedWeather.fromJson)
        : ConsolidatedWeather.fromJson(json);
  });

  @override
  Future<VenueAlerts> getAlerts(String matchContextId) => _respond(
    () => _keep(
      matchContextId,
      SavedKind.alerts,
      alertsJson(now: _now, withAlert: scenario == MockScenario.someStale),
      VenueAlerts.fromJson,
    ),
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
  Future<SafetyAssessment> getAssessment(String matchContextId) => _respond(() {
    if (safety == SafetyScenario.notReady) {
      throw ApiError.fromEnvelope(
        501,
        errorJson('NOT_IMPLEMENTED', 'This endpoint is part of the contract draft.'),
      );
    }
    final match = _matches[matchContextId];
    return _keep(
      matchContextId,
      SavedKind.assessment,
      assessmentJson(
        now: _now,
        kickoff: _kickoffFor(matchContextId),
        scenario: safety,
        ageGroup: match?.ageGroup.wire ?? 'senior',
        matchContextId: matchContextId,
        venue: match?.venue.scopeKey ?? 'rizal_memorial',
      ),
      SafetyAssessment.fromJson,
    );
  });

  @override
  Future<VenueLightning> getLightning(String matchContextId) => _respond(
    () => VenueLightning.fromJson(
      lightningJson(
        now: _now,
        kickoff: _kickoffFor(matchContextId),
        scenario: safety,
        venue: _matches[matchContextId]?.venue.scopeKey ?? 'rizal_memorial',
      ),
    ),
  );

  @override
  Future<SessionCreated> createSession() => _respond(() {
    sessionsCreated++;
    return SessionCreated.fromJson({
      ...sessionJson(now: _now),
      'token': 'mock-session-token-$sessionsCreated',
    });
  });

  @override
  Future<ConversationResponse> askQuestion(
    String matchContextId,
    ConversationRequest request, {
    required String sessionToken,
  }) => _respond(() {
    _checkChatLimits(sessionToken, withMatch: true);
    return ConversationResponse.fromJson(
      conversationJson(now: _now, role: request.role.wire, id: matchContextId, scenario: chat),
    );
  });

  @override
  Future<GeneralConversationResponse> askGeneralQuestion(
    ConversationRequest request, {
    required String sessionToken,
  }) => _respond(() {
    _checkChatLimits(sessionToken, withMatch: false);
    return GeneralConversationResponse.fromJson(
      generalConversationJson(now: _now, role: request.role.wire, scenario: chat),
    );
  });

  /// The errors both chat routes share (session, rate limit); 404 only with a match.
  void _checkChatLimits(String sessionToken, {required bool withMatch}) {
    tokensSeen.add(sessionToken);
    switch (chat) {
      case ChatScenario.rateLimited:
        throw ApiError.fromEnvelope(
          429,
          errorJson(
            'RATE_LIMITED',
            'Temporary usage limit reached. Try again after retry_at.',
            retryAt: _now.add(const Duration(minutes: 20)),
          ),
        );
      case ChatScenario.sessionAlwaysInvalid:
        throw ApiError.fromEnvelope(401, errorJson('INVALID_SESSION', 'Session is not valid.'));
      case ChatScenario.sessionExpiredOnce when tokensSeen.length == 1:
        throw ApiError.fromEnvelope(401, errorJson('INVALID_SESSION', 'Session is not valid.'));
      case ChatScenario.matchGone when withMatch:
        throw ApiError.fromEnvelope(404, errorJson('NOT_FOUND', 'Not found.'));
      case _:
        return;
    }
  }
}
