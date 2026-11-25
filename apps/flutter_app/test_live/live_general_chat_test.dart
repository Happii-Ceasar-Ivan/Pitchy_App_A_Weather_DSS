// Live check of PitChyAT without a match (Task A, POST /conversation) against
// the deployed backend (not part of the normal test run):
//   flutter test test_live/live_general_chat_test.dart
// Uses the app's own HTTP client, models and ChatController. Creates one
// session (per-IP limit 30/h) and asks two questions (10 per 10 minutes per
// session). No match is created. The token is never printed.

import 'package:flutter_test/flutter_test.dart';
import 'package:pitchy/core/config/app_config.dart';
import 'package:pitchy/core/network/http_pitchy_api.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/features/conversational_agent/chat_controller.dart';
import 'package:pitchy/features/conversational_agent/chat_reply.dart';
import 'package:pitchy/features/conversational_agent/chat_session.dart';
import 'package:pitchy/shared/models/conversation.dart';

void main() {
  final api = HttpPitchyApi(baseUrl: Uri.parse(AppConfig.defaultApiBaseUrl));

  test('PitChyAT answers a general rules question and declines an off-topic one', () async {
    final chat = ChatController(
      api: api,
      session: ChatSession(api: api),
      preferences: MemoryPreferences({PrefKeys.chatRole: ConversationRole.coach.wire}),
    );

    for (final q in ['When does FIFA use cooling breaks?', 'What is the capital of France?']) {
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
      expect(reply, isA<GeneralConversationResponse>());
      final view = ChatReplyView.of(reply);
      // ignore: avoid_print
      print(
        'Q: $q\n  generation=${reply.generation.wire} isAnswer=${view.isAnswer} '
        'codes=${reply.limitations.map((l) => l.code).join(',')} '
        'refs=${reply.references.length}\n'
        '  text: ${view.text.length > 300 ? '${view.text.substring(0, 300)}…' : view.text}',
      );
      expect(reply.limitations.take(2).map((l) => l.code), [
        ChatLimitationCodes.agentNotAuthority,
        ChatLimitationCodes.generalGuidanceOnly,
      ]);
      expect(view.generalOnly, isNot(ChatReplyView.fallbackGeneralOnly));
      expect(view.text, isNotEmpty);
    }
    chat.dispose();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
