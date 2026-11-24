// Live lightning near the venue (contract schemas VenueLightning, LightningStatus,
// FlashOut, LightningLevel, OfficialGuidance). Live since Backend Sprint B4
// (`GET /match-contexts/{id}/lightning`).
//
// This is detection from the last few minutes, not a forecast. The backend decides
// the state, the level and whether guidance is shown; the app only displays them.

import 'json.dart';
import 'weather.dart';

class LightningStatus {
  const LightningStatus({
    required this.state,
    required this.lastCheckedAt,
    required this.currentUntil,
    required this.lastErrorCode,
  });

  factory LightningStatus.fromJson(Json json) => LightningStatus(
    state: readEnum(json, 'state', WeatherDataState.values, WeatherDataState.wireOf),
    lastCheckedAt: readTimeOrNull(json, 'last_checked_at'),
    currentUntil: readTimeOrNull(json, 'current_until'),
    lastErrorCode: readStringOrNull(json, 'last_error_code'),
  );

  /// Current while the last check is under 5 minutes old; stale after that.
  final WeatherDataState state;

  /// Last successful check.
  final DateTime? lastCheckedAt;
  final DateTime? currentUntil;

  /// Set when the latest attempt failed.
  final String? lastErrorCode;
}

class Flash {
  const Flash({
    required this.detectedAt,
    required this.distanceKm,
    required this.latitude,
    required this.longitude,
  });

  factory Flash.fromJson(Json json) => Flash(
    detectedAt: readTime(json, 'detected_at'),
    distanceKm: readDouble(json, 'distance_km'),
    latitude: readDouble(json, 'latitude'),
    longitude: readDouble(json, 'longitude'),
  );

  final DateTime detectedAt;

  /// Distance from the venue, computed by the backend.
  final double distanceKm;
  final double latitude;
  final double longitude;
}

class LightningLevel {
  const LightningLevel({
    required this.id,
    required this.label,
    required this.action,
    required this.basis,
  });

  factory LightningLevel.fromJson(Json json) => LightningLevel(
    id: readString(json, 'id'),
    label: readString(json, 'label'),
    action: readString(json, 'action'),
    basis: readString(json, 'basis'),
  );

  final String id;
  final String label;
  final String action;
  final String basis;
}

/// The official on-site procedure, shown verbatim when the backend says why.
class OfficialGuidance {
  const OfficialGuidance({
    required this.source,
    required this.procedure,
    required this.appliesNote,
    required this.shownBecause,
  });

  factory OfficialGuidance.fromJson(Json json) => OfficialGuidance(
    source: readString(json, 'source'),
    procedure: readStringList(json, 'procedure'),
    appliesNote: readString(json, 'applies_note'),
    shownBecause: readStringList(json, 'shown_because'),
  );

  final String source;
  final List<String> procedure;
  final String appliesNote;

  /// Reason codes, e.g. LIGHTNING_DETECTED, PAGASA_THUNDERSTORM_ALERT.
  final List<String> shownBecause;
}

class VenueLightning {
  const VenueLightning({
    required this.venue,
    required this.liveWindow,
    required this.inLiveWindow,
    required this.status,
    required this.radiusKm,
    required this.detectionMinutes,
    required this.flashCount,
    required this.nearestKm,
    required this.latestFlashAt,
    required this.flashes,
    required this.level,
    required this.guidance,
    required this.attribution,
    required this.note,
  });

  factory VenueLightning.fromJson(Json json) => VenueLightning(
    venue: readString(json, 'venue'),
    liveWindow: CoverageWindow.fromJson(asJson(json['live_window'], 'live_window')),
    inLiveWindow: readBool(json, 'in_live_window'),
    status: LightningStatus.fromJson(asJson(json['status'], 'status')),
    radiusKm: readDouble(json, 'radius_km'),
    detectionMinutes: readInt(json, 'detection_minutes'),
    flashCount: readIntOrNull(json, 'flash_count'),
    nearestKm: readDoubleOrNull(json, 'nearest_km'),
    latestFlashAt: readTimeOrNull(json, 'latest_flash_at'),
    flashes: readList(json, 'flashes', Flash.fromJson),
    level: json['level'] == null ? null : LightningLevel.fromJson(asJson(json['level'], 'level')),
    guidance: json['guidance'] == null
        ? null
        : OfficialGuidance.fromJson(asJson(json['guidance'], 'guidance')),
    attribution: Attribution.fromJson(asJson(json['attribution'], 'attribution')),
    note: readString(json, 'note'),
  );

  final String venue;

  /// Live checks happen only in this window (before kickoff to match end).
  final CoverageWindow liveWindow;
  final bool inLiveWindow;
  final LightningStatus status;
  final double radiusKm;
  final int detectionMinutes;

  /// Flashes in the last successful check; null if there has been none yet.
  final int? flashCount;
  final double? nearestKm;
  final DateTime? latestFlashAt;

  /// Nearest first, from the last successful check.
  final List<Flash> flashes;

  /// Set only when a current check found lightning inside an approved distance.
  final LightningLevel? level;
  final OfficialGuidance? guidance;
  final Attribution attribution;

  /// Plain-language reminder of what the data is and is not. Always shown.
  final String note;
}
