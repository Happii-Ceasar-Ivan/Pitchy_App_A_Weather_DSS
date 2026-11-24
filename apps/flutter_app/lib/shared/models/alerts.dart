// Official alerts (contract schemas VenueAlerts, OfficialAlertOut, AlertArea).
// Confirmed: live since Backend Sprint B3.
//
// Alert text comes from external sources and is untrusted: display it as plain
// text only (Text widgets), never as HTML, Markdown or links.

import 'json.dart';
import 'weather.dart';

class AlertArea {
  const AlertArea({
    required this.name,
    required this.code,
    required this.level,
    required this.relation,
  });

  factory AlertArea.fromJson(Json json) => AlertArea(
    name: readString(json, 'name'),
    code: readString(json, 'code'),
    level: readString(json, 'level'),
    relation: readString(json, 'relation'),
  );

  final String name;
  final String code;

  /// `municipality` or `province`.
  final String level;
  final String relation;
}

class OfficialAlert {
  const OfficialAlert({
    required this.issuer,
    required this.event,
    required this.subtype,
    required this.headline,
    required this.message,
    required this.issuedAt,
    required this.validUntil,
    required this.matchedAreas,
  });

  factory OfficialAlert.fromJson(Json json) => OfficialAlert(
    issuer: readString(json, 'issuer'),
    event: readString(json, 'event'),
    subtype: readString(json, 'subtype'),
    headline: readString(json, 'headline'),
    message: readString(json, 'message'),
    issuedAt: readTimeOrNull(json, 'issued_at'),
    validUntil: readTimeOrNull(json, 'valid_until'),
    matchedAreas: readList(json, 'matched_areas', AlertArea.fromJson),
  );

  final String issuer;
  final String event;
  final String subtype;

  /// Untrusted source text. Plain text only.
  final String headline;

  /// Untrusted source text. Plain text only.
  final String message;
  final DateTime? issuedAt;
  final DateTime? validUntil;
  final List<AlertArea> matchedAreas;
}

class VenueAlerts {
  const VenueAlerts({
    required this.venue,
    required this.status,
    required this.activeTropicalCyclones,
    required this.alerts,
    required this.label,
  });

  factory VenueAlerts.fromJson(Json json) => VenueAlerts(
    venue: readString(json, 'venue'),
    status: AlertsStatus.fromJson(asJson(json['status'], 'status')),
    activeTropicalCyclones: readIntOrNull(json, 'active_tropical_cyclones'),
    alerts: readList(json, 'alerts', OfficialAlert.fromJson),
    label: readStringOrNull(json, 'label'),
  );

  final String venue;
  final AlertsStatus status;
  final int? activeTropicalCyclones;
  final List<OfficialAlert> alerts;
  final String? label;
}
