import 'package:flutter_test/flutter_test.dart';
import 'package:pitchy/core/errors/api_failure.dart';
import 'package:pitchy/core/state/loadable.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/core/storage/saved_copies.dart';
import 'package:pitchy/features/dashboard/dashboard_controller.dart';
import 'package:pitchy/features/match_management/match_controller.dart';
import 'package:pitchy/features/safety/safety_controller.dart';
import 'package:pitchy/shared/models/alerts.dart';
import 'package:pitchy/shared/models/assessment.dart';
import 'package:pitchy/shared/models/match.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/services/mock/mock_pitchy_api.dart';

import '../helpers.dart';

/// DEC-13 in the controllers: a saved copy only when the server can't be
/// reached or failed itself; a fresh reply always wins.
void main() {
  const id = rizalMemorialId;
  final savedAt = testNow.subtract(const Duration(minutes: 40));
  late MemoryPreferences prefs;
  late SavedCopyStore store;

  /// A store holding a full set of copies saved 40 minutes ago.
  Future<SavedCopyStore> seeded() async {
    final s = SavedCopyStore(prefs, clock: () => savedAt);
    await s.put(id, SavedKind.match, matchContextJson(kickoff: testKickoff, created: savedAt));
    await s.put(
      id,
      SavedKind.weatherStatus,
      weatherStatusJson(MockScenario.allCurrent, now: savedAt, kickoff: testKickoff),
    );
    await s.put(id, SavedKind.weather, consolidatedWeatherJson(now: savedAt, kickoff: testKickoff));
    await s.put(id, SavedKind.alerts, alertsJson(now: savedAt));
    await s.put(id, SavedKind.assessment, assessmentJson(now: savedAt, kickoff: testKickoff));
    return SavedCopyStore(prefs, clock: () => testNow);
  }

  MockPitchyApi api(MockScenario s) =>
      MockPitchyApi(scenario: s, clock: () => testNow, latency: Duration.zero);

  setUp(() async {
    prefs = MemoryPreferences({PrefKeys.activeMatchId: id});
    store = await seeded();
  });

  group('dashboard', () {
    for (final scenario in [MockScenario.offline, MockScenario.serviceError]) {
      test('${scenario.name}: weather and alerts fall back to the saved copy', () async {
        final c = DashboardController(api: api(scenario), matchContextId: id, savedCopies: store);
        await c.load();

        final data = c.data as Failed<DashboardData>;
        expect(data.saved, isNotNull);
        expect(data.saved!.savedAt, savedAt);
        expect(data.saved!.value.status.matchContextId, id);
        final alerts = c.alerts as Failed;
        expect(alerts.saved, isNotNull);
      });
    }

    test('without a saved copy the error shows as before', () async {
      final empty = SavedCopyStore(MemoryPreferences());
      final c = DashboardController(
        api: api(MockScenario.offline),
        matchContextId: id,
        savedCopies: empty,
      );
      await c.load();
      expect((c.data as Failed).saved, isNull);
      expect((c.data as Failed).failure, isA<NetworkFailure>());
    });

    test('the board copy needs both halves', () async {
      await store.removeMatch(id);
      await store.put(
        id,
        SavedKind.weather,
        consolidatedWeatherJson(now: testNow, kickoff: testKickoff),
      );
      final c = DashboardController(
        api: api(MockScenario.offline),
        matchContextId: id,
        savedCopies: store,
      );
      await c.load();
      expect((c.data as Failed).saved, isNull);
    });

    test('a fresh reply replaces the saved copy', () async {
      final backend = api(MockScenario.offline);
      final c = DashboardController(api: backend, matchContextId: id, savedCopies: store);
      await c.load();
      expect(c.data, isA<Failed<DashboardData>>());

      backend.scenario = MockScenario.allCurrent;
      await c.load();
      expect(c.data, isA<Loaded<DashboardData>>());
      expect(c.alerts, isA<Loaded<VenueAlerts>>());
    });
  });

  group('safety', () {
    test('offline: the saved assessment is the not-current one, with its time', () async {
      final c = SafetyController(
        api: api(MockScenario.offline),
        matchContextId: id,
        savedCopies: store,
      );
      await c.load();
      expect(c.assessment, isA<Failed<SafetyAssessment>>());
      expect(c.notCurrentAssessment, isNotNull);
      expect(c.savedCopyAt, savedAt);
      c.dispose();
    });

    test('an assessment from this run is preferred over the device copy', () async {
      final backend = api(MockScenario.allCurrent);
      final c = SafetyController(api: backend, matchContextId: id, savedCopies: store);
      await c.load();
      backend.scenario = MockScenario.offline;
      await c.load();
      expect(c.notCurrentAssessment, isNotNull);
      expect(c.savedCopyAt, isNull, reason: 'shown from memory, not the device copy');
      c.dispose();
    });
  });

  group('match', () {
    test('offline at start: the saved match is offered, labelled as a copy', () async {
      final m = MatchController(
        api: api(MockScenario.offline),
        preferences: prefs,
        savedCopies: store,
      );
      await m.restore();
      final active = m.active as Failed<MatchContext?>;
      expect(active.saved!.value!.id, id);
      expect(m.showingSavedCopy, isTrue);
    });

    test('back online: the live match replaces the copy without a loading flash', () async {
      final backend = api(MockScenario.offline);
      final m = MatchController(api: backend, preferences: prefs, savedCopies: store);
      await m.restore();
      backend.scenario = MockScenario.allCurrent;
      final seen = <Loadable<MatchContext?>>[];
      m.addListener(() => seen.add(m.active));
      await m.restore();
      expect(seen.whereType<Loading<MatchContext?>>(), isEmpty);
      expect(m.active, isA<Loaded<MatchContext?>>());
      expect(m.showingSavedCopy, isFalse);
    });

    test('a match gone on the server (404) deletes its saved copies', () async {
      prefs = MemoryPreferences({PrefKeys.activeMatchId: 'gone'});
      final s = SavedCopyStore(prefs, clock: () => testNow);
      await s.put('gone', SavedKind.alerts, alertsJson(now: testNow));
      final m = MatchController(api: _NotFoundApi(), preferences: prefs, savedCopies: s);
      await m.restore();
      expect(m.active, isA<Loaded<MatchContext?>>());
      expect(s.get('gone', SavedKind.alerts), isNull);
    });
  });
}

class _NotFoundApi extends MockPitchyApi {
  _NotFoundApi() : super(latency: Duration.zero);

  @override
  Future<MatchContext> getMatchContext(String matchContextId) async =>
      throw ApiError.fromEnvelope(404, errorJson('NOT_FOUND', 'Not found.'));
}
