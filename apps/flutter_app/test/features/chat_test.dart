import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/errors/api_failure.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/features/conversational_agent/chat_controller.dart';
import 'package:pitchy/features/conversational_agent/chat_reply.dart';
import 'package:pitchy/features/conversational_agent/chat_screen.dart';
import 'package:pitchy/features/conversational_agent/chat_session.dart';
import 'package:pitchy/shared/models/assessment.dart';
import 'package:pitchy/shared/models/conversation.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';

import '../app_harness.dart';

final _now = DateTime.utc(2026, 11, 25, 3);

({MockPitchyApi api, ChatSession session, ChatController chat}) _setUp({
  ChatScenario scenario = ChatScenario.answered,
  ConversationRole? role = ConversationRole.coach,
  DateTime Function()? clock,
}) {
  final api = MockPitchyApi(chat: scenario, clock: clock ?? () => _now, latency: Duration.zero);
  final session = ChatSession(api: api);
  final prefs = MemoryPreferences({PrefKeys.chatRole: ?role?.wire});
  final chat = ChatController(
    api: api,
    session: session,
    preferences: prefs,
    matchContextId: rizalMemorialId,
    clock: clock ?? () => _now,
  );
  return (api: api, session: session, chat: chat);
}

/// Messages use SelectableText, which `find.text` doesn't match.
Finder _selectable(String text) =>
    find.byWidgetPredicate((w) => w is SelectableText && w.data == text);

ConversationResponse _reply(ChatScenario s) =>
    ConversationResponse.fromJson(conversationJson(now: _now, role: 'coach', scenario: s));

void main() {
  group('reply view', () {
    test('an answer keeps its text; the same document is grouped once', () {
      final v = ChatReplyView.of(_reply(ChatScenario.answered));
      expect(v.isAnswer, isTrue);
      expect(v.text, startsWith('Demo reply'));
      expect(v.references, hasLength(1));
      expect(v.references.single.sections, ['2.1 Cooling breaks', '3 Hydration']);
      expect(v.notAuthority, contains('not an official safety decision'));
      expect(v.limitations.map((l) => l.code), ['RETRIEVAL_KEYWORD_ONLY']);
    });

    for (final (scenario, code) in [
      (ChatScenario.offTopic, 'OFF_TOPIC'),
      (ChatScenario.aiUnavailable, 'AI_UNAVAILABLE'),
      (ChatScenario.dailyLimitReached, 'DAILY_LIMIT_REACHED'),
      (ChatScenario.answerCheckFailed, 'ANSWER_CHECK_FAILED'),
    ]) {
      test('answer null with $code: its message is the reply', () {
        final r = _reply(scenario);
        final v = ChatReplyView.of(r);
        expect(v.isAnswer, isFalse);
        expect(v.text, r.limitations.firstWhere((l) => l.code == code).message);
        expect(v.limitations, isEmpty, reason: 'shown as the reply, not twice');
        expect(v.notAuthority, contains('not an official safety decision'));
      });
    }

    test('sections are not repeated and blank sections are dropped', () {
      const ref = GuidanceReference(
        documentId: 'd',
        title: 'T',
        authority: 'A',
        version: '1',
        section: 'S1',
      );
      const blank = GuidanceReference(
        documentId: 'd',
        title: 'T',
        authority: 'A',
        version: '1',
        section: ' ',
      );
      final groups = groupReferences([ref, ref, blank]);
      expect(groups.single.sections, ['S1']);
    });
  });

  group('session', () {
    test('two callers at once share one new session', () async {
      final api = MockPitchyApi(clock: () => _now, latency: Duration.zero);
      final s = ChatSession(api: api);
      final tokens = await Future.wait([s.token(), s.token()]);
      expect(tokens[0], tokens[1]);
      expect(api.sessionsCreated, 1);
    });

    test('the token never appears in toString', () async {
      final api = MockPitchyApi(clock: () => _now, latency: Duration.zero);
      final s = ChatSession(api: api);
      final t = await s.token();
      expect(s.toString(), isNot(contains(t)));
    });
  });

  group('controller', () {
    test('a question and its reply, sent with the chosen role', () async {
      final c = _setUp().chat;
      await c.send('  Do we need cooling breaks?  ');
      expect(c.entries, hasLength(2));
      final q = c.entries.first as UserQuestion;
      expect(q.text, 'Do we need cooling breaks?');
      expect(q.status, isA<QuestionAnswered>());
      expect((c.entries.last as BotReply).response.role, ConversationRole.coach);
    });

    test('nothing is sent without a role, or when empty or too long', () async {
      final noRole = _setUp(role: null);
      await noRole.chat.send('Hello?');
      expect(noRole.chat.entries, isEmpty);
      expect(noRole.api.sessionsCreated, 0);

      final c = _setUp().chat;
      await c.send('   ');
      await c.send('x' * (ConversationRequest.maxQuestionLength + 1));
      expect(c.entries, isEmpty);
    });

    test('the role is remembered', () {
      final s = _setUp(role: null);
      s.chat.setRole(ConversationRole.referee);
      expect(s.chat.preferences.getString(PrefKeys.chatRole), 'referee');
    });

    test('401 once: one new session and one retry', () async {
      final s = _setUp(scenario: ChatScenario.sessionExpiredOnce);
      await s.chat.send('Is it safe?');
      expect(s.api.sessionsCreated, 2);
      expect(s.api.tokensSeen, ['mock-session-token-1', 'mock-session-token-2']);
      expect(s.chat.entries.last, isA<BotReply>());
    });

    test('401 again after the retry: the question fails, no loop', () async {
      final s = _setUp(scenario: ChatScenario.sessionAlwaysInvalid);
      await s.chat.send('Is it safe?');
      expect(s.api.tokensSeen, hasLength(2));
      final q = s.chat.entries.single as UserQuestion;
      expect(q.status, isA<QuestionFailed>());
    });

    testWidgets('429 holds asking until retry_at, then allows it again', (tester) async {
      final start = DateTime.utc(2026, 11, 25, 3);
      var now = start;
      final s = _setUp(scenario: ChatScenario.rateLimited, clock: () => now);
      await s.chat.send('Is it safe?');
      final q = s.chat.entries.single as UserQuestion;
      expect(q.status, isA<QuestionHeld>());
      expect(s.chat.waitUntil, start.add(const Duration(minutes: 20)));
      expect(s.chat.canSend, isFalse);
      now = start.add(const Duration(minutes: 20, seconds: 2));
      await tester.pump(const Duration(minutes: 20, seconds: 2));
      expect(s.chat.waitUntil, isNull);
      expect(s.chat.canSend, isTrue);
      s.api.chat = ChatScenario.answered;
      await s.chat.resend(q);
      expect(s.chat.entries.last, isA<BotReply>());
      s.chat.dispose();
    });

    test('offline: the question fails and can be sent again', () async {
      final s = _setUp();
      s.api.scenario = MockScenario.offline;
      await s.chat.send('Is it safe?');
      final failed = s.chat.entries.single as UserQuestion;
      expect((failed.status as QuestionFailed).failure, isA<NetworkFailure>());
      s.api.scenario = MockScenario.allCurrent;
      await s.chat.resend(failed);
      expect(s.chat.entries, hasLength(2));
      expect(s.chat.entries.last, isA<BotReply>());
    });

    test('404: the question fails', () async {
      final s = _setUp(scenario: ChatScenario.matchGone);
      await s.chat.send('Is it safe?');
      final q = s.chat.entries.single as UserQuestion;
      expect(((q.status as QuestionFailed).failure as ApiError).statusCode, 404);
    });
  });

  group('screen', () {
    Future<MockPitchyApi> openChat(WidgetTester tester, {ChatScenario? chat}) async {
      final (api, _) = await pumpPitchyApp(
        tester,
        prefs: withActiveMatch(),
        location: Routes.chat,
        size: const Size(390, 1600),
      );
      if (chat != null) api.chat = chat;
      return api;
    }

    Future<void> ask(WidgetTester tester, String q) async {
      await tester.enterText(find.byType(TextField), q);
      await tester.pump();
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
    }

    Future<void> chooseRole(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(const ValueKey('role-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    Future<void> start(WidgetTester tester, String role) async {
      await chooseRole(tester, role);
      await tester.tap(find.text('Start chatting'));
      await tester.pumpAndSettle();
    }

    testWidgets('entry screen: role first, match shown, then the chat', (tester) async {
      await openChat(tester);
      expect(find.text('Welcome to Ask Pitchy'), findsOneWidget);
      expect(find.text('Your match'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('Choose your role to start'), findsOneWidget);
      expect(find.byTooltip('Send question'), findsNothing);

      await chooseRole(tester, 'Referee');
      await tester.tap(find.text('Start chatting'));
      await tester.pumpAndSettle();
      expect(find.text('Try asking'), findsOneWidget);
      expect(find.text('AI explanations, not decisions. Officials decide.'), findsOneWidget);
    });

    testWidgets('the remembered role is preselected', (tester) async {
      await pumpPitchyApp(
        tester,
        prefs: {...withActiveMatch(), PrefKeys.chatRole: 'medical_staff'},
        location: Routes.chat,
        size: const Size(390, 1600),
      );
      expect(find.text('Start chatting'), findsOneWidget);
    });

    testWidgets('a question gets a reply with its sources and notice', (tester) async {
      await openChat(tester);
      await start(tester, 'Referee');
      await ask(tester, 'Is it safe?');

      expect(_selectable('Is it safe?'), findsOneWidget);
      expect(find.textContaining('Demo reply'), findsOneWidget);
      expect(find.textContaining('for Referee'), findsOneWidget);
      expect(find.text('Based on'), findsOneWidget);
      expect(find.textContaining('2.1 Cooling breaks; 3 Hydration'), findsOneWidget);
      expect(find.textContaining('keyword search only'), findsOneWidget);
      expect(find.textContaining('not an official safety decision'), findsOneWidget);
    });

    testWidgets('a starter question only fills the input', (tester) async {
      final api = await openChat(tester);
      await start(tester, 'Coach');
      await tester.tap(find.text(starterQuestions.first));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        starterQuestions.first,
      );
      expect(api.tokensSeen, isEmpty);
    });

    testWidgets('off-topic: the limitation message is the bot reply', (tester) async {
      await openChat(tester, chat: ChatScenario.offTopic);
      await start(tester, 'Spectator');
      await ask(tester, 'Capital of France?');
      expect(find.text('No AI answer'), findsOneWidget);
      expect(find.textContaining('only help with weather and safety'), findsOneWidget);
    });

    testWidgets('429: the question is marked not sent with the time to try again', (
      tester,
    ) async {
      await openChat(tester, chat: ChatScenario.rateLimited);
      await start(tester, 'Coach');
      await ask(tester, 'Is it safe?');
      expect(find.textContaining('question limit reached'), findsOneWidget);
      expect(find.textContaining('PHT'), findsWidgets);
    });

    testWidgets('answers are plain text: markup is shown as typed', (tester) async {
      final api = await openChat(tester);
      await start(tester, 'Coach');
      await ask(tester, '**bold** <b>tag</b>');
      expect(_selectable('**bold** <b>tag</b>'), findsOneWidget);
      expect(api.tokensSeen, hasLength(1));
    });
  });
}
