// Live check of Ask Pitchy against the deployed backend (not part of the normal
// test run):
//   flutter test test_live/live_chat_test.dart
// Uses the app's own HTTP client, models and ChatController. Creates one
// session (per-IP limit 30/h), one throwaway match (20/h) and asks two
// questions (10 per 10 minutes per session). The token is never printed.

import 'package:flutter_test/flutter_test.dart';
import 'package:pitchy/core/config/app_config.dart';
import 'package:pitchy/core/network/http_pitchy_api.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/features/conversational_agent/chat_controller.dart';
import 'package:pitchy/features/conversational_agent/chat_reply.dart';
import 'package:pitchy/features/conversational_agent/chat_session.dart';
import 'package:pitchy/shared/models/conversation.dart';
import 'package:pitchy/shared/models/match.dart';

void main() {
  final api = HttpPitchyApi(baseUrl: Uri.parse(AppConfig.defaultApiBaseUrl));

  test('Ask Pitchy answers a match question and declines an off-topic one', () async {
    final now = DateTime.now().toUtc();
    final kickoff = DateTime.utc(now.year, now.month, now.day, now.hour).add(
      const Duration(hours: 4),
    );
    final match = await api.createMatchContext(
      MatchContextCreate(venueScopeKey: 'rizal_memorial', kickoffAt: kickoff),
    );
    final chat = ChatController(
      api: api,
      session: ChatSession(api: api),
      preferences: MemoryPreferences({PrefKeys.chatRole: ConversationRole.coach.wire}),
      matchContextId: match.id,
    );

    for (final q in [
      'Do we need cooling breaks for this match?',
      'What is the capital of France?',
    ]) {
      await chat.send(q);
      final last = chat.entries.last;
      if (last is UserQuestion) {
        fail(
          '"$q" was not answered: ${last.status.runtimeType} '
          '${last.status is QuestionFailed ? (last.status as QuestionFailed).failure : ''}'
          '${last.status is QuestionHeld ? 'retry_at=${(last.status as QuestionHeld).retryAt}' : ''}',
        );
      }
      final reply = (last as BotReply).response;
      final view = ChatReplyView.of(reply);
      // ignore: avoid_print
      print(
        'Q: $q\n  generation=${reply.generation.wire} isAnswer=${view.isAnswer} '
        'codes=${reply.limitations.map((l) => l.code).join(',')} '
        'refs=${reply.references.length} groups=${view.references.length}\n'
        '  text: ${view.text.length > 300 ? '${view.text.substring(0, 300)}…' : view.text}',
      );
      expect(
        reply.limitations.map((l) => l.code),
        contains(ChatLimitationCodes.agentNotAuthority),
      );
      expect(view.text, isNotEmpty);
    }
    chat.dispose();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
