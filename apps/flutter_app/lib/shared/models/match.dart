// Venues and match contexts (contract schemas VenueInfo, VenueList, MatchContext,
// MatchContextCreate, AgeGroup). Confirmed: live since Backend Sprint B3;
// age_group since B4.

import 'json.dart';

class Venue {
  const Venue({
    required this.scopeKey,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  factory Venue.fromJson(Json json) => Venue(
    scopeKey: readString(json, 'scope_key'),
    name: readString(json, 'name'),
    latitude: readDouble(json, 'latitude'),
    longitude: readDouble(json, 'longitude'),
  );

  /// Sent to the API instead of coordinates (P-07), e.g. `rizal_memorial`.
  final String scopeKey;
  final String name;
  final double latitude;
  final double longitude;
}

/// Selects the heat level set in the backend's rules (team decision
/// 2026-11-24). The backend defaults to senior when none is sent.
enum AgeGroup {
  senior('senior'),
  youthU20('youth_u20');

  const AgeGroup(this.wire);
  final String wire;

  static String wireOf(AgeGroup a) => a.wire;
}

List<Venue> venueListFromJson(Json json) => readList(json, 'venues', Venue.fromJson);

class MatchContext {
  const MatchContext({
    required this.id,
    required this.kickoffAt,
    required this.venue,
    required this.pitchSurface,
    required this.ageGroup,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MatchContext.fromJson(Json json) => MatchContext(
    id: readString(json, 'id'),
    kickoffAt: readTime(json, 'kickoff_at'),
    venue: Venue.fromJson(asJson(json['venue'], 'venue')),
    pitchSurface: readStringOrNull(json, 'pitch_surface'),
    ageGroup: readEnum(json, 'age_group', AgeGroup.values, AgeGroup.wireOf),
    createdAt: readTime(json, 'created_at'),
    updatedAt: readTime(json, 'updated_at'),
  );

  final String id;
  final DateTime kickoffAt;
  final Venue venue;
  final String? pitchSurface;
  final AgeGroup ageGroup;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class MatchContextCreate {
  const MatchContextCreate({
    required this.kickoffAt,
    required this.venueScopeKey,
    this.pitchSurface,
    this.ageGroup,
  });

  final DateTime kickoffAt;
  final String venueScopeKey;

  /// Optional metadata; no turf adjustment is applied (DEC-05). Max 50 characters.
  final String? pitchSurface;

  /// Not chosen in the app yet (F3); the backend then uses senior.
  final AgeGroup? ageGroup;

  Json toJson() => {
    'kickoff_at': writeTime(kickoffAt),
    'venue': venueScopeKey,
    if (pitchSurface != null) 'pitch_surface': pitchSurface,
    if (ageGroup != null) 'age_group': ageGroup!.wire,
  };
}
