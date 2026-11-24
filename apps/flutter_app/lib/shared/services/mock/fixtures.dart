// Mock fixtures shaped exactly like the backend contract
// (backend/contract/openapi.v1.json). Values are SYNTHETIC demo data, not real
// measurements, classifications or guidance. Rule and guidance wording in the safety
// fixtures is copied from the backend rules file; only the numbers are made up. test/contract/fixtures_contract_test.dart
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

  /// A source failed; cooldown until next_ingestion_at. Update answers 429.
  unavailable,

  /// PAGASA ATMO stale, Ingest offered, and the update job fails.
  ingestFails,

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
  String ageGroup = 'senior',
}) => {
  'id': id,
  'kickoff_at': _t(kickoff),
  'venue': venueJson(venue),
  'pitch_surface': pitchSurface,
  'age_group': ageGroup,
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
          MockScenario.someStale || MockScenario.ingestFails when id == 'pagasa_atmo' => 'stale',
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
      s == MockScenario.someStale ||
      s == MockScenario.missing ||
      s == MockScenario.unavailable ||
      s == MockScenario.ingestFails;
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
    'active_job_ids': s == MockScenario.updating ? [pagasaJobId] : <String>[],
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
  'label': 'Official PAGASA information, shown as issued. Not a Pitchy classification.',
};

Json ingestionJobJson({
  required String id,
  required String state,
  required DateTime created,
  bool reused = false,
  List<String> sources = const ['pagasa_atmo', 'pagasa_ecmwf'],
}) => {
  'id': id,
  'state': state,
  'venue': 'rizal_memorial',
  'source_ids': sources,
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
    ingestionJobJson(id: pagasaJobId, state: 'queued', created: now),
    ingestionJobJson(
      id: openMeteoJobId,
      state: 'running',
      created: now.subtract(const Duration(seconds: 20)),
      reused: true,
      sources: const ['open_meteo'],
    ),
  ],
};

/// Demo job ids: the PAGASA group (ATMO + ECMWF) and the Open-Meteo group.
const pagasaJobId = 'c1d2e3f4-0000-4000-8000-000000000001';
const openMeteoJobId = 'c1d2e3f4-0000-4000-8000-000000000002';

/// Demo safety situations for the assessment and lightning endpoints. Independent of
/// [MockScenario] (weather data states). All values are SYNTHETIC.
enum SafetyScenario {
  /// Default. Senior match, heat available with WBGT about 29.9 °C (below the
  /// cooling-break level), lightning unavailable outside the live window, rainfall
  /// with no approved rule, approved rules, one official notice.
  heatBelow,

  /// Senior match, WBGT above 32 °C: cooling-break level, both FIFA measurement
  /// times, hourly values and the PFF rule notice.
  coolingBreaks,

  /// Under-20 match (age_group youth_u20): the 28 °C youth level set applies.
  youth,

  /// Heat inputs missing: no value, no classification, no level.
  heatMissing,

  /// Lightning detected 8.2 km away, current check: level and AFC procedure shown.
  lightningNear,

  /// Lightning check is stale and the latest attempt failed: no current detection.
  lightningStale,

  /// Like [heatBelow] but the rule set is still a draft (rules_approved false).
  rulesDraft,

  /// The assessment endpoint answers 501 NOT_IMPLEMENTED; lightning still works.
  notReady,
}

bool _liveScenario(SafetyScenario s) =>
    s == SafetyScenario.lightningNear || s == SafetyScenario.lightningStale;

/// Kickoff the demo uses for a safety scenario, on the hour. Lightning scenarios kick
/// off within the hour so "now" is inside the live window (from 120 minutes before
/// kickoff); all others kick off about three hours from now.
DateTime safetyKickoff(SafetyScenario s, DateTime now) {
  final t = now.toUtc().add(Duration(hours: _liveScenario(s) ? 1 : 3));
  return DateTime.utc(t.year, t.month, t.day, t.hour);
}

// Texts below are copied from backend/services/safety_engine/thresholds/rules.yaml
// (rule set 2026-11-23.3) and backend/api/routes/lightning.py, with line folds joined.

const _fifa = {
  'document_id': 'fifa_ecm_2022',
  'title': 'FIFA Emergency Care Manual',
  'authority': 'FIFA',
  'version': '2022 (PDF dated 2022-09-30; no edition number printed)',
  'section': 'Chapter 9 Environmental emergencies: Prevention of heat-related illness, FIFA cooling breaks',
};
const _afc = {
  'document_id': 'afc_com_2026',
  'title': 'AFC Competition Operations Manual',
  'authority': 'Asian Football Confederation (AFC)',
  'version': 'Edition 2026 (1 Dec update)',
  'section': 'Section 2 art. 8.3 (lightning); art. 20 Cooling Break; Appendix 20 Part A (extreme conditions)',
};
const _pff = {
  'document_id': 'pff_heat_advisory',
  'title': 'PFF Advisory Update: Enhanced Safety for Football Activities During Extreme Heat',
  'authority': 'Philippine Football Federation (PFF)',
  'version': 'undated on the page; read 2026-11-23',
  'section': 'introduction and item 1',
};

const _heatMethod = 'Liljegren et al. (2008), DEC-05';
const _heatDecidedBy =
    'match management team (FIFA); venue medical officer recommends, referee implements (AFC)';
const _measurementNote =
    'FIFA and AFC measure WBGT on site 90 and 60 minutes before kickoff (FIFA: with a '
    'calibrated device; either reading at the level counts). AFC art. 20.4 says "exceed 32 °C" '
    'while its Appendix 20 says "32 °C and above"; the inclusive reading (FIFA\'s) is used. '
    'Pitchy\'s WBGT is a forecast estimate: it is always labelled as an estimate and never '
    'replaces the on-site measurement.';
const _pffNoticeText =
    'PFF advises regional associations to avoid sanctioned matches from 9 AM to 3 PM during '
    'extreme heat, until further advised, and to decide with caution using the local heat '
    'index. Organizers need an on-site ambulance and trained responders with an AED. The '
    'advisory is undated: check that it is still in force.';
const _ruleVersion = 'rules 2026-11-23.3; engine b4.1; wbgt liljegren-wbgt-1.1-py1';

const _lightningBasis = 'Vaisala Xweather detection, past 5 minutes; AFC 30/30 procedure';
const _lightningDecidedBy = 'officials on site (AFC General Coordinator and/or Match Commissioner)';
const _lightningReason =
    'Pitchy measures detection from Vaisala Xweather (past 5 minutes, up to 40 km), not '
    'thunder on site. It shows the procedure as official guidance and flags the 10 km level; '
    'it never declares "stop play".';
const _lightningProcedure = [
  '30 seconds: if thunder follows a lightning flash within 30 seconds or less, send teams and match officials to the dressing rooms and spectators to safe shelters.',
  '30 minutes: restart no earlier than 30 minutes after the last thunder is heard.',
  'If conditions do not improve in a reasonable time, the AFC General Coordinator and/or Match Commissioner may postpone or abandon the match, after consulting the host, safety officer and referee.',
];
const _lightningAppliesNote =
    'AFC applies the 30/30 procedure when technology for detailed local forecasts is '
    'unavailable or unreliable. It is judged on site by the officials.';
const _lightningLevel = {
  'id': 'within_30_second_distance',
  'label': 'Lightning within about 10 km (AFC 30-second distance)',
  'action':
      'Under AFC\'s 30/30 procedure, players, officials and spectators take shelter; play '
      'restarts no earlier than 30 minutes after the last thunder. Officials on site decide.',
  'basis':
      'Team decision 2026-11-23: AFC\'s 30-second flash-to-thunder rule expressed as a '
      'distance. Sound travels about 343 m/s, so 30 s is about 10 km. This conversion is '
      'Pitchy\'s, not AFC\'s wording.',
};
const _lightningNote =
    'Live lightning detection near the stadium from the last few minutes, not a forecast. '
    'Officials on site decide whether to stop play; Pitchy does not.';

DateTime _ceilHour(DateTime t) {
  final u = t.toUtc();
  final floor = DateTime.utc(u.year, u.month, u.day, u.hour);
  return floor == u ? floor : floor.add(const Duration(hours: 1));
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Python `isoformat(timespec="minutes")` for a UTC time, as the backend writes it in messages.
String _isoMinutes(DateTime t) {
  final u = t.toUtc();
  return '${u.year}-${_two(u.month)}-${_two(u.day)}T${_two(u.hour)}:${_two(u.minute)}+00:00';
}

/// The PFF notice applies when the local (Asia/Manila, UTC+8) kickoff is 09:00 to 15:00.
bool _pffWindow(DateTime kickoff) {
  final local = kickoff.toUtc().add(const Duration(hours: 8));
  final minutes = local.hour * 60 + local.minute;
  return minutes >= 9 * 60 && minutes <= 15 * 60;
}

Json _heatLevel(bool youth, double wbgt) {
  final threshold = youth ? 28.0 : 32.0;
  final cooling = wbgt >= threshold;
  if (youth) {
    return cooling
        ? {
            'id': 'cooling_breaks_required',
            'label': 'At or above the youth cooling-break level (WBGT 28 °C)',
            'action': 'AFC: for under-20 and younger competitions, cooling breaks may be introduced from WBGT 28 °C (3 minutes, around the 30th and 75th minute, added as stoppage time), after consultation with the match officials; the referee implements them.',
            'source': _afc,
            'also_supported_by': <Json>[],
          }
        : {
            'id': 'below_cooling_break_level',
            'label': 'Below the youth cooling-break level',
            'action': 'No AFC youth cooling-break trigger. This is not a statement that conditions are safe.',
            'source': _afc,
            'also_supported_by': <Json>[],
          };
  }
  return cooling
      ? {
          'id': 'cooling_breaks_required',
          'label': 'At or above the cooling-break level (WBGT 32 °C)',
          'action': 'FIFA: cooling breaks must be used (after about 30 and 75 minutes of play), or the match may be postponed or cancelled depending on the WBGT level and the match management team\'s decision. AFC: the venue medical officer recommends cooling breaks (3 minutes, around the 30th and 75th minute, added as stoppage time); the referee implements them.',
          'source': _fifa,
          'also_supported_by': [_afc],
        }
      : {
          'id': 'below_cooling_break_level',
          'label': 'Below the cooling-break level',
          'action': 'No FIFA or AFC cooling-break trigger. This is not a statement that conditions are safe. FIFA asks officials to consult when WBGT is near 32 °C (no number given), and AFC also weighs time of day, cloud cover and stadium location.',
          'source': _fifa,
          'also_supported_by': [_afc],
        };
}

Json _point(DateTime at, double? wbgt, {bool used = false, List<String> missing = const []}) => {
  'at': _t(at),
  'forecast_stamp': _t(_ceilHour(at)),
  'value': wbgt,
  'used_for_level': used,
  'missing': missing,
};

Json _input(
  String parameter,
  double value,
  String unit,
  DateTime from,
  DateTime until,
  DateTime retrieved,
) => {
  'parameter': parameter,
  'value': value,
  'unit': unit,
  'provenance': {
    'source_id': 'open_meteo',
    'source_name': 'Open-Meteo',
    'retrieved_at': _t(retrieved),
    'source_issued_at': null,
    'forecast_valid_from': _t(from),
    'forecast_valid_until': _t(until),
    'expires_at': null,
  },
};

Json _heatIndicator(SafetyScenario s, DateTime now, DateTime kickoff, bool youth) {
  final missingInputs = s == SafetyScenario.heatMissing;
  final cooling = s == SafetyScenario.coolingBreaks;
  final wbgt = missingInputs
      ? null
      : cooling
      ? 32.64
      : s == SafetyScenario.youth
      ? 28.64
      : 29.87;
  final times = [
    kickoff.subtract(const Duration(minutes: 90)),
    kickoff.subtract(const Duration(minutes: 60)),
  ];
  final hourlyAt = [for (var i = 0; i < 3; i++) _ceilHour(kickoff).add(Duration(hours: i))];
  const missing = ['shortwave_radiation', 'surface_pressure'];
  final hourlyOffsets = cooling ? const [0.46, 0.76, 0.16] : const [0.03, 0.53, 0.23];
  final notices = (cooling || _pffWindow(kickoff))
      ? [
          {'id': 'pff_avoid_midday', 'text': _pffNoticeText, 'source': _pff},
        ]
      : <Json>[];
  final limitations = <Json>[
    {'code': 'FORECAST_ESTIMATE', 'message': _measurementNote},
  ];
  if (missingInputs) {
    for (final at in times) {
      limitations.add({
        'code': 'MISSING_INPUT',
        'message':
            'WBGT for ${_isoMinutes(at)} is unavailable: missing ${missing.join(', ')} in the forecast stamped ${_isoMinutes(_ceilHour(at))}.',
      });
    }
    return {
      'hazard': 'heat',
      'status': 'unavailable',
      'indicator_value': null,
      'indicator_unit': '°C',
      'classification': null,
      'level': null,
      'basis': _heatMethod,
      'decided_by': _heatDecidedBy,
      'points': [for (final at in times) _point(at, null, missing: missing)],
      'hourly': [for (final at in hourlyAt) _point(at, null, missing: missing)],
      'notices': notices,
      'procedure': <String>[],
      'inputs': <Json>[],
      'limitations': limitations,
      'guidance': <Json>[],
    };
  }
  limitations.add({
    'code': 'SCREENING_ASSUMPTION',
    'message': 'Urban/rural wind profile and night-time air stability are not in the forecast; both were computed and the higher WBGT is shown (difference up to 0.4 °C).',
  });
  final level = _heatLevel(youth, wbgt!);
  final stamp = _ceilHour(times.last);
  const hour = Duration(hours: 1);
  final retrieved = now.subtract(const Duration(minutes: 40));
  final setLabel = youth
      ? 'youth_u20 (under-20 and younger age-group competitions)'
      : 'senior (senior competitions (default))';
  return {
    'hazard': 'heat',
    'status': 'available',
    'indicator_value': wbgt,
    'indicator_unit': '°C',
    'classification': level['id'],
    'level': level,
    'basis': '$_heatMethod; level set $setLabel',
    'decided_by': _heatDecidedBy,
    // Both measurement times share one forecast stamp, so the values tie and the
    // backend marks the first one it meets as used for the level.
    'points': [
      _point(times[0], wbgt, used: true),
      _point(times[1], wbgt),
    ],
    'hourly': [
      for (var i = 0; i < hourlyAt.length; i++)
        _point(hourlyAt[i], double.parse((wbgt + hourlyOffsets[i]).toStringAsFixed(2))),
    ],
    'notices': notices,
    'procedure': <String>[],
    'inputs': [
      _input('temperature_2m', cooling ? 34.2 : 32.1, '°C', stamp, stamp.add(hour), retrieved),
      _input('relative_humidity_2m', cooling ? 68 : 64, '%', stamp, stamp.add(hour), retrieved),
      _input('wind_speed_10m', 2.4, 'm/s', stamp, stamp.add(hour), retrieved),
      _input('surface_pressure', 1008.0, 'hPa', stamp, stamp.add(hour), retrieved),
      _input('shortwave_radiation', 610, 'W/m²', stamp.subtract(hour), stamp, retrieved),
    ],
    'limitations': limitations,
    'guidance': <Json>[],
  };
}

Json _lightningIndicator(SafetyScenario s) {
  final base = <String, Object?>{
    'hazard': 'lightning',
    'indicator_unit': 'km',
    'basis': _lightningBasis,
    'decided_by': _lightningDecidedBy,
    'points': <Json>[],
    'hourly': <Json>[],
    'notices': <Json>[],
    'inputs': <Json>[],
  };
  const reason = {'code': 'DETECTION_NOT_FORECAST', 'message': _lightningReason};
  if (s == SafetyScenario.lightningNear) {
    return {
      ...base,
      'status': 'available',
      'indicator_value': 8.2,
      'classification': _lightningLevel['id'],
      'level': {
        'id': _lightningLevel['id'],
        'label': _lightningLevel['label'],
        'action': _lightningLevel['action'],
        'source': _afc,
        'also_supported_by': <Json>[],
      },
      'procedure': _lightningProcedure,
      'limitations': [
        reason,
        {'code': 'PITCHY_CONVERSION', 'message': _lightningLevel['basis']},
      ],
      'guidance': [_afc],
    };
  }
  final String code;
  final String message;
  if (s == SafetyScenario.lightningStale) {
    code = 'STALE_INPUT';
    message = 'No current lightning check: stale (HTTP_503).';
  } else {
    code = 'OUTSIDE_LIVE_WINDOW';
    message = 'Lightning is checked live only from shortly before kickoff to the end of the match.';
  }
  return {
    ...base,
    'status': 'unavailable',
    'indicator_value': null,
    'classification': null,
    'level': null,
    'procedure': <String>[],
    'limitations': [
      reason,
      {'code': code, 'message': message},
    ],
    'guidance': <Json>[],
  };
}

Json _rainfallIndicator() => {
  'hazard': 'rainfall',
  'status': 'unavailable',
  'indicator_value': null,
  'indicator_unit': 'mm/h',
  'classification': null,
  'level': null,
  'basis': null,
  'decided_by': null,
  'points': <Json>[],
  'hourly': <Json>[],
  'notices': <Json>[],
  'procedure': <String>[],
  'inputs': <Json>[],
  'limitations': [
    {
      'code': 'NO_APPROVED_RULE',
      'message': 'None of FIFA, AFC or PFF gives a rain rule (AFC only weighs rain for cold and ground conditions). Forecast rain amounts with source and time, and official PAGASA alerts.',
    },
  ],
  'guidance': <Json>[],
};

/// Safety assessment for [scenario] (contract `SafetyAssessment`). SYNTHETIC numbers;
/// wording is copied from the backend rules. [ageGroup] is the match's age group: the
/// [SafetyScenario.youth] scenario always uses `youth_u20`, other scenarios follow it.
/// The [SafetyScenario.notReady] scenario is answered with an error by the mock API;
/// here it returns the same body as [SafetyScenario.heatBelow].
Json assessmentJson({
  required DateTime now,
  required DateTime kickoff,
  SafetyScenario scenario = SafetyScenario.heatBelow,
  String ageGroup = 'senior',
  String matchContextId = rizalMemorialId,
  String venue = 'rizal_memorial',
}) {
  final youth = scenario == SafetyScenario.youth || ageGroup == 'youth_u20';
  final withNotice = scenario == SafetyScenario.heatBelow || scenario == SafetyScenario.rulesDraft;
  final draft = scenario == SafetyScenario.rulesDraft;
  final issued = now.subtract(const Duration(minutes: 30));
  final until = now.add(const Duration(hours: 2));
  return {
    'id': '9a8b7c6d-0000-4000-8000-0000000000a1',
    'match_context': matchContextJson(
      id: matchContextId,
      venue: venue,
      kickoff: kickoff,
      created: now.subtract(const Duration(hours: 1)),
      ageGroup: youth ? 'youth_u20' : 'senior',
    ),
    'assessed_at': _t(now),
    'checked_at': _t(now),
    'age_group': youth ? 'youth_u20' : 'senior',
    'rules_approved': !draft,
    'rule_version': _ruleVersion,
    'indicators': [
      _heatIndicator(scenario, now, kickoff, youth),
      _lightningIndicator(scenario),
      _rainfallIndicator(),
    ],
    'official_notices': [
      if (withNotice)
        {
          'kind': 'severe_weather_alert',
          'issuer': 'PAGASA',
          'title': 'SYNTHETIC: Heat advisory for Metro Manila',
          'issued_at': _t(issued),
          'valid_until': _t(until),
          'provenance': {
            'source_id': 'pagasa',
            'source_name': 'PAGASA alerts (panahon.gov.ph)',
            'retrieved_at': _t(now.subtract(const Duration(minutes: 20))),
            'source_issued_at': null,
            'forecast_valid_from': _t(issued),
            'forecast_valid_until': _t(until),
            'expires_at': null,
          },
        },
    ],
    'limitations': [
      {
        'code': 'OFFICIALS_DECIDE',
        'message': 'Pitchy shows what the approved rules say; the official decision stays with the match officials named in each rule.',
      },
      if (draft) {'code': 'RULES_NOT_APPROVED', 'message': 'The rule set is still a draft.'},
    ],
  };
}

/// Live lightning near the venue for [scenario] (contract `VenueLightning`). SYNTHETIC.
/// Use [safetyKickoff] as the kickoff so the lightning scenarios fall in the live window.
Json lightningJson({
  required DateTime now,
  required DateTime kickoff,
  SafetyScenario scenario = SafetyScenario.heatBelow,
  String venue = 'rizal_memorial',
}) {
  final start = kickoff.subtract(const Duration(minutes: 120));
  final end = kickoff.add(const Duration(hours: 2));
  final inWindow = !now.isBefore(start) && now.isBefore(end);
  Json flash(int minutesAgo, double km, double lat, double lon) => {
    'detected_at': _t(now.subtract(Duration(minutes: minutesAgo))),
    'distance_km': km,
    'latitude': lat,
    'longitude': lon,
  };
  final Json status;
  final int? count;
  final double? nearest;
  final DateTime? latest;
  var flashes = <Json>[];
  Json? level;
  Json? guidance;
  switch (scenario) {
    case SafetyScenario.lightningNear:
      status = {
        'state': 'current',
        'last_checked_at': _t(now.subtract(const Duration(minutes: 1))),
        'current_until': _t(now.add(const Duration(minutes: 4))),
        'last_error_code': null,
      };
      count = 3;
      nearest = 8.2;
      latest = now.subtract(const Duration(minutes: 1));
      flashes = [
        flash(1, 8.2, 14.6371, 120.9919),
        flash(3, 11.7, 14.5634, 121.1005),
        flash(4, 17.95, 14.4434, 120.8804),
      ];
      level = {
        for (final k in ['id', 'label', 'action', 'basis']) k: _lightningLevel[k],
      };
      guidance = {
        'source': 'AFC Competition Operations Manual, Edition 2026 (1 Dec update), Section 2 art. 8.3 (lightning)',
        'procedure': _lightningProcedure,
        'applies_note': _lightningAppliesNote,
        'shown_because': ['LIGHTNING_DETECTED'],
      };
    case SafetyScenario.lightningStale:
      status = {
        'state': 'stale',
        'last_checked_at': _t(now.subtract(const Duration(minutes: 9))),
        'current_until': _t(now.subtract(const Duration(minutes: 4))),
        'last_error_code': 'HTTP_503',
      };
      count = 1;
      nearest = 14.6;
      latest = now.subtract(const Duration(minutes: 10));
      flashes = [flash(10, 14.6, 14.6948, 121.0919)];
    case _:
      status = {
        'state': 'missing',
        'last_checked_at': null,
        'current_until': null,
        'last_error_code': null,
      };
      count = null;
      nearest = null;
      latest = null;
  }
  return {
    'venue': venue,
    'live_window': {'start': _t(start), 'end': _t(end)},
    'in_live_window': inWindow,
    'status': status,
    'radius_km': 40.0,
    'detection_minutes': 5,
    'flash_count': count,
    'nearest_km': nearest,
    'latest_flash_at': latest == null ? null : _t(latest),
    'flashes': flashes,
    'level': level,
    'guidance': guidance,
    'attribution': {
      'source_id': 'xweather_lightning',
      'text': 'Powered by Vaisala Xweather',
      'url': 'https://www.xweather.com/',
    },
    'note': _lightningNote,
  };
}

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
