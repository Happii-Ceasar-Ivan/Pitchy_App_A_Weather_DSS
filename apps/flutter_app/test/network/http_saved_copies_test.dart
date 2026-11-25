import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitchy/core/errors/api_failure.dart';
import 'package:pitchy/core/network/http_pitchy_api.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/core/storage/saved_copies.dart';
import 'package:pitchy/shared/models/conversation.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';

/// The HTTP client saves each successful read for the DEC-13 saved copy, and
/// nothing else.
void main() {
  var now = DateTime.utc(2026, 11, 23, 4);
  final kickoff = DateTime.utc(2026, 11, 23, 7);
  const id = rizalMemorialId;

  late MemoryPreferences prefs;
  late SavedCopyStore store;

  setUp(() {
    prefs = MemoryPreferences();
    store = SavedCopyStore(prefs, clock: () => now);
  });

  http.Response json(Object body, int status) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );

  /// Answers every known read with its fixture.
  HttpPitchyApi online() => HttpPitchyApi(
    baseUrl: Uri.parse('https://api.example.test'),
    savedCopies: store,
    client: MockClient((r) async {
      final p = r.url.path;
      if (p.endsWith('/weather-status')) {
        return json(weatherStatusJson(MockScenario.allCurrent, now: now, kickoff: kickoff), 200);
      }
      if (p.endsWith('/weather')) {
        return json(consolidatedWeatherJson(now: now, kickoff: kickoff), 200);
      }
      if (p.endsWith('/alerts')) return json(alertsJson(now: now), 200);
      if (p.endsWith('/assessment')) return json(assessmentJson(now: now, kickoff: kickoff), 200);
      if (p.endsWith('/sessions')) return json(sessionJson(now: now), 201);
      if (p.endsWith('/conversation')) {
        return json(generalConversationJson(now: now, role: 'coach'), 200);
      }
      if (p.endsWith('/match-contexts/$id')) {
        return json(matchContextJson(kickoff: kickoff, created: now), 200);
      }
      return json(errorJson('NOT_FOUND', 'No.'), 404);
    }),
  );

  test('successful reads are saved with the time received', () async {
    final api = online();
    await api.getMatchContext(id);
    await api.getWeatherStatus(id);
    await api.getWeather(id);
    await api.getAlerts(id);
    await api.getAssessment(id);

    for (final kind in SavedKind.values) {
      final copy = store.get(id, kind);
      expect(copy, isNotNull, reason: kind.name);
      expect(copy!.savedAt, now);
    }
    expect(store.get(id, SavedKind.weatherStatus)!.body['match_context_id'], id);
  });

  test('a weather call for a custom window is not saved', () async {
    await online().getWeather(id, hours: 6);
    expect(store.get(id, SavedKind.weather), isNull);
  });

  test('chat and session replies are never saved', () async {
    final api = online();
    final session = await api.createSession();
    await api.askGeneralQuestion(
      const ConversationRequest(role: ConversationRole.coach, question: 'Is it hot?'),
      sessionToken: session.token,
    );
    expect(prefs.getString(SavedCopyStore.prefKey), isNull);
  });

  test('a failed read keeps the previous copy and saves nothing new', () async {
    await online().getAlerts(id);
    now = now.add(const Duration(minutes: 5));
    final offline = HttpPitchyApi(
      baseUrl: Uri.parse('https://api.example.test'),
      savedCopies: store,
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    await expectLater(offline.getAlerts(id), throwsA(isA<NetworkFailure>()));
    expect(store.get(id, SavedKind.alerts)!.savedAt, now.subtract(const Duration(minutes: 5)));
  });

  test('a reply that breaks the contract is not saved', () async {
    final bad = HttpPitchyApi(
      baseUrl: Uri.parse('https://api.example.test'),
      savedCopies: store,
      client: MockClient((_) async => json({'nope': true}, 200)),
    );
    await expectLater(bad.getAlerts(id), throwsA(isA<ContractFailure>()));
    expect(store.get(id, SavedKind.alerts), isNull);
  });

  test('a non-JSON 502 keeps its status code', () async {
    final down = HttpPitchyApi(
      baseUrl: Uri.parse('https://api.example.test'),
      client: MockClient((_) async => http.Response('<html>Bad gateway</html>', 502)),
    );
    await expectLater(
      down.getAlerts(id),
      throwsA(isA<ContractFailure>().having((f) => f.statusCode, 'statusCode', 502)),
    );
  });
}
