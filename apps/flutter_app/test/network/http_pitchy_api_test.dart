import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitchy/core/errors/api_failure.dart';
import 'package:pitchy/core/network/http_pitchy_api.dart';
import 'package:pitchy/shared/models/conversation.dart';
import 'package:pitchy/shared/models/match.dart';
import 'package:pitchy/shared/models/weather.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';

void main() {
  final now = DateTime.utc(2026, 11, 23, 4);
  final kickoff = DateTime.utc(2026, 11, 23, 7);

  HttpPitchyApi api(MockClient client) =>
      HttpPitchyApi(baseUrl: Uri.parse('https://api.example.test'), client: client);

  http.Response json(Object body, int status) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );

  test('GET weather-status builds the right URL and parses the contract shape', () async {
    late http.Request seen;
    final client = MockClient((r) async {
      seen = r;
      return json(weatherStatusJson(MockScenario.someStale, now: now, kickoff: kickoff), 200);
    });
    final status = await api(client).getWeatherStatus(rizalMemorialId);
    expect(seen.method, 'GET');
    expect(
      seen.url.toString(),
      'https://api.example.test/api/v1/match-contexts/$rizalMemorialId/weather-status',
    );
    expect(status.ingestionNeeded, isTrue);
    expect(status.sources.map((s) => s.state), contains(WeatherDataState.stale));
    expect(status.checkedAt, now);
  });

  test('weather passes hours as a query parameter', () async {
    late Uri seen;
    final client = MockClient((r) async {
      seen = r.url;
      return json(consolidatedWeatherJson(now: now, kickoff: kickoff), 200);
    });
    final weather = await api(client).getWeather(rizalMemorialId, hours: 6);
    expect(seen.queryParameters, {'hours': '6'});
    expect(weather.attributions.single.text, 'Weather data by Open-Meteo.com');
  });

  test('POST match-contexts sends the venue scope key and UTC kickoff', () async {
    late Map<String, Object?> body;
    final client = MockClient((r) async {
      body = jsonDecode(r.body) as Map<String, Object?>;
      expect(r.headers['Content-Type'], startsWith('application/json'));
      return json(matchContextJson(kickoff: kickoff, created: now), 201);
    });
    final match = await api(
      client,
    ).createMatchContext(MatchContextCreate(kickoffAt: kickoff, venueScopeKey: 'rizal_memorial'));
    expect(body, {'kickoff_at': '2026-11-23T07:00:00.000Z', 'venue': 'rizal_memorial'});
    expect(match.venue.scopeKey, 'rizal_memorial');
  });

  test('429 maps to ApiError with retryAt', () async {
    final retry = now.add(const Duration(minutes: 15));
    final client = MockClient(
      (_) async => json(errorJson('RATE_LIMITED', 'Try again later.', retryAt: retry), 429),
    );
    await expectLater(
      api(client).requestIngestion(rizalMemorialId),
      throwsA(
        isA<ApiError>()
            .having((e) => e.statusCode, 'status', 429)
            .having((e) => e.code, 'code', ApiErrorCode.rateLimited)
            .having((e) => e.retryAt, 'retryAt', retry),
      ),
    );
  });

  test('409 INGESTION_NOT_NEEDED is reported, not treated as success', () async {
    final client = MockClient(
      (_) async => json(errorJson('INGESTION_NOT_NEEDED', 'Not needed.'), 409),
    );
    await expectLater(
      api(client).requestIngestion(rizalMemorialId),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', ApiErrorCode.ingestionNotNeeded)),
    );
  });

  test('501 from a not-yet-built endpoint maps to NOT_IMPLEMENTED', () async {
    final client = MockClient(
      (_) async => json(errorJson('NOT_IMPLEMENTED', 'Not implemented yet.'), 501),
    );
    await expectLater(
      api(client).getAssessment(rizalMemorialId),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', ApiErrorCode.notImplemented)),
    );
  });

  test('unknown error codes still parse', () async {
    final client = MockClient((_) async => json(errorJson('SOMETHING_NEW', 'New.'), 400));
    await expectLater(
      api(client).listVenues(),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', ApiErrorCode.unknown)),
    );
  });

  test('a contract mismatch is a ContractFailure, never partial data', () async {
    final bad = weatherStatusJson(MockScenario.allCurrent, now: now, kickoff: kickoff)
      ..['ingestion_needed'] = 'yes';
    final client = MockClient((_) async => json(bad, 200));
    await expectLater(
      api(client).getWeatherStatus(rizalMemorialId),
      throwsA(isA<ContractFailure>()),
    );
  });

  test('times without an offset are rejected', () async {
    final bad = weatherStatusJson(MockScenario.allCurrent, now: now, kickoff: kickoff)
      ..['checked_at'] = '2026-11-23T04:00:00';
    final client = MockClient((_) async => json(bad, 200));
    await expectLater(
      api(client).getWeatherStatus(rizalMemorialId),
      throwsA(isA<ContractFailure>()),
    );
  });

  test('connection errors map to NetworkFailure', () async {
    final client = MockClient((_) async => throw const SocketException('offline'));
    await expectLater(api(client).listVenues(), throwsA(isA<NetworkFailure>()));
  });

  test('slow responses map to TimeoutFailure', () async {
    final client = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return json(venuesJson(), 200);
    });
    final slow = HttpPitchyApi(
      baseUrl: Uri.parse('https://api.example.test'),
      client: client,
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(slow.listVenues(), throwsA(isA<TimeoutFailure>()));
  });

  test('conversation sends the session token header', () async {
    late http.Request seen;
    final client = MockClient((r) async {
      seen = r;
      return json(conversationJson(now: now, role: 'referee'), 200);
    });
    final response = await api(client).askQuestion(
      rizalMemorialId,
      const ConversationRequest(role: ConversationRole.referee, question: 'Is it safe?'),
      sessionToken: 'abc',
    );
    expect(seen.headers['X-Session-Token'], 'abc');
    expect(jsonDecode(seen.body), {'role': 'referee', 'question': 'Is it safe?'});
    expect(response.generation, Generation.generated);
  });
}
