import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, HttpException, SocketException;

import 'package:http/http.dart' as http;

import '../../shared/models/alerts.dart';
import '../../shared/models/assessment.dart';
import '../../shared/models/conversation.dart';
import '../../shared/models/ingestion.dart';
import '../../shared/models/json.dart';
import '../../shared/models/match.dart';
import '../../shared/models/weather.dart';
import '../errors/api_failure.dart';
import 'pitchy_api.dart';

/// [PitchyApi] over HTTPS against the real backend.
///
/// Never logs URLs, headers or bodies (the session token must not leak).
class HttpPitchyApi implements PitchyApi {
  HttpPitchyApi({
    required Uri baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 40),
  }) : _base = baseUrl,
       _client = client ?? http.Client();

  final Uri _base;
  final http.Client _client;
  final Duration timeout;

  static const _prefix = '/api/v1';

  Uri _uri(List<String> segments, [Map<String, String>? query]) {
    final basePath = _base.path.endsWith('/')
        ? _base.path.substring(0, _base.path.length - 1)
        : _base.path;
    final path = ['$basePath$_prefix', ...segments.map(Uri.encodeComponent)].join('/');
    return _base.replace(path: path, queryParameters: query);
  }

  Future<Json> _send(
    String method,
    Uri uri, {
    Json? body,
    Map<String, String> headers = const {},
    required Set<int> ok,
  }) async {
    final request = http.Request(method, uri)
      ..headers.addAll({'Accept': 'application/json', ...headers});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const TimeoutFailure();
    } on SocketException {
      throw const NetworkFailure();
    } on HandshakeException {
      throw const NetworkFailure();
    } on HttpException {
      throw const NetworkFailure();
    } on http.ClientException {
      throw const NetworkFailure();
    }

    final Object? decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ContractFailure('Response from ${uri.path} is not JSON (${response.statusCode})');
    }

    if (ok.contains(response.statusCode)) {
      try {
        return asJson(decoded, 'response');
      } on FormatException catch (e) {
        throw ContractFailure(e.message);
      }
    }
    try {
      throw ApiError.fromEnvelope(response.statusCode, asJson(decoded, 'response'));
    } on FormatException {
      throw ContractFailure('Unexpected ${response.statusCode} without an error envelope');
    }
  }

  Future<T> _get<T>(Uri uri, T Function(Json) parse) async =>
      _parse(await _send('GET', uri, ok: {200}), parse);

  T _parse<T>(Json json, T Function(Json) parse) {
    try {
      return parse(json);
    } on FormatException catch (e) {
      throw ContractFailure(e.message);
    }
  }

  @override
  Future<List<Venue>> listVenues() => _get(_uri(['venues']), venueListFromJson);

  @override
  Future<MatchContext> createMatchContext(MatchContextCreate request) async => _parse(
    await _send('POST', _uri(['match-contexts']), body: request.toJson(), ok: {201}),
    MatchContext.fromJson,
  );

  @override
  Future<MatchContext> getMatchContext(String matchContextId) =>
      _get(_uri(['match-contexts', matchContextId]), MatchContext.fromJson);

  @override
  Future<WeatherStatus> getWeatherStatus(String matchContextId) =>
      _get(_uri(['match-contexts', matchContextId, 'weather-status']), WeatherStatus.fromJson);

  @override
  Future<ConsolidatedWeather> getWeather(String matchContextId, {int? hours}) => _get(
    _uri(['match-contexts', matchContextId, 'weather'], hours == null ? null : {'hours': '$hours'}),
    ConsolidatedWeather.fromJson,
  );

  @override
  Future<VenueAlerts> getAlerts(String matchContextId) =>
      _get(_uri(['match-contexts', matchContextId, 'alerts']), VenueAlerts.fromJson);

  @override
  Future<IngestionRequestResult> requestIngestion(String matchContextId) async => _parse(
    await _send('POST', _uri(['match-contexts', matchContextId, 'ingestions']), ok: {202}),
    IngestionRequestResult.fromJson,
  );

  @override
  Future<IngestionJob> getIngestionJob(String jobId) =>
      _get(_uri(['ingestions', jobId]), IngestionJob.fromJson);

  @override
  Future<SafetyAssessment> getAssessment(String matchContextId) =>
      _get(_uri(['match-contexts', matchContextId, 'assessment']), SafetyAssessment.fromJson);

  @override
  Future<SessionCreated> createSession() async =>
      _parse(await _send('POST', _uri(['sessions']), ok: {201}), SessionCreated.fromJson);

  @override
  Future<ConversationResponse> askQuestion(
    String matchContextId,
    ConversationRequest request, {
    required String sessionToken,
  }) async => _parse(
    await _send(
      'POST',
      _uri(['match-contexts', matchContextId, 'conversation']),
      body: request.toJson(),
      headers: {'X-Session-Token': sessionToken},
      ok: {200},
    ),
    ConversationResponse.fromJson,
  );
}
