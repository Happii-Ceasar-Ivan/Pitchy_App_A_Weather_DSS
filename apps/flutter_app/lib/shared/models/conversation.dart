// Conversation and anonymous session (contract schemas ConversationRequest,
// ConversationResponse, GeneralConversationResponse, ConversationRole,
// SessionCreated), live since B5 (general questions since B6).
// Checked field by field against backend/contract/openapi.v1.json (F4, Task A).
//
// A generated answer is an explanation, never an official decision.

import 'assessment.dart';
import 'json.dart';
import 'weather.dart';

/// Conversational context only, not an account role (P-03).
enum ConversationRole {
  coach('coach', 'Coach'),
  matchOfficial('match_official', 'Match Official/Commissioner'),
  referee('referee', 'Referee'),
  medicalStaff('medical_staff', 'Medical Staff'),
  spectator('spectator', 'Spectator');

  const ConversationRole(this.wire, this.label);
  final String wire;
  final String label;

  static String wireOf(ConversationRole r) => r.wire;
}

class ConversationRequest {
  const ConversationRequest({required this.role, required this.question});

  final ConversationRole role;

  /// 1 to 2000 characters (contract).
  final String question;

  static const maxQuestionLength = 2000;

  Json toJson() => {'role': role.wire, 'question': question};
}

enum Generation {
  generated('generated'),
  unavailable('unavailable');

  const Generation(this.wire);
  final String wire;

  static String wireOf(Generation g) => g.wire;
}

/// What every Ask Pitchy reply has, with or without a match. The chat shows
/// replies only through this, so both kinds read the same way.
abstract interface class ChatAnswer {
  ConversationRole get role;

  /// `unavailable` when no AI provider can answer (FR-AGT-006).
  Generation get generation;
  String? get answer;
  List<GuidanceReference> get references;
  List<Limitation> get limitations;
  DateTime get respondedAt;
}

/// Reply to a question about one match (`POST /match-contexts/{id}/conversation`).
class ConversationResponse implements ChatAnswer {
  const ConversationResponse({
    required this.matchContextId,
    required this.assessmentId,
    required this.role,
    required this.generation,
    required this.answer,
    required this.references,
    required this.limitations,
    required this.respondedAt,
  });

  factory ConversationResponse.fromJson(Json json) => ConversationResponse(
    matchContextId: readString(json, 'match_context_id'),
    assessmentId: readStringOrNull(json, 'assessment_id'),
    role: readEnum(json, 'role', ConversationRole.values, ConversationRole.wireOf),
    generation: readEnum(json, 'generation', Generation.values, Generation.wireOf),
    answer: readStringOrNull(json, 'answer'),
    references: readList(json, 'references', GuidanceReference.fromJson, optional: true),
    limitations: readList(json, 'limitations', Limitation.fromJson, optional: true),
    respondedAt: readTime(json, 'responded_at'),
  );

  final String matchContextId;
  final String? assessmentId;
  @override
  final ConversationRole role;

  /// `unavailable` when no AI provider can answer; the assessment still works (FR-AGT-006).
  @override
  final Generation generation;
  @override
  final String? answer;
  @override
  final List<GuidanceReference> references;
  @override
  final List<Limitation> limitations;
  @override
  final DateTime respondedAt;
}

/// Reply to a general question asked without a match (`POST /conversation`,
/// B6): approved guidance only, never about current conditions. The backend
/// always puts `AGENT_NOT_AUTHORITY` and `GENERAL_GUIDANCE_ONLY` first in
/// [limitations].
class GeneralConversationResponse implements ChatAnswer {
  const GeneralConversationResponse({
    required this.role,
    required this.generation,
    required this.answer,
    required this.references,
    required this.limitations,
    required this.respondedAt,
  });

  factory GeneralConversationResponse.fromJson(Json json) => GeneralConversationResponse(
    role: readEnum(json, 'role', ConversationRole.values, ConversationRole.wireOf),
    generation: readEnum(json, 'generation', Generation.values, Generation.wireOf),
    answer: readStringOrNull(json, 'answer'),
    references: readList(json, 'references', GuidanceReference.fromJson, optional: true),
    limitations: readList(json, 'limitations', Limitation.fromJson, optional: true),
    respondedAt: readTime(json, 'responded_at'),
  );

  @override
  final ConversationRole role;
  @override
  final Generation generation;
  @override
  final String? answer;
  @override
  final List<GuidanceReference> references;
  @override
  final List<Limitation> limitations;
  @override
  final DateTime respondedAt;
}

class SessionCreated {
  const SessionCreated({required this.token, required this.createdAt});

  factory SessionCreated.fromJson(Json json) =>
      SessionCreated(token: readString(json, 'token'), createdAt: readTime(json, 'created_at'));

  /// Kept in memory only (F4 decision 2026-11-25). Never logged or shown.
  final String token;
  final DateTime createdAt;
}
