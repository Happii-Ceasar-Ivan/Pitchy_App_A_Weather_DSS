// PROVISIONAL. Safety assessment (contract schemas SafetyAssessment, HazardIndicator,
// InputValue, GuidanceReference, OfficialNotice). The backend returns 501 until
// Sprint B4; these shapes follow the contract draft and may change. See
// D:\Pitchy_App\docs\frontend\api-assumptions.md.
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

class HazardIndicator {
  const HazardIndicator({
    required this.hazard,
    required this.status,
    required this.indicatorValue,
    required this.indicatorUnit,
    required this.classification,
    required this.basis,
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
    basis: readStringOrNull(json, 'basis'),
    inputs: readList(json, 'inputs', InputValue.fromJson, optional: true),
    limitations: readList(json, 'limitations', Limitation.fromJson, optional: true),
    guidance: readList(json, 'guidance', GuidanceReference.fromJson, optional: true),
  );

  final Hazard hazard;
  final IndicatorStatus status;
  final double? indicatorValue;
  final String? indicatorUnit;

  /// Backend-provided label, shown verbatim. Thresholds are still OPEN (DEC-05/06, P-11).
  final String? classification;
  final String? basis;
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
