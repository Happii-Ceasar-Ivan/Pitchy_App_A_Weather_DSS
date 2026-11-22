// Venues and match contexts (contract schemas VenueInfo, VenueList, MatchContext,
// MatchContextCreate). Confirmed: live since Backend Sprint B3.

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

List<Venue> venueListFromJson(Json json) => readList(json, 'venues', Venue.fromJson);

class MatchContext {
  const MatchContext({
    required this.id,
    required this.kickoffAt,
    required this.venue,
    required this.pitchSurface,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MatchContext.fromJson(Json json) => MatchContext(
    id: readString(json, 'id'),
    kickoffAt: readTime(json, 'kickoff_at'),
    venue: Venue.fromJson(asJson(json['venue'], 'venue')),
    pitchSurface: readStringOrNull(json, 'pitch_surface'),
    createdAt: readTime(json, 'created_at'),
    updatedAt: readTime(json, 'updated_at'),
  );

  final String id;
  final DateTime kickoffAt;
  final Venue venue;
  final String? pitchSurface;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class MatchContextCreate {
  const MatchContextCreate({
    required this.kickoffAt,
    required this.venueScopeKey,
    this.pitchSurface,
  });

  final DateTime kickoffAt;
  final String venueScopeKey;

  /// Optional metadata; no turf adjustment is applied (DEC-05). Max 50 characters.
  final String? pitchSurface;

  Json toJson() => {
    'kickoff_at': writeTime(kickoffAt),
    'venue': venueScopeKey,
    if (pitchSurface != null) 'pitch_surface': pitchSurface,
  };
}
