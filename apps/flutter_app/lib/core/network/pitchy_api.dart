import '../../shared/models/alerts.dart';
import '../../shared/models/assessment.dart';
import '../../shared/models/conversation.dart';
import '../../shared/models/ingestion.dart';
import '../../shared/models/lightning.dart';
import '../../shared/models/match.dart';
import '../../shared/models/weather.dart';

/// The backend API (`/api/v1`) as the app uses it. Implemented by [HttpPitchyApi]
/// for the real backend and [MockPitchyApi] for fixtures.
///
/// Every method throws an [ApiFailure] on error. The backend is authoritative for
/// freshness, coverage, ingestion eligibility and classifications; callers display
/// what comes back and never recompute it.
abstract interface class PitchyApi {
  /// `GET /venues`
  Future<List<Venue>> listVenues();

  /// `POST /match-contexts`
  Future<MatchContext> createMatchContext(MatchContextCreate request);

  /// `GET /match-contexts/{id}`
  Future<MatchContext> getMatchContext(String matchContextId);

  /// `GET /match-contexts/{id}/weather-status`
  Future<WeatherStatus> getWeatherStatus(String matchContextId);

  /// `GET /match-contexts/{id}/weather?hours=` (hours 1 to 24 from kickoff; null = coverage window)
  Future<ConsolidatedWeather> getWeather(String matchContextId, {int? hours});

  /// `GET /match-contexts/{id}/alerts`
  Future<VenueAlerts> getAlerts(String matchContextId);

  /// `POST /match-contexts/{id}/ingestions`: 202, or [ApiError] 409 / 429 (with retryAt).
  Future<IngestionRequestResult> requestIngestion(String matchContextId);

  /// `GET /ingestions/{id}`
  Future<IngestionJob> getIngestionJob(String jobId);

  /// `GET /match-contexts/{id}/assessment` (live since B4). Saved by the backend only
  /// when the result changes, so polling it does not add rows.
  Future<SafetyAssessment> getAssessment(String matchContextId);

  /// `GET /match-contexts/{id}/lightning` (live since B4). The backend calls the
  /// detection source at most once per venue per interval, only in the live window.
  Future<VenueLightning> getLightning(String matchContextId);

  /// `POST /sessions` (live since B6).
  Future<SessionCreated> createSession();

  /// `POST /match-contexts/{id}/conversation` with the `X-Session-Token`
  /// header (live since B5).
  Future<ConversationResponse> askQuestion(
    String matchContextId,
    ConversationRequest request, {
    required String sessionToken,
  });

  /// `POST /conversation` with the `X-Session-Token` header (live since B6): a
  /// general question without a match. Shares the per-session limit with
  /// [askQuestion].
  Future<GeneralConversationResponse> askGeneralQuestion(
    ConversationRequest request, {
    required String sessionToken,
  });
}
