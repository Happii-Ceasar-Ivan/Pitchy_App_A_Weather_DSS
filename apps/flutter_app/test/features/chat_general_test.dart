// Ask Pitchy without a match (Task A): general questions to POST /conversation.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/errors/api_failure.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/features/conversational_agent/chat_controller.dart';
import 'package:pitchy/features/conversational_agent/chat_reply.dart';
import 'package:pitchy/features/conversational_agent/chat_screen.dart';
import 'package:pitchy/features/conversational_agent/chat_session.dart';
import 'package:pitchy/shared/models/conversation.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';

import '../app_harness.dart';

final _now = DateTime.utc(2026, 11, 25, 3);

GeneralConversationResponse _general(ChatScenario s) => GeneralConversationResponse.fromJson(
  generalConversationJson(now: _now, role: 'coach', scenario: s),
);

({MockPitchyApi api, ChatController chat}) _setUp(ChatScenario scenario) {
  final api = MockPitchyApi(chat: scenario, clock: () => _now, latency: Duration.zero);
  final chat = ChatController(
    api: api,
    session: ChatSession(api: api),
    preferences: MemoryPreferences({PrefKeys.chatRole: 'coach'}),
    clock: () => _now,
  );
  return (api: api, chat: chat);
}

Finder _selectable(String text) =>
    find.byWidgetPredicate((w) => w is SelectableText && w.data == text);

void main() {
  group('reply view (general)', () {
    test('an answer shows the general-guidance notice apart from other limitations', () {
      final v = ChatReplyView.of(_general(ChatScenario.answered));
      expect(v.isAnswer, isTrue);
      expect(v.generalOnly, contains('general guidance'));
      expect(v.notAuthority, contains('not an official safety decision'));
      expect(v.limitations, isEmpty);
      expect(v.references.single.title, 'Demo heat guidance');
    });

    for (final (scenario, code) in [
      (ChatScenario.offTopic, 'OFF_TOPIC'),
      (ChatScenario.noGuidanceFound, 'NO_GUIDANCE_FOUND'),
      (ChatScenario.aiUnavailable, 'AI_UNAVAILABLE'),
      (ChatScenario.dailyLimitReached, 'DAILY_LIMIT_REACHED'),
      (ChatScenario.answerCheckFailed, 'ANSWER_CHECK_FAILED'),
    ]) {
      test('$code: its message is the reply, and the notice still shows', () {
        final r = _general(scenario);
        final v = ChatReplyView.of(r);
        expect(v.isAnswer, isFalse);
        expect(v.text, r.limitations.singleWhere((l) => l.code == code).message);
        expect(v.generalOnly, isNotNull);
        expect(v.limitations, isEmpty);
      });
    }

    test('a general reply without GENERAL_GUIDANCE_ONLY still gets the app fallback', () {
      final json = generalConversationJson(now: _now, role: 'coach');
      json['limitations'] = [
        for (final l in json['limitations'] as List)
          if ((l as Map)['code'] != 'GENERAL_GUIDANCE_ONLY') l,
      ];
      final v = ChatReplyView.of(GeneralConversationResponse.fromJson(json));
      expect(v.generalOnly, ChatReplyView.fallbackGeneralOnly);
    });

    test('a match reply never shows the general notice', () {
      final r = ConversationResponse.fromJson(conversationJson(now: _now, role: 'coach'));
      expect(ChatReplyView.of(r).generalOnly, isNull);
    });
  });

  group('controller (general)', () {
    test('without a match the question goes to the general route', () async {
      final s = _setUp(ChatScenario.answered);
      expect(s.chat.isGeneral, isTrue);
      await s.chat.send('When are cooling breaks used?');
      final reply = s.chat.entries.last as BotReply;
      expect(reply.response, isA<GeneralConversationResponse>());
      expect(s.api.tokensSeen, ['mock-session-token-1']);
    });

    test('401 once: one new session and one retry', () async {
      final s = _setUp(ChatScenario.sessionExpiredOnce);
      await s.chat.send('When are cooling breaks used?');
      expect(s.chat.entries.last, isA<BotReply>());
      expect(s.api.sessionsCreated, 2);
      expect(s.api.tokensSeen, ['mock-session-token-1', 'mock-session-token-2']);
    });

    test('401 twice: the question fails, no third try', () async {
      final s = _setUp(ChatScenario.sessionAlwaysInvalid);
      await s.chat.send('When are cooling breaks used?');
      final q = s.chat.entries.single as UserQuestion;
      expect(((q.status as QuestionFailed).failure as ApiError).statusCode, 401);
      expect(s.api.tokensSeen, hasLength(2));
    });

    test('429: held until retry_at and the composer is off', () async {
      final s = _setUp(ChatScenario.rateLimited);
      await s.chat.send('When are cooling breaks used?');
      final q = s.chat.entries.single as UserQuestion;
      expect((q.status as QuestionHeld).retryAt, _now.add(const Duration(minutes: 20)));
      expect(s.chat.canSend, isFalse);
      s.chat.dispose();
    });
  });

  group('screen (general)', () {
    Future<MockPitchyApi> open(WidgetTester tester, {ChatScenario? chat}) async {
      final (api, _) = await pumpPitchyApp(
        tester,
        location: Routes.chat,
        size: const Size(390, 1600),
      );
      if (chat != null) api.chat = chat;
      return api;
    }

    Future<void> start(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('role-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coach').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start chatting'));
      await tester.pumpAndSettle();
    }

    Future<void> ask(WidgetTester tester, String q) async {
      await tester.enterText(find.byType(TextField), q);
      await tester.pump();
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
    }

    testWidgets('entry: Start chatting and Set up a match are both offered', (tester) async {
      await open(tester);
      expect(find.text('Welcome to Ask Pitchy'), findsOneWidget);
      expect(find.text('Choose your role to start'), findsOneWidget);
      expect(find.text('Set up a match'), findsOneWidget);
      expect(find.text('Your match'), findsNothing);
    });

    testWidgets('the general chat says so and offers general starter questions', (tester) async {
      final api = await open(tester);
      await start(tester);
      expect(find.textContaining('No match selected'), findsOneWidget);
      expect(find.text('Set up a match'), findsOneWidget);
      for (final q in generalStarterQuestions) {
        expect(find.text(q), findsOneWidget);
      }
      await tester.tap(find.text(generalStarterQuestions.first));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        generalStarterQuestions.first,
      );
      expect(api.tokensSeen, isEmpty);
    });

    testWidgets('a general reply shows the general-guidance notice under the text', (
      tester,
    ) async {
      await open(tester);
      await start(tester);
      await ask(tester, 'When are cooling breaks used?');
      expect(_selectable('When are cooling breaks used?'), findsOneWidget);
      expect(find.textContaining('Demo reply'), findsOneWidget);
      expect(find.byKey(const ValueKey('general-only')), findsOneWidget);
      expect(find.textContaining('not advice about current conditions'), findsOneWidget);
      expect(find.textContaining('not an official safety decision'), findsOneWidget);
    });

    testWidgets('NO_GUIDANCE_FOUND is the bot reply, with the notice', (tester) async {
      await open(tester, chat: ChatScenario.noGuidanceFound);
      await start(tester);
      await ask(tester, 'What is the offside rule?');
      expect(find.text('No AI answer'), findsOneWidget);
      expect(find.textContaining('No approved guidance covers'), findsOneWidget);
      expect(find.byKey(const ValueKey('general-only')), findsOneWidget);
    });

    testWidgets('the notice collapses to the safety line and expands again', (tester) async {
      await open(tester);
      await start(tester);
      const safety = 'AI explanations, not decisions. Officials decide.';
      expect(find.textContaining('No match selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide details'));
      await tester.pumpAndSettle();
      // The safety line never hides; the details and Set up a match do.
      expect(find.text(safety), findsOneWidget);
      expect(find.textContaining('No match selected'), findsNothing);
      expect(find.text('Set up a match'), findsNothing);
      final button = tester.getSize(find.byTooltip('Show details'));
      expect(button.width, greaterThanOrEqualTo(48));
      expect(button.height, greaterThanOrEqualTo(48));

      await tester.tap(find.byTooltip('Show details'));
      await tester.pumpAndSettle();
      expect(find.text(safety), findsOneWidget);
      expect(find.textContaining('No match selected'), findsOneWidget);
      expect(find.text('Set up a match'), findsOneWidget);
    });

    testWidgets('Set up a match from the general chat opens match setup', (tester) async {
      await open(tester);
      await start(tester);
      await tester.tap(find.text('Set up a match'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
    });
  });
}
