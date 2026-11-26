import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../shared/models/json.dart';
import '../errors/api_failure.dart';
import '../state/loadable.dart';
import 'preferences.dart';

/// What a saved copy can hold (DEC-13). Chat, the session token and secrets
/// have no kind on purpose: they are never saved.
enum SavedKind {
  /// The match itself (venue, kickoff), so a copy can be shown after a cold
  /// start without the server.
  match,
  weatherStatus,

  /// Consolidated weather for the default window only (no `hours`).
  weather,

  /// Consolidated weather for the trend chart's window (P-27: `hours_before`).
  trend,
  alerts,
  assessment,
}

/// One saved backend reply, exactly as the backend sent it.
@immutable
class SavedJson {
  const SavedJson({required this.body, required this.savedAt});

  final Json body;

  /// When the app received the reply (UTC), shown as "Saved copy from …".
  final DateTime savedAt;
}

/// True only when the backend could not be reached or failed itself: no
/// connection, a timeout or a 5xx. A real answer (401, 404, 409, 422, 429, 501
/// "not built", a reply that breaks the contract) is shown as it is, never
/// hidden by a copy.
bool allowsSavedCopy(ApiFailure failure) => switch (failure) {
  NetworkFailure() || TimeoutFailure() => true,
  ApiError(:final statusCode) => statusCode >= 500 && statusCode != 501,
  ContractFailure(:final statusCode) => statusCode != null && statusCode >= 500,
};

/// The DEC-13 last-result snapshot: the last successful reply per match and
/// kind, on the device. One `shared_preferences` entry holds all of them (a
/// few KB per match; user decision 2026-11-25, no new package).
///
/// Copies expire 14 days after they were saved (DEC-11/DEC-13, confirmed by
/// the user 2026-11-25) and are deleted when their match is removed.
class SavedCopyStore {
  SavedCopyStore(this._prefs, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _all = _decode(_prefs.getString(prefKey));
  }

  static const prefKey = 'savedCopy.v1';
  static const maxAge = Duration(days: 14);

  final Preferences _prefs;
  final DateTime Function() _clock;

  /// matchId → kind name → {saved_at, body}
  late Map<String, Map<String, Json>> _all;

  DateTime get _now => _clock().toUtc();

  static Map<String, Map<String, Json>> _decode(String? raw) {
    if (raw == null) return {};
    try {
      final top = asJson(jsonDecode(raw), 'savedCopy');
      return {
        for (final MapEntry(:key, :value) in top.entries)
          key: {
            for (final e in asJson(value, key).entries) e.key: asJson(e.value, e.key),
          },
      };
    } on Object {
      // A damaged value is not worth crashing over: start empty.
      return {};
    }
  }

  Future<void> _write() =>
      _all.isEmpty ? _prefs.remove(prefKey) : _prefs.setString(prefKey, jsonEncode(_all));

  /// Saves a successful reply, replacing the previous copy of that kind.
  Future<void> put(String matchId, SavedKind kind, Json body) {
    (_all[matchId] ??= {})[kind.name] = {
      'saved_at': _now.toIso8601String(),
      'body': body,
    };
    return _write();
  }

  /// The saved reply, or null when there is none or it is older than [maxAge].
  SavedJson? get(String matchId, SavedKind kind) {
    final entry = _all[matchId]?[kind.name];
    if (entry == null) return null;
    try {
      final savedAt = DateTime.parse(readString(entry, 'saved_at')).toUtc();
      if (_now.difference(savedAt) > maxAge) return null;
      return SavedJson(body: asJson(entry['body'], 'body'), savedAt: savedAt);
    } on FormatException {
      return null;
    }
  }

  /// Parses a saved reply into its model. Null when there is none, or when it
  /// no longer parses (e.g. after an app update changed the model).
  SavedCopy<T>? read<T>(String matchId, SavedKind kind, T Function(Json) parse) {
    final saved = get(matchId, kind);
    if (saved == null) return null;
    try {
      return SavedCopy(parse(saved.body), savedAt: saved.savedAt);
    } on FormatException {
      return null;
    }
  }

  /// Deletes every copy for [matchId] (the match was removed or is gone).
  Future<void> removeMatch(String matchId) async {
    if (_all.remove(matchId) != null) await _write();
  }

  /// Keeps only [matchId]'s copies (a new match became the active one).
  Future<void> keepOnly(String matchId) async {
    final before = _all.length;
    _all.removeWhere((id, _) => id != matchId);
    if (_all.length != before) await _write();
  }

  /// Deletes copies older than [maxAge]. Run once at app start.
  Future<void> purgeExpired() async {
    var changed = false;
    for (final MapEntry(key: id, value: kinds) in _all.entries.toList()) {
      kinds.removeWhere((kind, _) {
        final known = SavedKind.values.where((k) => k.name == kind).firstOrNull;
        final gone = known == null || get(id, known) == null;
        changed |= gone;
        return gone;
      });
      if (kinds.isEmpty) _all.remove(id);
    }
    if (changed) await _write();
  }
}
