// Checks every mock fixture against the backend contract
// (backend/contract/openapi.v1.json): required fields present, no unknown fields
// (the contract forbids extras), and the right JSON types and enum values.
// If the backend changes the contract, this test fails and the frontend models
// must be reviewed (coordination rule, frontend session prompt section 11).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitchy/shared/models/json.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';

late Json _schemas;

void main() {
  setUpAll(() {
    final file = File('../../backend/contract/openapi.v1.json');
    final spec = jsonDecode(file.readAsStringSync()) as Json;
    _schemas = asJson(asJson(spec['components'], 'components')['schemas'], 'schemas');
  });

  final now = DateTime.utc(2026, 11, 23, 4);
  final kickoff = DateTime.utc(2026, 11, 23, 7);

  final cases = <String, Json Function()>{
    'VenueList': venuesJson,
    'MatchContext': () => matchContextJson(kickoff: kickoff, created: now),
    for (final s in MockScenario.values)
      'WeatherStatus#${s.name}': () => weatherStatusJson(s, now: now, kickoff: kickoff),
    'ConsolidatedWeather': () => consolidatedWeatherJson(now: now, kickoff: kickoff),
    'VenueAlerts': () => alertsJson(now: now, withAlert: true),
    'IngestionRequestResult': () => ingestionRequestJson(now: now),
    for (final st in ['queued', 'running', 'succeeded', 'failed'])
      'IngestionJob#$st': () =>
          ingestionJobJson(id: 'c1d2e3f4-0000-4000-8000-000000000001', state: st, created: now),
    for (final s in SafetyScenario.values)
      if (s != SafetyScenario.notReady)
        'SafetyAssessment#${s.name}': () =>
            assessmentJson(now: now, kickoff: safetyKickoff(s, now), scenario: s),
    for (final s in SafetyScenario.values)
      'VenueLightning#${s.name}': () =>
          lightningJson(now: now, kickoff: safetyKickoff(s, now), scenario: s),
    'SessionCreated': () => sessionJson(now: now),
    'ConversationResponse': () => conversationJson(now: now, role: 'coach'),
    'ErrorEnvelope': () => errorJson('RATE_LIMITED', 'Try later.', retryAt: now),
  };

  for (final entry in cases.entries) {
    test('fixture ${entry.key} matches the contract', () {
      final schema = entry.key.split('#').first;
      final problems = <String>[];
      _check(entry.value(), {r'$ref': '#/components/schemas/$schema'}, schema, problems);
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}

void _check(Object? value, Json schema, String path, List<String> problems) {
  final ref = schema[r'$ref'];
  if (ref is String) {
    _check(value, asJson(_schemas[ref.split('/').last], ref), path, problems);
    return;
  }
  final anyOf = schema['anyOf'];
  if (anyOf is List) {
    for (final option in anyOf) {
      final sub = <String>[];
      _check(value, asJson(option, path), path, sub);
      if (sub.isEmpty) return;
    }
    problems.add('$path: matches no allowed shape (${jsonEncode(value)})');
    return;
  }
  final enumValues = schema['enum'];
  if (enumValues is List && !enumValues.contains(value)) {
    problems.add('$path: "$value" is not one of $enumValues');
    return;
  }
  switch (schema['type']) {
    case 'object':
      if (value is! Map) return problems.add('$path: expected object');
      final props = asJson(schema['properties'] ?? <String, Object?>{}, path);
      final required = (schema['required'] as List<Object?>? ?? const []).cast<String>();
      for (final key in required) {
        if (!value.containsKey(key)) problems.add('$path.$key: required field missing');
      }
      for (final key in value.keys.cast<String>()) {
        if (!props.containsKey(key)) {
          if (schema['additionalProperties'] == false) {
            problems.add('$path.$key: not in the contract');
          }
          continue;
        }
        _check(value[key], asJson(props[key], key), '$path.$key', problems);
      }
    case 'array':
      if (value is! List) return problems.add('$path: expected array');
      for (var i = 0; i < value.length; i++) {
        _check(value[i], asJson(schema['items'], path), '$path[$i]', problems);
      }
    case 'string':
      if (value is! String) return problems.add('$path: expected string');
      if (schema['format'] == 'date-time' && DateTime.tryParse(value) == null) {
        problems.add('$path: not a date-time');
      }
      final pattern = schema['pattern'];
      if (pattern is String && !RegExp(pattern).hasMatch(value)) {
        problems.add('$path: does not match $pattern');
      }
    case 'integer':
      if (value is! int) problems.add('$path: expected integer');
    case 'number':
      if (value is! num) problems.add('$path: expected number');
    case 'boolean':
      if (value is! bool) problems.add('$path: expected boolean');
    case 'null':
      if (value != null) problems.add('$path: expected null');
  }
}
