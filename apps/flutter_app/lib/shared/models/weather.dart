// Weather status and consolidated weather (contract: backend/contract/openapi.v1.json,
// schemas WeatherStatus, SourceStatus, Provenance, AlertsStatus, ConsolidatedWeather).
// Confirmed: these endpoints are live since Backend Sprint B3.

import 'json.dart';

/// Per-source data state (P-05). The backend decides it; the app only displays it.
enum WeatherDataState {
  current('current'),
  stale('stale'),
  missing('missing'),
  updating('updating'),
  unavailable('unavailable');

  const WeatherDataState(this.wire);
  final String wire;

  static String wireOf(WeatherDataState s) => s.wire;
}

class Limitation {
  const Limitation({required this.code, required this.message});

  factory Limitation.fromJson(Json json) =>
      Limitation(code: readString(json, 'code'), message: readString(json, 'message'));

  final String code;
  final String message;
}

/// Where and when a value came from (FR-WTH-005). Fields are null when a source omits them.
class Provenance {
  const Provenance({
    required this.sourceId,
    required this.sourceName,
    required this.retrievedAt,
    required this.sourceIssuedAt,
    required this.forecastValidFrom,
    required this.forecastValidUntil,
    required this.expiresAt,
  });

  factory Provenance.fromJson(Json json) => Provenance(
    sourceId: readString(json, 'source_id'),
    sourceName: readString(json, 'source_name'),
    retrievedAt: readTimeOrNull(json, 'retrieved_at'),
    sourceIssuedAt: readTimeOrNull(json, 'source_issued_at'),
    forecastValidFrom: readTimeOrNull(json, 'forecast_valid_from'),
    forecastValidUntil: readTimeOrNull(json, 'forecast_valid_until'),
    expiresAt: readTimeOrNull(json, 'expires_at'),
  );

  final String sourceId;
  final String sourceName;
  final DateTime? retrievedAt;
  final DateTime? sourceIssuedAt;
  final DateTime? forecastValidFrom;
  final DateTime? forecastValidUntil;
  final DateTime? expiresAt;
}

/// Why a source needing data must wait before it is asked again (P-27 A4).
/// The backend decides; the app only words it.
enum WaitReason {
  /// PAGASA: 4 hours after the last successful request.
  minInterval('min_interval'),

  /// PAGASA answered 401/403/429 last time (signs of blocking): 4 hours.
  sourceRefused('source_refused'),

  /// 15 minutes after an ordinary failed request.
  failureCooldown('failure_cooldown'),

  /// A reason this app version doesn't know yet: worded generically.
  other('');

  const WaitReason(this.wire);
  final String wire;

  /// Null for null; an unknown value becomes [other] instead of failing the
  /// whole reply, since the wording is only a hint.
  static WaitReason? parse(Object? value) {
    if (value == null) return null;
    for (final r in values) {
      if (r != other && r.wire == value) return r;
    }
    return other;
  }
}

class SourceStatus {
  const SourceStatus({
    required this.sourceId,
    required this.sourceName,
    required this.state,
    required this.coversMatchTime,
    required this.currentUntil,
    required this.provenance,
    required this.limitations,
    this.nextRequestAt,
    this.waitReason,
  });

  factory SourceStatus.fromJson(Json json) => SourceStatus(
    sourceId: readString(json, 'source_id'),
    sourceName: readString(json, 'source_name'),
    state: readEnum(json, 'state', WeatherDataState.values, WeatherDataState.wireOf),
    coversMatchTime: readBool(json, 'covers_match_time'),
    currentUntil: readTimeOrNull(json, 'current_until'),
    provenance: json['provenance'] == null
        ? null
        : Provenance.fromJson(asJson(json['provenance'], 'provenance')),
    limitations: readList(json, 'limitations', Limitation.fromJson, optional: true),
    nextRequestAt: readTimeOrNull(json, 'next_request_at'),
    waitReason: WaitReason.parse(json['wait_reason']),
  );

  final String sourceId;
  final String sourceName;
  final WeatherDataState state;

  /// True when stored forecasts cover the whole coverage window without a gap.
  final bool coversMatchTime;
  final DateTime? currentUntil;
  final Provenance? provenance;
  final List<Limitation> limitations;

  /// Set only while this source needs data and a new request must wait (P-27
  /// A4). Null when current or requestable now, and on older backends.
  final DateTime? nextRequestAt;
  final WaitReason? waitReason;
}

class CoverageWindow {
  const CoverageWindow({required this.start, required this.end});

  factory CoverageWindow.fromJson(Json json) =>
      CoverageWindow(start: readTime(json, 'start'), end: readTime(json, 'end'));

  final DateTime start;
  final DateTime end;
}

class AlertsStatus {
  const AlertsStatus({
    required this.state,
    required this.lastCheckedAt,
    required this.currentUntil,
    required this.lastErrorCode,
  });

  factory AlertsStatus.fromJson(Json json) => AlertsStatus(
    state: readEnum(json, 'state', WeatherDataState.values, WeatherDataState.wireOf),
    lastCheckedAt: readTimeOrNull(json, 'last_checked_at'),
    currentUntil: readTimeOrNull(json, 'current_until'),
    lastErrorCode: readStringOrNull(json, 'last_error_code'),
  );

  final WeatherDataState state;
  final DateTime? lastCheckedAt;
  final DateTime? currentUntil;
  final String? lastErrorCode;
}

class WeatherStatus {
  const WeatherStatus({
    required this.matchContextId,
    required this.venue,
    required this.checkedAt,
    required this.coverage,
    required this.sources,
    required this.ingestionNeeded,
    required this.activeJobIds,
    required this.nextIngestionAt,
    required this.alerts,
  });

  factory WeatherStatus.fromJson(Json json) => WeatherStatus(
    matchContextId: readString(json, 'match_context_id'),
    venue: readString(json, 'venue'),
    checkedAt: readTime(json, 'checked_at'),
    coverage: CoverageWindow.fromJson(asJson(json['coverage'], 'coverage')),
    sources: readList(json, 'sources', SourceStatus.fromJson),
    ingestionNeeded: readBool(json, 'ingestion_needed'),
    activeJobIds: readStringList(json, 'active_job_ids'),
    nextIngestionAt: readTimeOrNull(json, 'next_ingestion_at'),
    alerts: AlertsStatus.fromJson(asJson(json['alerts'], 'alerts')),
  );

  final String matchContextId;
  final String venue;
  final DateTime checkedAt;
  final CoverageWindow coverage;
  final List<SourceStatus> sources;

  /// The app shows Ingest only when this is true (DEC-04). Never derived client-side.
  final bool ingestionNeeded;

  /// Jobs running for this venue now; poll `GET /ingestions/{id}`.
  final List<String> activeJobIds;

  /// Set when a source must wait (PAGASA 4-hour gap, or cooldown after a failure).
  final DateTime? nextIngestionAt;
  final AlertsStatus alerts;
}

class ValueRange {
  const ValueRange({
    required this.min,
    required this.max,
    required this.count,
    required this.sourceIds,
  });

  factory ValueRange.fromJson(Json json) => ValueRange(
    min: readDouble(json, 'min'),
    max: readDouble(json, 'max'),
    count: readInt(json, 'count'),
    sourceIds: readStringList(json, 'source_ids'),
  );

  final double min;
  final double max;
  final int count;
  final List<String> sourceIds;
}

class SourceValue {
  const SourceValue({
    required this.sourceId,
    required this.value,
    required this.state,
    required this.note,
  });

  factory SourceValue.fromJson(Json json) => SourceValue(
    sourceId: readString(json, 'source_id'),
    value: readDouble(json, 'value'),
    state: readEnum(json, 'state', WeatherDataState.values, WeatherDataState.wireOf),
    note: readStringOrNull(json, 'note'),
  );

  final String sourceId;
  final double value;
  final WeatherDataState state;
  final String? note;
}

class ConsolidatedSlot {
  const ConsolidatedSlot({
    required this.validFrom,
    required this.validUntil,
    required this.value,
    required this.sourceId,
    required this.state,
    required this.fallbackLabel,
    required this.notes,
    required this.range,
    required this.bySource,
  });

  factory ConsolidatedSlot.fromJson(Json json) => ConsolidatedSlot(
    validFrom: readTime(json, 'valid_from'),
    validUntil: readTime(json, 'valid_until'),
    value: readDoubleOrNull(json, 'value'),
    sourceId: readStringOrNull(json, 'source_id'),
    state: readEnumOrNull(json, 'state', WeatherDataState.values, WeatherDataState.wireOf),
    fallbackLabel: readStringOrNull(json, 'fallback_label'),
    notes: readStringList(json, 'notes', optional: true),
    range: json['range'] == null ? null : ValueRange.fromJson(asJson(json['range'], 'range')),
    bySource: readList(json, 'by_source', SourceValue.fromJson),
  );

  final DateTime validFrom;
  final DateTime validUntil;

  /// Null when no source has a usable value for this slot.
  final double? value;
  final String? sourceId;
  final WeatherDataState? state;

  /// Set when a lower-priority source was used (P-09), e.g. "PAGASA ECMWF used; PAGASA ATMO stale".
  final String? fallbackLabel;
  final List<String> notes;

  /// Spread across sources (uncertainty). Never averaged.
  final ValueRange? range;
  final List<SourceValue> bySource;
}

class ConsolidatedQuantity {
  const ConsolidatedQuantity({
    required this.quantity,
    required this.label,
    required this.unit,
    required this.priority,
    required this.slots,
  });

  factory ConsolidatedQuantity.fromJson(Json json) => ConsolidatedQuantity(
    quantity: readString(json, 'quantity'),
    label: readString(json, 'label'),
    unit: readString(json, 'unit'),
    priority: readStringList(json, 'priority'),
    slots: readList(json, 'slots', ConsolidatedSlot.fromJson),
  );

  final String quantity;
  final String label;
  final String unit;
  final List<String> priority;
  final List<ConsolidatedSlot> slots;
}

class Attribution {
  const Attribution({required this.sourceId, required this.text, required this.url});

  factory Attribution.fromJson(Json json) => Attribution(
    sourceId: readString(json, 'source_id'),
    text: readString(json, 'text'),
    url: readString(json, 'url'),
  );

  final String sourceId;
  final String text;
  final String url;
}

class ConsolidatedWeather {
  const ConsolidatedWeather({
    required this.matchContextId,
    required this.venue,
    required this.checkedAt,
    required this.window,
    required this.sources,
    required this.quantities,
    required this.attributions,
    this.kickoffAt,
    this.coverage,
  });

  factory ConsolidatedWeather.fromJson(Json json) => ConsolidatedWeather(
    matchContextId: readString(json, 'match_context_id'),
    venue: readString(json, 'venue'),
    checkedAt: readTime(json, 'checked_at'),
    window: CoverageWindow.fromJson(asJson(json['window'], 'window')),
    sources: readList(json, 'sources', SourceStatus.fromJson),
    quantities: readList(json, 'quantities', ConsolidatedQuantity.fromJson),
    attributions: readList(json, 'attributions', Attribution.fromJson),
    kickoffAt: readTimeOrNull(json, 'kickoff_at'),
    coverage: json['coverage'] == null
        ? null
        : CoverageWindow.fromJson(asJson(json['coverage'], 'coverage')),
  );

  final String matchContextId;
  final String venue;
  final DateTime checkedAt;
  final CoverageWindow window;
  final List<SourceStatus> sources;
  final List<ConsolidatedQuantity> quantities;
  final List<Attribution> attributions;

  /// Exact kickoff (UTC) and the DEC-04 coverage window (kickoff to +2 h),
  /// sent since P-27. Null on older backends, which also can't serve hours
  /// before kickoff.
  final DateTime? kickoffAt;
  final CoverageWindow? coverage;
}
