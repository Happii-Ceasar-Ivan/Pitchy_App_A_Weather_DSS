import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/errors/api_failure.dart';
import '../../core/network/pitchy_api.dart';
import '../../core/storage/preferences.dart';
import '../../shared/models/conversation.dart';
import 'chat_session.dart';

/// Where a question the user typed stands.
sealed class QuestionStatus {
  const QuestionStatus();
}

class QuestionSending extends QuestionStatus {
  const QuestionSending();
}

class QuestionAnswered extends QuestionStatus {
  const QuestionAnswered();
}

/// The request failed (offline, timeout, server error...). It can be sent again.
class QuestionFailed extends QuestionStatus {
  const QuestionFailed(this.failure);
  final ApiFailure failure;
}

/// The backend's limit was reached (429). Asking again is held until [retryAt].
class QuestionHeld extends QuestionStatus {
  const QuestionHeld(this.retryAt);
  final DateTime? retryAt;
}

sealed class ChatEntry {
  const ChatEntry(this.id);
  final int id;
}

/// The user's own message. It appears as soon as it is sent (the only
/// optimistic UI allowed); its [status] follows the request.
class UserQuestion extends ChatEntry {
  UserQuestion(super.id, {required this.text, required this.role, required this.askedAt});

  final String text;
  final ConversationRole role;
  final DateTime askedAt;
  QuestionStatus status = const QuestionSending();
}

/// A reply exactly as the backend returned it. Never made up by the app.
class BotReply extends ChatEntry {
  const BotReply(super.id, this.response);

  /// A [ConversationResponse] in a match chat, a [GeneralConversationResponse]
  /// in the general one.
  final ChatAnswer response;
}

/// One conversation with PitChyAT: about one match, or general questions
/// when [matchContextId] is null (`POST /conversation`, Task A). History is
/// kept in memory only (team decision 2026-11-25) and is gone when the match
/// changes or the app closes. The role is a remembered preference; it only changes wording on
/// the backend (P-03).
class ChatController extends ChangeNotifier {
  ChatController({
    required this.api,
    required this.session,
    required this.preferences,
    this.matchContextId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _role = ConversationRole.values
        .where((r) => r.wire == preferences.getString(PrefKeys.chatRole))
        .firstOrNull;
  }

  final PitchyApi api;
  final ChatSession session;
  final Preferences preferences;

  /// Null for general questions without a match.
  final String? matchContextId;
  bool get isGeneral => matchContextId == null;
  final DateTime Function() _clock;

  final List<ChatEntry> _entries = [];
  List<ChatEntry> get entries => List.unmodifiable(_entries);
  int _nextId = 0;

  ConversationRole? _role;
  ConversationRole? get role => _role;

  void setRole(ConversationRole role) {
    if (_role == role) return;
    _role = role;
    unawaited(preferences.setString(PrefKeys.chatRole, role.wire));
    _notify();
  }

  bool _sending = false;
  bool get sending => _sending;

  DateTime? _waitUntil;
  Timer? _waitTimer;

  /// Set after a 429 until its `retry_at` has passed.
  DateTime? get waitUntil => _waitUntil;

  bool get canSend => _role != null && !_sending && _waitUntil == null && !_disposed;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// A question the composer would accept: 1 to 2000 characters after trimming.
  static bool isValidQuestion(String text) {
    final t = text.trim();
    return t.isNotEmpty && t.length <= ConversationRequest.maxQuestionLength;
  }

  /// Sends one question. Ignored while another is in flight, during a 429
  /// wait, without a role, or for an empty or too-long question.
  Future<void> send(String text) async {
    final question = text.trim();
    final role = _role;
    if (!canSend || role == null || !isValidQuestion(question)) return;
    final entry = UserQuestion(_nextId++, text: question, role: role, askedAt: _clock().toUtc());
    _entries.add(entry);
    await _ask(entry);
  }

  /// Sends a failed or held question again, as a new message at the end.
  Future<void> resend(UserQuestion failed) async {
    if (failed.status is! QuestionFailed && failed.status is! QuestionHeld) return;
    if (!canSend) return;
    _entries.remove(failed);
    await send(failed.text);
  }

  Future<void> _ask(UserQuestion entry) async {
    _sending = true;
    _notify();
    try {
      final response = await _askWithSession(
        ConversationRequest(role: entry.role, question: entry.text),
      );
      if (_disposed) return;
      entry.status = const QuestionAnswered();
      _entries.add(BotReply(_nextId++, response));
    } on ApiError catch (e) {
      if (_disposed) return;
      if (e.code == ApiErrorCode.rateLimited) {
        entry.status = QuestionHeld(e.retryAt);
        _holdUntil(e.retryAt);
      } else {
        entry.status = QuestionFailed(e);
      }
    } on ApiFailure catch (e) {
      if (_disposed) return;
      entry.status = QuestionFailed(e);
    } finally {
      _sending = false;
      _notify();
    }
  }

  /// One request with the current session. A 401 `INVALID_SESSION` gets one
  /// new session and one retry; a second 401 is returned as the failure.
  /// Both routes share the session and its per-session limit.
  Future<ChatAnswer> _askWithSession(ConversationRequest request) async {
    var token = await session.token();
    try {
      return await _route(request, token);
    } on ApiError catch (e) {
      if (e.code != ApiErrorCode.invalidSession && e.statusCode != 401) rethrow;
      session.invalidate(token);
      token = await session.token();
      return _route(request, token);
    }
  }

  Future<ChatAnswer> _route(ConversationRequest request, String token) {
    final id = matchContextId;
    return id == null
        ? api.askGeneralQuestion(request, sessionToken: token)
        : api.askQuestion(id, request, sessionToken: token);
  }

  void _holdUntil(DateTime? retryAt) {
    _waitTimer?.cancel();
    _waitTimer = null;
    // Without retry_at the backend gave no time; hold for a minute so the
    // user isn't invited to hammer it.
    final until = retryAt ?? _clock().toUtc().add(const Duration(minutes: 1));
    final wait = until.difference(_clock().toUtc());
    if (wait <= Duration.zero) {
      _waitUntil = null;
      return;
    }
    _waitUntil = until;
    // A local timer only re-enables the composer; the next request is still
    // the backend's decision.
    _waitTimer = Timer(wait + const Duration(seconds: 1), () {
      _waitUntil = null;
      _waitTimer = null;
      _notify();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _waitTimer?.cancel();
    super.dispose();
  }
}
