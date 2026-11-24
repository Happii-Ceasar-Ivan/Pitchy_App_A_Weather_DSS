import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../core/errors/api_failure.dart';
import '../../core/network/pitchy_api.dart';
import '../../core/state/loadable.dart';
import '../../core/storage/preferences.dart';
import '../../core/utils/pht_time.dart';
import '../../shared/models/match.dart';

/// Pitch surface choices (optional metadata; no turf adjustment, DEC-05).
enum PitchSurface {
  naturalGrass('natural_grass', 'Natural grass'),
  syntheticTurf('synthetic_turf', 'Synthetic turf');

  const PitchSurface(this.wire, this.label);
  final String wire;
  final String label;

  static PitchSurface? fromWire(String? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

/// The match setup form's values, in PHT wall-clock terms (P-14). Saved as a
/// draft so a half-filled form survives leaving the screen (rulebook law 4).
@immutable
class MatchDraft {
  const MatchDraft({
    this.venueKey,
    this.date,
    this.time,
    this.surface,
    this.ageGroup = AgeGroup.senior,
  });

  factory MatchDraft.fromJson(Map<String, Object?> j) {
    final d = j['date'];
    final t = j['time'];
    return MatchDraft(
      venueKey: j['venue'] as String?,
      date: d is String ? DateTime.tryParse(d) : null,
      time: t is String && t.contains(':')
          ? TimeOfDay(hour: int.parse(t.split(':')[0]), minute: int.parse(t.split(':')[1]))
          : null,
      surface: PitchSurface.fromWire(j['surface'] as String?),
      ageGroup: AgeGroup.values.firstWhere(
        (a) => a.wire == j['age_group'],
        orElse: () => AgeGroup.senior,
      ),
    );
  }

  final String? venueKey;

  /// PHT calendar date (only year, month and day are used).
  final DateTime? date;

  /// PHT clock time.
  final TimeOfDay? time;
  final PitchSurface? surface;

  /// Selects the backend's heat level set. Senior by default, as on the backend.
  final AgeGroup ageGroup;

  /// The age group always has a value, so it doesn't count towards a started form.
  bool get isEmpty => venueKey == null && date == null && time == null && surface == null;

  /// The kickoff instant (UTC), when both date and time are set.
  DateTime? get kickoffUtc => date == null || time == null
      ? null
      : fromPhtWallClock(date!.year, date!.month, date!.day, time!.hour, time!.minute);

  MatchDraft copyWith({
    String? venueKey,
    DateTime? date,
    TimeOfDay? time,
    PitchSurface? surface,
    bool clearSurface = false,
    AgeGroup? ageGroup,
  }) => MatchDraft(
    venueKey: venueKey ?? this.venueKey,
    date: date ?? this.date,
    time: time ?? this.time,
    surface: clearSurface ? null : (surface ?? this.surface),
    ageGroup: ageGroup ?? this.ageGroup,
  );

  Map<String, Object?> toJson() => {
    'venue': venueKey,
    'date': date == null
        ? null
        : '${date!.year.toString().padLeft(4, '0')}-${date!.month.toString().padLeft(2, '0')}-'
              '${date!.day.toString().padLeft(2, '0')}',
    'time': time == null ? null : '${time!.hour}:${time!.minute}',
    'surface': surface?.wire,
    'age_group': ageGroup.wire,
  };
}

/// Why the form can't be sent yet. Plain form checks only; whether forecasts
/// cover the kickoff is the backend's call, never the app's.
enum DraftProblem { noVenue, noDate, noTime, kickoffInPast }

/// The active match and the setup draft, shared by Match setup and Dashboard.
class MatchController extends ChangeNotifier {
  MatchController({
    required this.api,
    required Preferences preferences,
    DateTime Function()? clock,
  }) : _prefs = preferences,
       _clock = clock ?? DateTime.now {
    final raw = _prefs.getString(PrefKeys.matchDraft);
    if (raw != null) {
      try {
        _draft = MatchDraft.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
      } on Object {
        _draft = const MatchDraft();
      }
    }
  }

  final PitchyApi api;
  final Preferences _prefs;
  final DateTime Function() _clock;

  DateTime get now => _clock().toUtc();

  // ---- Active match ----

  Loadable<MatchContext?> _active = const Loading();
  Loadable<MatchContext?> get active => _active;

  /// Restores the last active match from the device, if any.
  Future<void> restore() async {
    final id = _prefs.getString(PrefKeys.activeMatchId);
    if (id == null) {
      _active = const Loaded(null);
      notifyListeners();
      return;
    }
    _active = const Loading();
    notifyListeners();
    try {
      _active = Loaded(await api.getMatchContext(id));
    } on ApiError catch (e) {
      if (e.code == ApiErrorCode.notFound) {
        // The match is gone on the server (e.g. retention); start fresh.
        unawaited(_prefs.remove(PrefKeys.activeMatchId));
        _active = const Loaded(null);
      } else {
        _active = Failed(e);
      }
    } on ApiFailure catch (e) {
      _active = Failed(e);
    }
    notifyListeners();
  }

  // ---- Venues ----

  Loadable<List<Venue>> _venues = const Loading();
  Loadable<List<Venue>> get venues => _venues;

  Future<void> loadVenues() async {
    _venues = const Loading();
    notifyListeners();
    try {
      _venues = Loaded(await api.listVenues());
    } on ApiFailure catch (e) {
      _venues = Failed(e);
    }
    notifyListeners();
  }

  // ---- Draft ----

  MatchDraft _draft = const MatchDraft();
  MatchDraft get draft => _draft;

  void updateDraft(MatchDraft draft) {
    _draft = draft;
    unawaited(_prefs.setString(PrefKeys.matchDraft, jsonEncode(draft.toJson())));
    notifyListeners();
  }

  List<DraftProblem> problems([MatchDraft? d]) {
    final draft = d ?? _draft;
    final kickoff = draft.kickoffUtc;
    return [
      if (draft.venueKey == null) DraftProblem.noVenue,
      if (draft.date == null) DraftProblem.noDate,
      if (draft.time == null) DraftProblem.noTime,
      if (kickoff != null && !kickoff.isAfter(now)) DraftProblem.kickoffInPast,
    ];
  }

  bool _submitting = false;
  bool get submitting => _submitting;

  /// Creates the match on the backend and makes it active. Throws [ApiFailure].
  Future<MatchContext> submit() async {
    assert(problems().isEmpty);
    _submitting = true;
    notifyListeners();
    try {
      final match = await api.createMatchContext(
        MatchContextCreate(
          kickoffAt: _draft.kickoffUtc!,
          venueScopeKey: _draft.venueKey!,
          pitchSurface: _draft.surface?.wire,
          ageGroup: _draft.ageGroup,
        ),
      );
      _active = Loaded(match);
      unawaited(_prefs.setString(PrefKeys.activeMatchId, match.id));
      _draft = const MatchDraft();
      unawaited(_prefs.remove(PrefKeys.matchDraft));
      return match;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// Starts the form from the active match, so "Change match" begins filled in.
  void draftFromActive() {
    final a = _active;
    if (a is! Loaded<MatchContext?> || a.value == null || !_draft.isEmpty) return;
    final m = a.value!;
    final pht = toPhtWallClock(m.kickoffAt);
    updateDraft(
      MatchDraft(
        venueKey: m.venue.scopeKey,
        date: DateTime.utc(pht.year, pht.month, pht.day),
        time: TimeOfDay(hour: pht.hour, minute: pht.minute),
        surface: PitchSurface.fromWire(m.pitchSurface),
        ageGroup: m.ageGroup,
      ),
    );
  }
}
