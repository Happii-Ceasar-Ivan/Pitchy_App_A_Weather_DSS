// Safety assessment (contract schemas SafetyAssessment, HazardIndicator, AssessmentLevel,
// IndicatorPoint, RuleNotice, InputValue, GuidanceReference, OfficialNotice).
// Confirmed: live since Backend Sprint B4 (`GET /match-contexts/{id}/assessment`).
//
// The app displays classifications, values and guidance exactly as the backend
// sends them. It never calculates, overrides or hardcodes a classification.

import 'json.dart';
import 'match.dart';
import 'weather.dart';

enum Hazard {
  heat('heat'),
  lightning('lightning'),
  rainfall('rainfall');

  const Hazard(this.wire);
  final String wire;

  static String wireOf(Hazard h) => h.wire;
}

enum IndicatorStatus {
  available('available'),
  limited('limited'),
  unavailable('unavailable');

  const IndicatorStatus(this.wire);
  final String wire;

  static String wireOf(IndicatorStatus s) => s.wire;
}

class GuidanceReference {
  const GuidanceReference({
    required this.documentId,
    required this.title,
    required this.authority,
    required this.version,
    required this.section,
  });

  factory GuidanceReference.fromJson(Json json) => GuidanceReference(
    documentId: readString(json, 'document_id'),
    title: readString(json, 'title'),
    authority: readString(json, 'authority'),
    version: readString(json, 'version'),
    section: readStringOrNull(json, 'section'),
  );

  final String documentId;
  final String title;
  final String authority;
  final String version;
  final String? section;
}

class InputValue {
  const InputValue({
    required this.parameter,
    required this.value,
    required this.unit,
    required this.provenance,
  });

  factory InputValue.fromJson(Json json) => InputValue(
    parameter: readString(json, 'parameter'),
    value: readDoubleOrNull(json, 'value'),
    unit: readStringOrNull(json, 'unit'),
    provenance: Provenance.fromJson(asJson(json['provenance'], 'provenance')),
  );

  final String parameter;
  final double? value;
  final String? unit;
  final Provenance provenance;
}

/// The level the approved rules gave an indicator (contract `AssessmentLevel`).
/// Label and action are the source's words, shown verbatim.
class AssessmentLevel {
  const AssessmentLevel({
    required this.id,
    required this.label,
    required this.action,
    required this.source,
    required this.alsoSupportedBy,
    this.severity,
  });

  factory AssessmentLevel.fromJson(Json json) => AssessmentLevel(
    id: readString(json, 'id'),
    label: readString(json, 'label'),
    action: readString(json, 'action'),
    source: GuidanceReference.fromJson(asJson(json['source'], 'source')),
    alsoSupportedBy: readList(
      json,
      'also_supported_by',
      GuidanceReference.fromJson,
      optional: true,
    ),
    severity: readStringOrNull(json, 'severity'),
  );

  final String id;
  final String label;
  final String action;
  final GuidanceReference source;
  final List<GuidanceReference> alsoSupportedBy;

  /// How strongly to show the level: `advisory`, `warning` or `danger`, from
  /// the backend's rules file (P-19). Display only; null when not given.
  final String? severity;
}

/// One calculated value at one time (contract `IndicatorPoint`), e.g. WBGT at a
/// FIFA measurement time. A null value comes with the inputs that were missing.
class IndicatorPoint {
  const IndicatorPoint({
    required this.at,
    required this.forecastStamp,
    required this.value,
    required this.usedForLevel,
    required this.missing,
  });

  factory IndicatorPoint.fromJson(Json json) => IndicatorPoint(
    at: readTime(json, 'at'),
    forecastStamp: readTime(json, 'forecast_stamp'),
    value: readDoubleOrNull(json, 'value'),
    usedForLevel: readBool(json, 'used_for_level'),
    missing: readStringList(json, 'missing', optional: true),
  );

  final DateTime at;
  final DateTime forecastStamp;
  final double? value;

  /// True for the value the backend used to set the level.
  final bool usedForLevel;
  final List<String> missing;
}

/// A rule note from the approved rules (contract `RuleNotice`), shown verbatim.
class RuleNotice {
  const RuleNotice({required this.id, required this.text, required this.source});

  factory RuleNotice.fromJson(Json json) => RuleNotice(
    id: readString(json, 'id'),
    text: readString(json, 'text'),
    source: GuidanceReference.fromJson(asJson(json['source'], 'source')),
  );

  final String id;
  final String text;
  final GuidanceReference source;
}

class HazardIndicator {
  const HazardIndicator({
    required this.hazard,
    required this.status,
    required this.indicatorValue,
    required this.indicatorUnit,
    required this.classification,
    required this.level,
    required this.basis,
    required this.decidedBy,
    required this.points,
    required this.hourly,
    required this.notices,
    required this.procedure,
    required this.inputs,
    required this.limitations,
    required this.guidance,
  });

  factory HazardIndicator.fromJson(Json json) => HazardIndicator(
    hazard: readEnum(json, 'hazard', Hazard.values, Hazard.wireOf),
    status: readEnum(json, 'status', IndicatorStatus.values, IndicatorStatus.wireOf),
    indicatorValue: readDoubleOrNull(json, 'indicator_value'),
    indicatorUnit: readStringOrNull(json, 'indicator_unit'),
    classification: readStringOrNull(json, 'classification'),
    level: json['level'] == null ? null : AssessmentLevel.fromJson(asJson(json['level'], 'level')),
    basis: readStringOrNull(json, 'basis'),
    decidedBy: readStringOrNull(json, 'decided_by'),
    points: readList(json, 'points', IndicatorPoint.fromJson, optional: true),
    hourly: readList(json, 'hourly', IndicatorPoint.fromJson, optional: true),
    notices: readList(json, 'notices', RuleNotice.fromJson, optional: true),
    procedure: readStringList(json, 'procedure', optional: true),
    inputs: readList(json, 'inputs', InputValue.fromJson, optional: true),
    limitations: readList(json, 'limitations', Limitation.fromJson, optional: true),
    guidance: readList(json, 'guidance', GuidanceReference.fromJson, optional: true),
  );

  final Hazard hazard;
  final IndicatorStatus status;

  /// Calculated by the backend (e.g. WBGT). Never recalculated here.
  final double? indicatorValue;
  final String? indicatorUnit;

  /// Level id from the approved rules; null without a rule or current inputs.
  final String? classification;

  /// The level's label, action and source. Null when there is no classification.
  final AssessmentLevel? level;
  final String? basis;

  /// Who makes the official decision under the source rules.
  final String? decidedBy;

  /// Heat: WBGT at the FIFA measurement times (90 and 60 min before kickoff).
  final List<IndicatorPoint> points;

  /// Heat: WBGT for each hour of the match (information only).
  final List<IndicatorPoint> hourly;
  final List<RuleNotice> notices;

  /// Lightning: the official on-site procedure, when the backend shows it.
  final List<String> procedure;
  final List<InputValue> inputs;
  final List<Limitation> limitations;
  final List<GuidanceReference> guidance;
}

class OfficialNotice {
  const OfficialNotice({
    required this.kind,
    required this.issuer,
    required this.title,
    required this.issuedAt,
    required this.validUntil,
    required this.provenance,
  });

  factory OfficialNotice.fromJson(Json json) => OfficialNotice(
    kind: readString(json, 'kind'),
    issuer: readString(json, 'issuer'),
    title: readString(json, 'title'),
    issuedAt: readTimeOrNull(json, 'issued_at'),
    validUntil: readTimeOrNull(json, 'valid_until'),
    provenance: Provenance.fromJson(asJson(json['provenance'], 'provenance')),
  );

  final String kind;
  final String issuer;

  /// Untrusted source text. Plain text only.
  final String title;
  final DateTime? issuedAt;
  final DateTime? validUntil;
  final Provenance provenance;
}

class SafetyAssessment {
  const SafetyAssessment({
    required this.id,
    required this.matchContext,
    required this.assessedAt,
    required this.checkedAt,
    required this.ageGroup,
    required this.rulesApproved,
    required this.ruleVersion,
    required this.indicators,
    required this.officialNotices,
    required this.limitations,
  });

  factory SafetyAssessment.fromJson(Json json) => SafetyAssessment(
    id: readString(json, 'id'),
    matchContext: MatchContext.fromJson(asJson(json['match_context'], 'match_context')),
    assessedAt: readTime(json, 'assessed_at'),
    checkedAt: readTime(json, 'checked_at'),
    ageGroup: readEnum(json, 'age_group', AgeGroup.values, AgeGroup.wireOf),
    rulesApproved: readBool(json, 'rules_approved'),
    ruleVersion: readString(json, 'rule_version'),
    indicators: readList(json, 'indicators', HazardIndicator.fromJson),
    officialNotices: readList(json, 'official_notices', OfficialNotice.fromJson, optional: true),
    limitations: readList(json, 'limitations', Limitation.fromJson, optional: true),
  );

  final String id;
  final MatchContext matchContext;
  final DateTime assessedAt;
  final DateTime checkedAt;
  final AgeGroup ageGroup;

  /// False while the rules file is a draft; the app must say so (F3).
  final bool rulesApproved;
  final String ruleVersion;
  final List<HazardIndicator> indicators;
  final List<OfficialNotice> officialNotices;
  final List<Limitation> limitations;
}
