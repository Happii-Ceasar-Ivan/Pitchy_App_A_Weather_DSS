import 'dart:async';

import '../../core/network/pitchy_api.dart';

/// The anonymous chat session token (`POST /sessions`), kept in memory only
/// for as long as the app runs (team decision 2026-11-25: no secure-storage
/// package; a restart starts a new session).
///
/// The token is never logged, displayed, or written to preferences. It only
/// leaves this object as the `X-Session-Token` header of a conversation
/// request.
class ChatSession {
  ChatSession({required this.api});

  final PitchyApi api;

  String? _token;
  Future<String>? _pending;

  /// True once a session exists. Says nothing about the token itself.
  bool get active => _token != null;

  /// The current token, creating a session on first use. Two callers at once
  /// share one `POST /sessions`. Throws the request's [ApiFailure] (a 429
  /// carries `retry_at`).
  Future<String> token() {
    final t = _token;
    if (t != null) return Future.value(t);
    return _pending ??= _create();
  }

  Future<String> _create() async {
    try {
      final created = await api.createSession();
      _token = created.token;
      return created.token;
    } finally {
      _pending = null;
    }
  }

  /// Drops [used] after the backend rejected it (401 `INVALID_SESSION`), so
  /// the next [token] call makes a new session. A token that was already
  /// replaced is left alone.
  void invalidate(String used) {
    if (_token == used) _token = null;
  }

  /// Forgets the session (for example when the app is reset).
  void clear() => _token = null;

  @override
  String toString() => 'ChatSession(active: $active)';
}
