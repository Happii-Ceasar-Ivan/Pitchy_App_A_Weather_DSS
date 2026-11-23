// Mock fixtures shaped exactly like the backend contract
// (backend/contract/openapi.v1.json). Values are SYNTHETIC demo data, not real
// measurements, classifications or guidance. test/contract/fixtures_contract_test.dart
// checks every fixture against the contract so drift fails loudly.
//
// Fixtures are JSON maps (not model objects) so the mock path also exercises the
// same parsing as the real backend.

import '../../models/json.dart';

const rizalMemorialId = '3f0c2a6e-6b1d-4c2e-9f0a-1a2b3c4d5e61';
const newClarkCityId = '7b9e4d10-2c3a-4f5b-8e6d-0a1b2c3d4e72';

/// Demo scenarios the mock API can serve. Each maps to a state the UI must handle.
enum MockScenario {
  /// Every source current and covering the match.
  allCurrent,

  /// PAGASA ATMO stale, Ingest offered.
  someStale,

  /// Ingestion running for the venue.
  updating,

  /// No stored forecast covers the match yet.
  missing,

  /// A source failed; cooldown until next_ingestion_at.
  unavailable,

  /// Backend answers 503 SERVICE_UNAVAILABLE.
  serviceError,

  /// No connection to the backend.
  offline,
}

String _t(DateTime t) => t.toUtc().toIso8601String();

Json venuesJson() => {
  'venues': [
    {
      'scope_key': 'rizal_memorial',
      'name': 'Rizal Memorial Stadium, Manila',
      'latitude': 14.563405271502504,
      'longitude': 120.99193149681405,
    },
    {
      'scope_key': 'new_clark_city',
      'name': 'New Clark City Athletics Stadium, Capas, Tarlac',
      'latitude': 15.34571628739377,
      'longitude': 120.53364718440237,
    },
  ],
};

Json venueJson(String scopeKey) => (venuesJson()['venues']! as List<Object?>)
    .cast<Json>()
    .firstWhere((v) => v['scope_key'] == scopeKey);

Json matchContextJson({
  String id = rizalMemorialId,
  String venue = 'rizal_memorial',
  required DateTime kickoff,
  required DateTime created,
  String? pitchSurface = 'synthetic_turf',
}) => {
  'id': id,
  'kickoff_at': _t(kickoff),
  'venue': venueJson(venue),
  'pitch_surface': pitchSurface,
  'created_at': _t(created),
  'updated_at': _t(created),
};

Json _provenance(
  String id,
  String name,
  DateTime retrieved,
  DateTime from,
  DateTime until, {
  DateTime? issued,
}) => {
  'source_id': id,
  'source_name': name,
  'retrieved_at': _t(retrieved),
  'source_issued_at': issued == null ? null : _t(issued),
  'forecast_valid_from': _t(from),
  'forecast_valid_until': _t(until),
  'expires_at': null,
};

const _sources = [
  ('open_meteo', 'Open-Meteo'),
  ('pagasa_atmo', 'PAGASA ATMO (panahon.gov.ph)'),
  ('pagasa_ecmwf', 'PAGASA ECMWF (panahon.gov.ph)'),
];

List<Json> _sourceStatuses(MockScenario s, DateTime now, DateTime kickoff) {
  final windowEnd = kickoff.add(const Duration(hours: 3));
  return [
    for (final (id, name) in _sources)
      () {
        final state = switch (s) {
          MockScenario.someStale when id == 'pagasa_atmo' => 'stale',
          MockScenario.updating => 'updating',
          MockScenario.missing => 'missing',
          MockScenario.unavailable when id == 'pagasa_ecmwf' => 'unavailable',
          _ => 'current',
        };
        final hasData =
            state == 'current' || state == 'stale' || (state == 'updating' && id == 'open_meteo');
        // The stale fetch is older, so its forecast ends before the match window does.
        final validUntil = state == 'stale' ? kickoff.add(const Duration(hours: 1)) : windowEnd;
        final retrieved = state == 'stale'
            ? now.subtract(const Duration(hours: 9))
            : now.subtract(const Duration(minutes: 40));
        return <String, Object?>{
          'source_id': id,
          'source_name': name,
          'state': state,
          'covers_match_time': hasData && state != 'stale',
          'current_until': state == 'current' ? _t(now.add(const Duration(hours: 2))) : null,
          'provenance': hasData
              ? _provenance(
                  id,
                  name,
                  retrieved,
                  kickoff.subtract(const Duration(hours: 1)),
                  validUntil,
                  issued: id.startsWith('pagasa')
                      ? retrieved.subtract(const Duration(hours: 2))
                      : null,
                )
              : null,
          'limitations': [
            if (state == 'unavailable')
              {'code': 'SOURCE_FAILED', 'message': 'The last fetch from this source failed.'},
          ],
        };
      }(),
  ];
}

Json weatherStatusJson(
  MockScenario s, {
  required DateTime now,
  required DateTime kickoff,
  String id = rizalMemorialId,
}) {
  final needs =
      s == MockScenario.someStale || s == MockScenario.missing || s == MockScenario.unavailable;
  return {
    'match_context_id': id,
    'venue': 'rizal_memorial',
    'checked_at': _t(now),
    'coverage': {
      'start': _t(kickoff.subtract(const Duration(hours: 1))),
      'end': _t(kickoff.add(const Duration(hours: 3))),
    },
    'sources': _sourceStatuses(s, now, kickoff),
    'ingestion_needed': needs,
    'active_job_ids': s == MockScenario.updating
        ? ['c1d2e3f4-0000-4000-8000-000000000001']
        : <String>[],
    'next_ingestion_at': s == MockScenario.unavailable
        ? _t(now.add(const Duration(minutes: 15)))
        : null,
    'alerts': {
      'state': 'current',
      'last_checked_at': _t(now.subtract(const Duration(minutes: 20))),
      'current_until': _t(now.add(const Duration(minutes: 40))),
      'last_error_code': null,
    },
  };
}

/// Hourly slots for one quantity; values are synthetic.
/// Hourly slots for one quantity; values are synthetic. Each slot carries the
/// state of the source used, and a source with no usable data gives no value.
List<Json> _slots(
  DateTime start,
  List<double?> raw, {
  required Map<String, String> states,
  String source = 'open_meteo',
  List<(String, double)> others = const [],
}) {
  bool usable(String id) => states[id] == 'current' || states[id] == 'stale';
  final values = [for (final v in raw) usable(source) ? v : null];
  others = [
    for (final o in others)
      if (usable(o.$1)) o,
  ];
  return [
    for (var i = 0; i < values.length; i++)
      {
        'valid_from': _t(start.add(Duration(hours: i))),
        'valid_until': _t(start.add(Duration(hours: i + 1))),
        'value': values[i],
        'source_id': values[i] == null ? null : source,
        'state': values[i] == null ? null : states[source],
        'fallback_label': null,
        'notes': <String>[],
        'range': values[i] == null || others.isEmpty
            ? null
            : {
                'min': [values[i]!, ...others.map((o) => o.$2)].reduce((a, b) => a < b ? a : b),
                'max': [values[i]!, ...others.map((o) => o.$2)].reduce((a, b) => a > b ? a : b),
                'count': others.length + 1,
                'source_ids': [source, ...others.map((o) => o.$1)],
              },
        'by_source': [
          if (values[i] != null)
            {'source_id': source, 'value': values[i], 'state': states[source], 'note': null},
          for (final (sid, v) in others)
            {'source_id': sid, 'value': v, 'state': states[sid], 'note': null},
        ],
      },
  ];
}

Json consolidatedWeatherJson({
  MockScenario scenario = MockScenario.allCurrent,
  required DateTime now,
  required DateTime kickoff,
  String id = rizalMemorialId,
}) {
  final start = kickoff.subtract(const Duration(hours: 1));
  // Same source statuses (and provenance) as weather-status for this scenario.
  final sources = _sourceStatuses(scenario, now, kickoff);
  final states = {for (final src in sources) src['source_id']! as String: src['state']! as String};
  Json q(String key, String label, String unit, List<String> priority, List<Json> slots) => {
    'quantity': key,
    'label': label,
    'unit': unit,
    'priority': priority,
    'slots': slots,
  };
  return {
    'match_context_id': id,
    'venue': 'rizal_memorial',
    'checked_at': _t(now),
    'window': {'start': _t(start), 'end': _t(kickoff.add(const Duration(hours: 3)))},
    'sources': sources,
    'quantities': [
      q('air_temperature', 'Air temperature', '°C', [
        'open_meteo',
      ], _slots(states: states, start, [32.1, 32.4, 31.8, 30.9])),
      q(
        'heat_index',
        'Heat index (PAGASA)',
        '°C',
        ['pagasa_atmo', 'pagasa_ecmwf'],
        _slots(
          states: states,
          start,
          [39.0, 40.0, 38.0, 36.0],
          source: 'pagasa_atmo',
          others: [('pagasa_ecmwf', 41.0)],
        ),
      ),
      q('relative_humidity', 'Relative humidity', '%', [
        'open_meteo',
      ], _slots(states: states, start, [68, 66, 70, 74])),
      q('rain', 'Rain', 'mm/h', [
        'pagasa_atmo',
        'pagasa_ecmwf',
        'open_meteo',
      ], _slots(states: states, start, [0.0, 0.2, 1.4, null], source: 'pagasa_atmo')),
      q('rain_probability', 'Rain probability', '%', [
        'open_meteo',
      ], _slots(states: states, start, [20, 35, 55, 60])),
      q('wind_speed', 'Wind speed', 'm/s', [
        'open_meteo',
        'pagasa_atmo',
        'pagasa_ecmwf',
      ], _slots(states: states, start, [3.1, 3.4, 4.2, 5.0])),
    ],
    'attributions': [
      {
        'source_id': 'open_meteo',
        'text': 'Weather data by Open-Meteo.com',
        'url': 'https://open-meteo.com/',
      },
    ],
  };
}

Json alertsJson({required DateTime now, bool withAlert = false}) => {
  'venue': 'rizal_memorial',
  'status': {
    'state': 'current',
    'last_checked_at': _t(now.subtract(const Duration(minutes: 20))),
    'current_until': _t(now.add(const Duration(minutes: 40))),
    'last_error_code': null,
  },
  'active_tropical_cyclones': 0,
  'alerts': [
    if (withAlert)
      {
        'issuer': 'PAGASA',
        'event': 'thunderstorm',
        'subtype': 'advisory',
        'headline': 'SYNTHETIC: Thunderstorm advisory for Metro Manila',
        'message': 'SYNTHETIC demo text. <b>Never rendered as HTML.</b>',
        'issued_at': _t(now.subtract(const Duration(minutes: 30))),
        'valid_until': _t(now.add(const Duration(hours: 2))),
        'matched_areas': [
          {
            'name': 'Metro Manila',
            'code': '130000000',
            'level': 'province',
            'relation': 'contains venue',
          },
        ],
      },
  ],
};

Json ingestionJobJson({
  required String id,
  required String state,
  required DateTime created,
  bool reused = false,
}) => {
  'id': id,
  'state': state,
  'venue': 'rizal_memorial',
  'source_ids': ['pagasa_atmo', 'pagasa_ecmwf'],
  'created_at': _t(created),
  'started_at': state == 'queued' ? null : _t(created.add(const Duration(seconds: 2))),
  'finished_at': (state == 'succeeded' || state == 'failed' || state == 'expired')
      ? _t(created.add(const Duration(seconds: 30)))
      : null,
  'failures': [
    if (state == 'failed')
      {
        'source_id': 'pagasa_ecmwf',
        'code': 'SOURCE_UNAVAILABLE',
        'message': 'Source did not respond.',
      },
  ],
  'reused_existing_job': reused,
};

Json ingestionRequestJson({required DateTime now, String id = rizalMemorialId}) => {
  'match_context_id': id,
  'jobs': [
    ingestionJobJson(id: 'c1d2e3f4-0000-4000-8000-000000000001', state: 'queued', created: now),
  ],
};

/// PROVISIONAL (B4 not built). Placeholder classification labels are clearly synthetic;
/// real labels and thresholds come only from the backend's approved rules.
Json assessmentJson({required DateTime now, required DateTime kickoff}) => {
  'id': '9a8b7c6d-0000-4000-8000-0000000000a1',
  'match_context': matchContextJson(
    kickoff: kickoff,
    created: now.subtract(const Duration(hours: 1)),
  ),
  'assessed_at': _t(now),
  'rule_version': 'synthetic-0',
  'indicators': [
    {
      'hazard': 'heat',
      'status': 'limited',
      'indicator_value': null,
      'indicator_unit': null,
      'classification': null,
      'basis': 'SYNTHETIC: thresholds not yet approved (DEC-05).',
      'inputs': <Json>[],
      'limitations': [
        {'code': 'THRESHOLDS_PENDING', 'message': 'Heat thresholds are not approved yet.'},
      ],
      'guidance': <Json>[],
    },
    {
      'hazard': 'lightning',
      'status': 'unavailable',
      'indicator_value': null,
      'indicator_unit': null,
      'classification': null,
      'basis': null,
      'inputs': <Json>[],
      'limitations': [
        {'code': 'RULES_PENDING', 'message': 'Lightning rules are not decided yet (DEC-06).'},
      ],
      'guidance': <Json>[],
    },
  ],
  'official_notices': <Json>[],
  'limitations': <Json>[],
};

/// PROVISIONAL (B5/B6 not built).
Json sessionJson({required DateTime now}) => {'token': 'mock-session-token', 'created_at': _t(now)};

/// PROVISIONAL (B5 not built).
Json conversationJson({required DateTime now, required String role, String id = rizalMemorialId}) =>
    {
      'match_context_id': id,
      'assessment_id': null,
      'role': role,
      'generation': 'unavailable',
      'answer': null,
      'references': <Json>[],
      'limitations': [
        {'code': 'AI_UNAVAILABLE', 'message': 'The assistant is not available in mock mode.'},
      ],
      'responded_at': _t(now),
    };

Json errorJson(String code, String message, {DateTime? retryAt}) => {
  'error': {
    'code': code,
    'message': message,
    'request_id': 'mock-request',
    'retry_at': retryAt == null ? null : _t(retryAt),
    'details': <Json>[],
  },
};
