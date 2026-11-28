// Device QA for F5 (platform QA 1b): taps through the app on a real phone or
// on Windows, with the mock backend (never the live one) and a fixed clock.
//
// Phone (with screenshots):
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/qa_flow_test.dart -d <device-id>
// Windows (no screenshots):
//   flutter test integration_test/qa_flow_test.dart -d windows

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/app.dart';
import 'package:pitchy/core/config/app_config.dart';
import 'package:pitchy/core/config/app_info.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/core/storage/saved_copies.dart';
import 'package:pitchy/features/settings/update_check.dart';
import 'package:pitchy/features/settings/update_installer.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';
import 'package:pitchy/shared/widgets/request_states.dart';
import 'package:pitchy/shared/widgets/source_rail.dart';
import 'package:pitchy/shared/widgets/weather_value_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.utc(2026, 11, 23, 4);

/// A filled-in match form (venue, Mon 23 Nov, 3:00 PM PHT).
const _draft = '{"venue":"rizal_memorial","date":"2026-11-23","time":"15:0","surface":null}';

late IntegrationTestWidgetsFlutterBinding _binding;
bool _surfaceReady = false;

/// Saves a screenshot on Android (via the driver); a no-op where the platform
/// can't take one (Windows) or no driver is listening (`flutter test`).
Future<void> _shot(WidgetTester t, String name) async {
  await t.pumpAndSettle();
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    if (!_surfaceReady) {
      await _binding.convertFlutterSurfaceToImage();
      _surfaceReady = true;
      await t.pumpAndSettle();
    }
    await _binding.takeScreenshot(name);
  } on Object catch (e) {
    debugPrint('screenshot $name skipped: $e');
  }
}

/// Settles, then keeps pumping until [finder] shows (or, with [gone], until it
/// has gone), up to 5 s. With the
/// device's "Remove animations" on, the loading skeleton doesn't pulse, so
/// pumpAndSettle returns before the demo API's 350 ms delay has passed.
Future<void> _waitFor(WidgetTester t, Finder finder, {bool gone = false}) async {
  await t.pumpAndSettle();
  for (var i = 0; i < 50 && finder.evaluate().isEmpty != gone; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pumpAndSettle();
}

Finder _tab(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is NavigationBar || w is NavigationRail),
  matching: find.text(label),
);

Future<MockPitchyApi> _launch(
  WidgetTester t, {
  required Preferences prefs,
  required SavedCopyStore store,
  MockScenario scenario = MockScenario.allCurrent,
}) async {
  final api = MockPitchyApi(
    scenario: scenario,
    clock: () => _now,
    latency: const Duration(milliseconds: 150),
    savedCopies: store,
  );
  await t.pumpWidget(
    PitchyApp(
      config: AppConfig(apiBaseUrl: Uri.parse('https://api.example.test'), useMocks: true),
      info: const AppInfo(version: '1.0.0', buildNumber: 'qa'),
      api: api,
      preferences: prefs,
      savedCopies: store,
      clock: () => _now,
      // Device QA never asks GitHub or installs anything.
      checkForUpdatesOnOpen: false,
      updates: UpdateChecker(
        installedVersion: '1.0.0',
        client: MockClient((_) async => http.Response('{}', 404)),
      ),
      updateInstaller: UpdateInstaller(
        platform: const NoUpdatePlatform(),
        client: MockClient((_) async => http.Response('', 404)),
      ),
    ),
  );
  await t.pumpAndSettle();
  return api;
}

/// The keys this test writes on the device, cleared before and after.
const _keys = [
  PrefKeys.activeMatchId,
  PrefKeys.chatRole,
  PrefKeys.matchDraft,
  PrefKeys.themeMode,
  PrefKeys.lastLightMode,
  SavedCopyStore.prefKey,
];

Future<SharedPreferencesStore> _deviceStore() async {
  final raw = await SharedPreferences.getInstance();
  for (final k in _keys) {
    await raw.remove(k);
  }
  return SharedPreferencesStore(raw);
}

void main() {
  _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Each test gets a fresh surface, so screenshots are set up again per test.
  setUp(() => _surfaceReady = false);

  tearDownAll(() async {
    final raw = await SharedPreferences.getInstance();
    for (final k in _keys) {
      await raw.remove(k);
    }
  });

  testWidgets('A: set up a match, visit every tab, switch to dark mode', (t) async {
    final prefs = MemoryPreferences({PrefKeys.matchDraft: _draft});
    await _launch(
      t,
      prefs: prefs,
      store: SavedCopyStore(prefs, clock: () => _now),
    );
    await _shot(t, 'a0-no-match');

    await t.tap(find.text('Set up a match'));
    await t.pumpAndSettle();
    await _shot(t, 'a1-setup-form');
    await t.scrollUntilVisible(find.text('Show conditions'), 200);
    // scrollUntilVisible can stop with the button a few pixels past the edge.
    await t.ensureVisible(find.text('Show conditions'));
    await t.pumpAndSettle();
    await t.tap(find.text('Show conditions'));
    await t.pumpAndSettle();
    expect(find.text('Kickoff Mon 23 Nov, 3:00 PM PHT'), findsOneWidget);
    expect(find.byType(SourceRail), findsOneWidget);
    expect(find.byType(WeatherCardGrid), findsOneWidget);
    await _shot(t, 'a2-board');

    await t.tap(_tab('Safety'));
    await _waitFor(t, find.textContaining('Assessed'));
    expect(find.textContaining('Assessed'), findsWidgets);
    await _shot(t, 'a3-safety');

    await t.tap(_tab('Ask Pitchy'));
    await t.pumpAndSettle();
    await _shot(t, 'a4-chat-entry');

    await t.tap(_tab('Dashboard'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Quick settings'));
    await t.pumpAndSettle();
    await _shot(t, 'a5-quick-settings');
    await t.tap(find.text('Dark mode'));
    await t.pumpAndSettle();
    // Close the drawer the way the system back gesture does.
    Navigator.of(t.element(find.text('Dark mode'))).pop();
    await t.pumpAndSettle();
    expect(prefs.getString(PrefKeys.themeMode), 'dark');
    await _shot(t, 'a6-board-dark');
  });

  testWidgets('B: online, then the server goes away: saved board, Update off', (t) async {
    final prefs = MemoryPreferences({PrefKeys.activeMatchId: rizalMemorialId});
    final store = SavedCopyStore(prefs, clock: () => _now);
    final api = await _launch(t, prefs: prefs, store: store, scenario: MockScenario.someStale);
    expect(find.text('Update'), findsOneWidget);

    api.scenario = MockScenario.offline;
    await t.tap(find.byTooltip('Refresh'));
    await t.pumpAndSettle();
    expect(find.textContaining('not live'), findsOneWidget);
    expect(find.text('CURRENT'), findsNothing);
    final update = t.widget<FilledButton>(
      find.ancestor(
        of: find.text('Update'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(update.onPressed, isNull);
    await _shot(t, 'b1-board-saved-copy');

    api.scenario = MockScenario.someStale;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.textContaining('not live'), findsNothing);
    await _shot(t, 'b2-board-live-again');
  });

  testWidgets('C: restart offline from the device store: saved board and Safety', (t) async {
    // First run online, saving into the phone's real storage.
    final device = await _deviceStore();
    await device.setString(PrefKeys.activeMatchId, rizalMemorialId);
    await _launch(
      t,
      prefs: device,
      store: SavedCopyStore(device, clock: () => _now),
    );
    await t.tap(_tab('Safety'));
    await _waitFor(t, find.textContaining('Assessed')); // saved for the restart
    await t.tap(_tab('Dashboard'));
    await t.pumpAndSettle();

    // "Restart": a new app over the same device storage, server unreachable.
    await t.pumpWidget(const SizedBox());
    final again = SharedPreferencesStore(await SharedPreferences.getInstance());
    final api = await _launch(
      t,
      prefs: again,
      store: SavedCopyStore(again, clock: () => _now),
      scenario: MockScenario.offline,
    );
    expect(find.text('Rizal Memorial Stadium, Manila'), findsOneWidget);
    expect(find.textContaining('not live'), findsOneWidget);
    expect(find.byType(ErrorState), findsNothing);
    await _shot(t, 'c1-restart-offline-board');

    await t.tap(_tab('Safety'));
    await _waitFor(t, find.text('NOT CURRENT'));
    expect(find.textContaining('not live'), findsOneWidget);
    expect(find.text('NOT CURRENT'), findsWidgets);
    await _shot(t, 'c2-restart-offline-safety');

    api.scenario = MockScenario.allCurrent;
    // The banner's Try again (the lightning card offline has its own).
    await t.tap(
      find.descendant(of: find.byType(NoticeBanner), matching: find.text('Try again')),
    );
    await _waitFor(t, find.textContaining('not live'), gone: true);
    expect(find.textContaining('not live'), findsNothing);
    await _shot(t, 'c3-safety-back-online');
  });

  testWidgets('D: redesign follow-ups: sources count, credit, 24 h trend, suggestions, copy', (
    t,
  ) async {
    final prefs = MemoryPreferences({
      PrefKeys.activeMatchId: rizalMemorialId,
      PrefKeys.chatRole: 'coach',
    });
    final api = await _launch(
      t,
      prefs: prefs,
      store: SavedCopyStore(prefs, clock: () => _now),
      scenario: MockScenario.someStale,
    );
    // S2 and S3 on the board.
    expect(find.textContaining('sources current'), findsOneWidget);
    expect(find.textContaining('Open-Meteo.com'), findsWidgets);
    await _shot(t, 'd1-board');

    // S7: the longest range asks the backend for 24 hours once.
    final range = find.byWidgetPredicate(
      (w) => w is DropdownMenu && w.label is Text && (w.label! as Text).data == 'Range',
    );
    await t.scrollUntilVisible(range, 200, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(range);
    await t.pumpAndSettle();
    await t.tap(range);
    await t.pumpAndSettle();
    await t.tap(find.text('Kickoff to +24 h').hitTestable().last);
    await t.pumpAndSettle();
    // The mock answers after its device latency: let the request land.
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(api.weatherQueries, contains((hours: 24, hoursBefore: 6)));
    await _shot(t, 'd2-trend-24h');

    // S8 and S5 in Ask Pitchy.
    await t.tap(_tab('Ask Pitchy'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Start chatting'));
    await t.tap(find.text('Start chatting'));
    await t.pumpAndSettle();
    // S8 is the existing "Try asking" list (no second set of chips).
    expect(find.text('Try asking'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    await _shot(t, 'd3-chat-suggestions');
    const question = 'How current is the weather data?';
    await t.enterText(find.byType(TextField), question);
    await t.pump();
    await t.tap(find.byTooltip('Send question'));
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.byTooltip('Copy reply'), findsOneWidget);
    await t.tap(find.byTooltip('Copy reply'));
    // The real clipboard answers asynchronously; then the snackbar slides in.
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Reply copied'), findsOneWidget);
    final copied = await Clipboard.getData(Clipboard.kTextPlain);
    expect(copied?.text, isNotEmpty);
    await _shot(t, 'd4-chat-reply-copied');
  });
}
