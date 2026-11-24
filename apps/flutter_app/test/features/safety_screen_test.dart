import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/app.dart';
import 'package:pitchy/core/config/app_config.dart';
import 'package:pitchy/core/errors/api_failure.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/core/theme/app_theme.dart';
import 'package:pitchy/features/safety/safety_cards.dart';
import 'package:pitchy/features/safety/safety_level.dart';
import 'package:pitchy/shared/models/assessment.dart';
import 'package:pitchy/shared/models/lightning.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';
import 'package:pitchy/shared/widgets/data_state_badge.dart';

import '../app_harness.dart';
import '../helpers.dart';

/// Counts the live lightning requests.
class _CountingApi extends MockPitchyApi {
  _CountingApi({super.safety}) : super(clock: () => testNow, latency: Duration.zero);

  int lightningCalls = 0;

  @override
  Future<VenueLightning> getLightning(String matchContextId) {
    lightningCalls++;
    return super.getLightning(matchContextId);
  }
}

/// Serves the heatBelow assessment (no lightning level) with a live reading
/// that found lightning: the live level then differs from the assessment's.
class _LiveDiffersApi extends MockPitchyApi {
  _LiveDiffersApi() : super(clock: () => testNow, latency: Duration.zero);

  @override
  Future<VenueLightning> getLightning(String matchContextId) async => VenueLightning.fromJson(
    lightningJson(
      now: testNow,
      kickoff: safetyKickoff(SafetyScenario.lightningNear, testNow),
      scenario: SafetyScenario.lightningNear,
    ),
  );
}

/// The assessment the mock serves, parsed with the app's own model, so tests
/// compare against the backend's words instead of retyping them.
SafetyAssessment _fixture(SafetyScenario s) => SafetyAssessment.fromJson(
  assessmentJson(now: testNow, kickoff: safetyKickoff(s, testNow), scenario: s),
);

Future<MockPitchyApi> _pump(
  WidgetTester tester, {
  SafetyScenario safety = SafetyScenario.heatBelow,
  MockPitchyApi? api,
  Size size = const Size(390, 3200),
  bool withMatch = true,
  Duration latency = Duration.zero,
  bool settle = true,
  double textScale = 1,
  String location = Routes.safety,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final backend = api ?? MockPitchyApi(safety: safety, clock: () => testNow, latency: latency);
  await tester.pumpWidget(
    PitchyApp(
      config: AppConfig(apiBaseUrl: Uri.parse('https://api.example.test'), useMocks: true),
      info: testInfo,
      api: backend,
      preferences: MemoryPreferences(withMatch ? withActiveMatch() : null),
      initialLocation: location,
      clock: () => testNow,
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return backend;
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Finder _pillIn(Finder within) =>
    find.descendant(of: within, matching: find.byType(SafetyLevelPill));

Color _pillColour(WidgetTester tester, Finder pill) {
  final box = tester.widget<Container>(
    find.descendant(of: pill, matching: find.byType(Container)).first,
  );
  return (box.decoration! as BoxDecoration).color!;
}

Finder _card(String title) => find.ancestor(
  of: find.descendant(of: find.byType(HazardCard), matching: find.text(title)).first,
  matching: find.byType(HazardCard),
);

void main() {
  setUpAll(loadAppFonts);

  group('navigation', () {
    testWidgets('Safety is the second tab and opens the Safety screen', (tester) async {
      await _pump(tester, location: Routes.dashboard, size: const Size(390, 844));
      final labels = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((d) => d.label)
          .toList();
      expect(labels, ['Dashboard', 'Safety', 'PitChyAT']);
      await tester.tap(_tab('Safety'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Safety')),
        findsOneWidget,
      );
      expect(find.textContaining('Assessed '), findsOneWidget);
    });

    testWidgets('no active match shows the empty state with one action', (tester) async {
      await _pump(tester, withMatch: false, size: const Size(390, 844));
      expect(find.text('No match set up'), findsOneWidget);
      expect(find.text('Set up a match'), findsOneWidget);
    });
  });

  group('heat card', () {
    testWidgets('heatBelow: level, WBGT, age group, top-level message, rules, footer', (
      tester,
    ) async {
      await _pump(tester);
      final a = _fixture(SafetyScenario.heatBelow);
      final heat = a.indicators.first;
      expect(find.text(heat.level!.label), findsOneWidget);
      expect(find.text('WBGT (forecast estimate)'), findsOneWidget);
      expect(find.text('29.9 °C'), findsOneWidget);
      expect(find.text('Heat levels: Senior'), findsOneWidget);
      final officials = a.limitations.firstWhere((l) => l.code == 'OFFICIALS_DECIDE');
      expect(find.text(officials.message), findsOneWidget);
      expect(find.text('Rules: ${a.ruleVersion}'), findsOneWidget);
      expect(find.text('Pitchy supports the decision. Match officials make it.'), findsOneWidget);
      expect(find.text(heat.level!.action), findsOneWidget);
      expect(find.text(heat.decidedBy!), findsWidgets);
      expect(find.text('Who decides'), findsWidgets);
      expect(find.text('DATA AVAILABLE'), findsOneWidget);
      expect(find.text('NO DATA'), findsNWidgets(2));
      expect(find.byKey(const ValueKey(Hazard.heat)), findsOneWidget);
    });

    testWidgets('coolingBreaks: warning colour with an icon, and the worked-out details', (
      tester,
    ) async {
      await _pump(tester, safety: SafetyScenario.coolingBreaks);
      final a = _fixture(SafetyScenario.coolingBreaks);
      final pill = _pillIn(_card('Heat'));
      expect(pill, findsOneWidget);
      expect(_pillColour(tester, pill), tester.element(pill).safetyColors.warning);
      expect(
        find.descendant(of: pill, matching: find.byIcon(Icons.warning_amber_rounded)),
        findsOneWidget,
      );
      expect(find.text('Used for the level'), findsNothing);
      await tester.tap(find.text('How this was worked out').first);
      await tester.pumpAndSettle();
      expect(find.text('Measurement times'), findsOneWidget);
      expect(find.text('Used for the level'), findsOneWidget);
      expect(find.text('Inputs'), findsOneWidget);
      expect(find.text('Air temperature (temperature_2m): 34.2 °C'), findsOneWidget);
      expect(find.textContaining('Open-Meteo · retrieved '), findsWidgets);
      expect(find.text('Rule notes'), findsOneWidget);
      expect(find.text(a.indicators.first.notices.first.text), findsOneWidget);
    });

    testWidgets('youth shows the Under-20 level set', (tester) async {
      await _pump(tester, safety: SafetyScenario.youth);
      expect(find.text('Heat levels: Under-20 or younger'), findsOneWidget);
    });

    testWidgets('heatMissing: No level, and the MISSING_INPUT messages need no tap', (
      tester,
    ) async {
      await _pump(tester, safety: SafetyScenario.heatMissing);
      final a = _fixture(SafetyScenario.heatMissing);
      expect(find.descendant(of: _card('Heat'), matching: find.text('No level')), findsOneWidget);
      final missing = a.indicators.first.limitations.where((l) => l.code == 'MISSING_INPUT');
      expect(missing, isNotEmpty);
      for (final l in missing) {
        expect(find.text(l.message), findsOneWidget);
      }
    });

    testWidgets('rulesDraft: banner with the backend message', (tester) async {
      await _pump(tester, safety: SafetyScenario.rulesDraft);
      final a = _fixture(SafetyScenario.rulesDraft);
      final message = a.limitations.firstWhere((l) => l.code == 'RULES_NOT_APPROVED').message;
      expect(find.text('Rules not approved yet'), findsOneWidget);
      expect(find.text(message), findsOneWidget);
    });

    testWidgets('official notices are plain text with their label line', (tester) async {
      await _pump(tester);
      expect(find.text('Official notices'), findsOneWidget);
      expect(find.text('Official information, shown as issued.'), findsOneWidget);
      expect(find.text('SYNTHETIC: Heat advisory for Metro Manila'), findsOneWidget);
      expect(find.textContaining('Valid until '), findsOneWidget);
    });
  });

  group('lightning', () {
    testWidgets('lightningNear: live block, procedure, note, attribution, danger colour', (
      tester,
    ) async {
      await _pump(tester, safety: SafetyScenario.lightningNear);
      final a = _fixture(SafetyScenario.lightningNear);
      final lightning = a.indicators[1];
      final pill = _pillIn(_card('Lightning'));
      expect(pill, findsOneWidget);
      expect(_pillColour(tester, pill), tester.element(pill).safetyColors.danger);
      expect(
        find.descendant(of: pill, matching: find.byIcon(Icons.warning)),
        findsOneWidget,
      );
      expect(find.text('3 flashes within 40 km in the last 5 min'), findsOneWidget);
      expect(find.text('Nearest 8.2 km'), findsOneWidget);
      expect(find.textContaining('Latest '), findsOneWidget);
      expect(find.textContaining('Lightning detected nearby'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('3.'), findsOneWidget);
      for (final step in lightning.procedure) {
        expect(find.text(step), findsOneWidget);
      }
      expect(find.textContaining('Live lightning detection near the stadium'), findsOneWidget);
      expect(find.text('Powered by Vaisala Xweather'), findsOneWidget);
      expect(find.byType(DataStateBadge), findsOneWidget);
      expect(find.text('CURRENT'), findsOneWidget);
    });

    testWidgets('a live level newer than the assessment is shown with its own time', (
      tester,
    ) async {
      await _pump(tester, api: _LiveDiffersApi());
      final lightning = _card('Lightning');
      expect(find.descendant(of: lightning, matching: find.text('No level')), findsOneWidget);
      expect(
        find.descendant(of: lightning, matching: find.textContaining('Live check (')),
        findsOneWidget,
      );
      final pills = _pillIn(lightning);
      final danger = tester.element(lightning).safetyColors.danger;
      expect(
        [for (final e in pills.evaluate()) _pillColour(tester, find.byWidget(e.widget))],
        contains(danger),
        reason: 'the live level keeps its fixed colour',
      );
    });

    testWidgets('lightningStale: stale pill with its word, values not shown as current', (
      tester,
    ) async {
      await _pump(tester, safety: SafetyScenario.lightningStale);
      expect(find.text('STALE'), findsOneWidget);
      expect(find.text('CURRENT'), findsNothing);
      expect(find.text('Not current. Last reading:'), findsOneWidget);
      expect(find.text('1 flash within 40 km in the last 5 min'), findsOneWidget);
    });

    testWidgets('outside the live window the block names the window', (tester) async {
      await _pump(tester);
      expect(find.textContaining('Live checks run from '), findsOneWidget);
      expect(find.text('Not checked yet'), findsOneWidget);
    });

    testWidgets('notReady: Not available yet with no retry; live lightning still shows', (
      tester,
    ) async {
      await _pump(tester, safety: SafetyScenario.notReady);
      expect(find.text('Not available yet'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Lightning near the venue'), findsOneWidget);
      expect(find.text('Live lightning check'), findsOneWidget);
      expect(find.text('Powered by Vaisala Xweather'), findsOneWidget);
    });

    testWidgets('a failed live check keeps the assessment and offers Try again', (tester) async {
      final api = _FailingLightningApi();
      await _pump(tester, api: api);
      expect(find.textContaining('Assessed '), findsOneWidget);
      expect(find.textContaining('Live check unavailable'), findsOneWidget);
      api.fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Live check unavailable'), findsNothing);
      expect(find.text('Powered by Vaisala Xweather'), findsOneWidget);
    });
  });

  group('review follow-up', () {
    testWidgets('lightning card order: level, live check, who decides, limitations', (
      tester,
    ) async {
      await _pump(tester, safety: SafetyScenario.lightningNear);
      double y(Finder f) => tester.getTopLeft(f.first).dy;
      Finder inCard(Finder f) => find.descendant(of: _card('Lightning'), matching: f);
      expect(y(inCard(find.text('Level'))), lessThan(y(inCard(find.text('Live lightning check')))));
      expect(
        y(inCard(find.text('Live lightning check'))),
        lessThan(y(inCard(find.text('What officials do')))),
      );
      expect(
        y(inCard(find.text('What officials do'))),
        lessThan(y(inCard(find.text('Who decides')))),
      );
      expect(
        y(inCard(find.text('Nearest detected flash (at assessment)'))),
        lessThan(y(inCard(find.text('Limitations')))),
      );
      expect(find.byKey(const ValueKey('safetyLiveSummary')), findsOneWidget);
      // Nearest distance leads the live detail.
      expect(y(find.text('Nearest 8.2 km')), lessThan(y(find.textContaining('3 flashes within'))));
    });

    testWidgets('no level: neutral pill, no "What officials do", "Who decides" instead', (
      tester,
    ) async {
      await _pump(tester, safety: SafetyScenario.heatMissing);
      final heat = _card('Heat');
      expect(find.descendant(of: heat, matching: find.byIcon(Icons.help_outline)), findsOneWidget);
      expect(find.descendant(of: heat, matching: find.text('What officials do')), findsNothing);
      expect(find.descendant(of: heat, matching: find.text('Who decides')), findsOneWidget);
      await tester.tap(find.text('How this was worked out').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Solar radiation (shortwave_radiation)'), findsWidgets);
    });

    testWidgets('draft rules: banner first, and a marker beside every level', (tester) async {
      await _pump(tester, safety: SafetyScenario.rulesDraft);
      expect(
        tester.getTopLeft(find.text('Rules not approved yet')).dy,
        lessThan(tester.getTopLeft(find.textContaining('Assessed ')).dy),
      );
      expect(find.text('Draft rules'), findsNWidgets(3));
    });

    testWidgets('a failed refresh keeps the last assessment, marked Not current', (
      tester,
    ) async {
      final api = _FailingAssessmentApi();
      await _pump(tester, api: api);
      expect(find.textContaining('Not current. Assessed'), findsNothing);
      final heatLevel = _fixture(SafetyScenario.heatBelow).indicators.first.level!.label;
      api.fail = true;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Couldn’t refresh the assessment'), findsOneWidget);
      expect(find.textContaining('Not current. Assessed 12:00 PM PHT.'), findsOneWidget);
      expect(find.text('NOT CURRENT'), findsNWidgets(3));
      expect(find.text(heatLevel), findsOneWidget);
      expect(find.text('Try again'), findsWidgets);
      api.fail = false;
      await tester.tap(find.text('Try again').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Not current. Assessed'), findsNothing);
      expect(find.text('NOT CURRENT'), findsNothing);
    });
  });

  testWidgets('rainfall card: No level and the NO_APPROVED_RULE message', (tester) async {
    await _pump(tester);
    final a = _fixture(SafetyScenario.heatBelow);
    final rain = a.indicators.firstWhere((i) => i.hazard == Hazard.rainfall);
    expect(find.descendant(of: _card('Rainfall'), matching: find.text('No level')), findsOneWidget);
    final message = rain.limitations.firstWhere((l) => l.code == 'NO_APPROVED_RULE').message;
    expect(find.text(message), findsOneWidget);
    expect(find.text('NO DATA'), findsWidgets);
  });

  testWidgets('skeleton cards land where the loaded collapsed cards are (heatBelow)', (
    tester,
  ) async {
    await _pump(
      tester,
      latency: const Duration(milliseconds: 300),
      settle: false,
      size: const Size(390, 3200),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(SafetySkeleton), findsOneWidget);
    final skeleton = [
      for (final e in find.byType(HazardCardSkeleton).evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ];
    final headerSkeleton = tester.getRect(find.byType(SafetyHeaderSkeleton));
    expect(skeleton, hasLength(3));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(SafetySkeleton), findsNothing);
    final loaded = [
      for (final e in find.byType(HazardCard).evaluate()) tester.getRect(find.byWidget(e.widget)),
    ];
    final header = tester.getRect(find.byType(Card).first);
    expect(loaded, hasLength(3));
    expect((header.height - headerSkeleton.height).abs(), lessThan(1.5), reason: 'header');
    for (var n = 0; n < 3; n++) {
      expect((loaded[n].top - skeleton[n].top).abs(), lessThan(1.5), reason: 'top of card $n');
      expect(
        (loaded[n].height - skeleton[n].height).abs(),
        lessThan(1.5),
        reason: 'height of card $n',
      );
    }
  });

  group('large text on a phone', () {
    Future<void> scrollThrough(WidgetTester tester) async {
      for (var n = 0; n < 12; n++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'after scrolling $n');
      }
    }

    for (final scenario in [SafetyScenario.lightningNear, SafetyScenario.coolingBreaks]) {
      testWidgets('no overflow at 1.6x (${scenario.name}), expanders open', (tester) async {
        await _pump(tester, safety: scenario, size: const Size(360, 800), textScale: 1.6);
        expect(tester.takeException(), isNull);
        for (final e in find.text('How this was worked out').evaluate()) {
          final f = find.byWidget(e.widget);
          await tester.ensureVisible(f);
          await tester.pump();
          await tester.tap(f);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);
      });
    }
  });

  group('auto-refresh', () {
    testWidgets('asks again after the period while the tab is visible', (tester) async {
      final api = _CountingApi(safety: SafetyScenario.lightningNear);
      await _pump(tester, api: api, size: const Size(390, 844));
      expect(api.lightningCalls, 1);
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(api.lightningCalls, 2);
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(api.lightningCalls, 3);
    });

    testWidgets('does not ask while another tab is selected, and resumes on return', (
      tester,
    ) async {
      final api = _CountingApi(safety: SafetyScenario.lightningNear);
      await _pump(tester, api: api, size: const Size(390, 844));
      await tester.tap(_tab('PitChyAT'));
      await tester.pumpAndSettle();
      final before = api.lightningCalls;
      await tester.pump(const Duration(seconds: 130));
      await tester.pumpAndSettle();
      expect(api.lightningCalls, before);
      await tester.tap(_tab('Safety'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(api.lightningCalls, greaterThan(before));
    });

    testWidgets('does not ask outside the live window', (tester) async {
      final api = _CountingApi();
      await _pump(tester, api: api, size: const Size(390, 844));
      expect(api.lightningCalls, 1);
      await tester.pump(const Duration(seconds: 180));
      expect(api.lightningCalls, 1);
    });

    testWidgets('does not ask while the app is in the background', (tester) async {
      final api = _CountingApi(safety: SafetyScenario.lightningNear);
      await _pump(tester, api: api, size: const Size(390, 844));
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump(const Duration(seconds: 130));
      expect(api.lightningCalls, 1);
      for (final s in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(api.lightningCalls, 2);
    });
  });

  test('the colour logic is only in safety_level.dart', () {
    expect(safetyToneOf('cooling_breaks_required'), SafetyTone.warning);
    expect(safetyToneOf('within_30_second_distance'), SafetyTone.danger);
    expect(safetyToneOf('anything_else'), isNull);
  });
}

class _FailingLightningApi extends MockPitchyApi {
  _FailingLightningApi() : super(clock: () => testNow, latency: Duration.zero);

  bool fail = true;

  @override
  Future<VenueLightning> getLightning(String matchContextId) {
    if (fail) throw const NetworkFailure();
    return super.getLightning(matchContextId);
  }
}

class _FailingAssessmentApi extends MockPitchyApi {
  _FailingAssessmentApi() : super(clock: () => testNow, latency: Duration.zero);

  bool fail = false;

  @override
  Future<SafetyAssessment> getAssessment(String matchContextId) {
    if (fail) throw const NetworkFailure();
    return super.getAssessment(matchContextId);
  }
}
