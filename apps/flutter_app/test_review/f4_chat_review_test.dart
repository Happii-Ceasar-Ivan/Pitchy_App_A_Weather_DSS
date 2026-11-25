// Review captures for the F4 PitChyAT chat (not part of the normal test run).
//   flutter test test_review --plain-name f4 --update-goldens
// Output: .impeccable/review/ (git-ignored working material).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/app.dart';
import 'package:pitchy/core/config/app_config.dart';
import 'package:pitchy/core/config/app_info.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';
import 'package:pitchy/shared/models/conversation.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';

Future<void> _loadFonts() async {
  final roboto = FontLoader('Roboto');
  for (final f in ['regular', 'medium', 'bold']) {
    roboto.addFont(rootBundle.load('assets/fonts/roboto-$f.ttf'));
  }
  await roboto.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'D:\dev\flutter';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
  await loader.load();
}

final _now = DateTime.utc(2026, 11, 23, 4);

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _ask(WidgetTester t, MockPitchyApi api, ChatScenario s, String q) async {
  api.chat = s;
  await t.enterText(find.byType(TextField), q);
  await t.pump();
  await t.tap(find.byTooltip('Send question'));
  await _settle(t);
}

Future<void> _shot(
  WidgetTester tester,
  String name, {
  required Size size,
  PitchyThemeMode mode = PitchyThemeMode.light,
  ConversationRole? role,
  bool start = true,
  bool withMatch = true,
  Future<void> Function(WidgetTester, MockPitchyApi)? act,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  addTearDown(tester.view.reset);
  final api = MockPitchyApi(clock: () => _now, latency: Duration.zero);
  await tester.pumpWidget(
    PitchyApp(
      config: AppConfig(apiBaseUrl: Uri.parse('https://api.example.test'), useMocks: true),
      info: const AppInfo(version: '1.0.0', buildNumber: '1'),
      api: api,
      preferences: MemoryPreferences({
        PrefKeys.themeMode: mode.name,
        PrefKeys.activeMatchId: ?(withMatch ? rizalMemorialId : null),
        PrefKeys.chatRole: ?role?.wire,
      }),
      initialLocation: Routes.chat,
      clock: () => _now,
    ),
  );
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(Scaffold).first);
    await precacheImage(const AssetImage('assets/images/pitchy_logo_placeholder.png'), ctx);
  });
  await _settle(tester);
  if (start) {
    await tester.tap(find.text('Start chatting'));
    await _settle(tester);
  }
  if (act != null) {
    await act(tester, api);
    await _settle(tester);
  }
  await expectLater(find.byType(PitchyApp), matchesGoldenFile('../.impeccable/review/$name.png'));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 10));
}

Future<void> _conversation(WidgetTester t, MockPitchyApi api) async {
  await _ask(t, api, ChatScenario.answered, 'Do we need cooling breaks for this match?');
  await _ask(t, api, ChatScenario.offTopic, 'What is the capital of France?');
  await _ask(t, api, ChatScenario.dailyLimitReached, 'And for the second half?');
  await _ask(t, api, ChatScenario.rateLimited, 'What about lightning?');
}

void main() {
  setUpAll(_loadFonts);
  const phone = Size(390, 844);
  const tallPhone = Size(390, 1700);
  const desktop = Size(1280, 900);

  testWidgets(
    'f4 phone entry no role',
    (t) => _shot(t, 'f4-phone-entry', size: phone, start: false),
  );
  testWidgets(
    'f4 phone entry with role',
    (t) => _shot(t, 'f4-phone-entry-role', size: phone, role: ConversationRole.coach, start: false),
  );
  testWidgets(
    'f4 desktop entry',
    (t) =>
        _shot(t, 'f4-desktop-entry', size: desktop, role: ConversationRole.referee, start: false),
  );
  testWidgets(
    'f4 phone welcome',
    (t) => _shot(t, 'f4-phone-welcome', size: phone, role: ConversationRole.coach),
  );
  testWidgets(
    'f4 phone conversation',
    (t) => _shot(
      t,
      'f4-phone-conversation',
      size: tallPhone,
      role: ConversationRole.coach,
      act: _conversation,
    ),
  );
  testWidgets(
    'f4 phone conversation dark',
    (t) => _shot(
      t,
      'f4-phone-conversation-dark',
      size: tallPhone,
      mode: PitchyThemeMode.dark,
      role: ConversationRole.medicalStaff,
      act: _conversation,
    ),
  );
  testWidgets(
    'f4 desktop conversation',
    (t) => _shot(
      t,
      'f4-desktop-conversation',
      size: desktop,
      role: ConversationRole.referee,
      act: (t, api) => _ask(t, api, ChatScenario.answered, 'Do we need cooling breaks?'),
    ),
  );

  // Task A: no match, general questions.
  testWidgets(
    'taska phone entry no match',
    (t) => _shot(
      t,
      'taska-phone-entry',
      size: phone,
      role: ConversationRole.coach,
      start: false,
      withMatch: false,
    ),
  );
  testWidgets(
    'taska phone general welcome',
    (t) => _shot(
      t,
      'taska-phone-welcome',
      size: phone,
      role: ConversationRole.coach,
      withMatch: false,
    ),
  );
  testWidgets(
    'taska phone general conversation',
    (t) => _shot(
      t,
      'taska-phone-conversation',
      size: tallPhone,
      role: ConversationRole.coach,
      withMatch: false,
      act: (t, api) async {
        await _ask(t, api, ChatScenario.answered, 'When are cooling breaks used?');
        await _ask(t, api, ChatScenario.noGuidanceFound, 'What is the offside rule?');
      },
    ),
  );
  testWidgets(
    'taska phone general conversation dark',
    (t) => _shot(
      t,
      'taska-phone-conversation-dark',
      size: tallPhone,
      mode: PitchyThemeMode.dark,
      role: ConversationRole.referee,
      withMatch: false,
      act: (t, api) => _ask(t, api, ChatScenario.answered, 'When are cooling breaks used?'),
    ),
  );
}
