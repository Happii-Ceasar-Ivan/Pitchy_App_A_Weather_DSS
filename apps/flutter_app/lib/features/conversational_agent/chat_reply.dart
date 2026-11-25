import '../../shared/models/assessment.dart';
import '../../shared/models/conversation.dart';
import '../../shared/models/weather.dart';

/// Conversation limitation codes the backend sends (B5, B6).
abstract final class ChatLimitationCodes {
  static const agentNotAuthority = 'AGENT_NOT_AUTHORITY';

  /// On every reply without a match: general guidance, not about current conditions.
  static const generalGuidanceOnly = 'GENERAL_GUIDANCE_ONLY';

  /// General questions only: no approved passage matched (no AI call).
  static const noGuidanceFound = 'NO_GUIDANCE_FOUND';
  static const aiUnavailable = 'AI_UNAVAILABLE';
  static const dailyLimitReached = 'DAILY_LIMIT_REACHED';
  static const answerCheckFailed = 'ANSWER_CHECK_FAILED';
  static const retrievalKeywordOnly = 'RETRIEVAL_KEYWORD_ONLY';
  static const offTopic = 'OFF_TOPIC';

  /// Sent with `answer: null`. Their message is shown as the reply itself
  /// (backend note B5), in this order of preference.
  static const reply = [
    offTopic,
    noGuidanceFound,
    dailyLimitReached,
    aiUnavailable,
    answerCheckFailed,
  ];
}

/// One approved document the reply drew on, with every section cited.
/// The backend can list the same document more than once with different
/// sections; they are grouped here so each document shows once.
class ReferenceGroup {
  const ReferenceGroup({
    required this.documentId,
    required this.title,
    required this.authority,
    required this.version,
    required this.sections,
  });

  final String documentId;
  final String title;
  final String authority;
  final String version;
  final List<String> sections;
}

List<ReferenceGroup> groupReferences(List<GuidanceReference> refs) {
  final order = <String>[];
  final byId = <String, (GuidanceReference, List<String>)>{};
  for (final r in refs) {
    final entry = byId.putIfAbsent(r.documentId, () {
      order.add(r.documentId);
      return (r, <String>[]);
    });
    final section = r.section?.trim();
    if (section != null && section.isNotEmpty && !entry.$2.contains(section)) {
      entry.$2.add(section);
    }
  }
  return [
    for (final id in order)
      ReferenceGroup(
        documentId: id,
        title: byId[id]!.$1.title,
        authority: byId[id]!.$1.authority,
        version: byId[id]!.$1.version,
        sections: byId[id]!.$2,
      ),
  ];
}

/// The backend's citation labels: `[A]` (the match facts) and `[D1]`..
/// (documents), alone, side by side (`[A][D1]`) or in one bracket (`[A, D1]`).
const _markers = r'(?:\[(?:A|D\d{1,2})(?:\s*,\s*(?:A|D\d{1,2}))*\])+';
final _leadingMarkers = RegExp('^$_markers[ \t]*', multiLine: true);
final _innerMarkers = RegExp('[ \t]*$_markers');

/// The answer without its citation labels. They exist for the backend's answer
/// check and read as unfinished text on screen (user, 2026-11-25); the sources
/// are listed under "Based on". Nothing else in the text is changed.
String hideCitationMarkers(String text) =>
    text.replaceAll(_leadingMarkers, '').replaceAll(_innerMarkers, '').trim();

/// How one backend reply reads on screen. Everything comes from the reply;
/// the app adds only fixed fallback wording when a field is missing.
class ChatReplyView {
  const ChatReplyView({
    required this.text,
    required this.isAnswer,
    required this.notAuthority,
    required this.generalOnly,
    required this.limitations,
    required this.references,
  });

  factory ChatReplyView.of(ChatAnswer r) {
    final sent = r.answer;
    final answer = sent == null ? null : hideCitationMarkers(sent);
    final hasAnswer = answer != null && answer.isNotEmpty;

    Limitation? replyLimitation;
    if (!hasAnswer) {
      for (final code in ChatLimitationCodes.reply) {
        replyLimitation = r.limitations.where((l) => l.code == code).firstOrNull;
        if (replyLimitation != null) break;
      }
    }
    final notAuthority = r.limitations
        .where((l) => l.code == ChatLimitationCodes.agentNotAuthority)
        .firstOrNull;
    final general = r is GeneralConversationResponse;
    final generalOnly = general
        ? r.limitations.where((l) => l.code == ChatLimitationCodes.generalGuidanceOnly).firstOrNull
        : null;

    return ChatReplyView(
      text: hasAnswer ? answer : (replyLimitation?.message ?? fallbackNoAnswer),
      isAnswer: hasAnswer,
      notAuthority: notAuthority?.message ?? fallbackNotAuthority,
      generalOnly: general ? (generalOnly?.message ?? fallbackGeneralOnly) : null,
      limitations: [
        for (final l in r.limitations)
          if (!identical(l, replyLimitation) &&
              !identical(l, notAuthority) &&
              !identical(l, generalOnly))
            l,
      ],
      references: groupReferences(r.references),
    );
  }

  /// App text used only if the backend sends neither an answer nor a reply
  /// limitation.
  static const fallbackNoAnswer = 'Pitchy couldn’t answer this question.';

  /// App text used only if the backend leaves out `AGENT_NOT_AUTHORITY`.
  static const fallbackNotAuthority =
      'AI-generated explanation. It is not an official safety decision.';

  /// App text used only if a general reply leaves out `GENERAL_GUIDANCE_ONLY`.
  static const fallbackGeneralOnly =
      'No match is selected: this is general guidance, not advice about current conditions.';

  /// The answer, or the message of the limitation that took its place.
  /// Untrusted text: shown as plain text only.
  final String text;

  /// False when [text] is a limitation message (off-topic, no guidance found,
  /// daily limit, AI unavailable, answer check failed) rather than an AI answer.
  final bool isAnswer;

  /// The backend's "not an authority" message, shown on every reply.
  final String notAuthority;

  /// Set on every general reply (no match), never on a match reply: the
  /// backend's "general guidance only" message, shown with the reply.
  final String? generalOnly;

  /// The other limitations (assessment ones, keyword-only retrieval, ...).
  final List<Limitation> limitations;
  final List<ReferenceGroup> references;
}
