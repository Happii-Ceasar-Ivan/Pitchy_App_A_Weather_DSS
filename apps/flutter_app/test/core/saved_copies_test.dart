import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitchy/core/errors/api_failure.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/core/storage/saved_copies.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 23, 4);
  late DateTime now;
  late MemoryPreferences prefs;

  SavedCopyStore open() => SavedCopyStore(prefs, clock: () => now);

  setUp(() {
    now = t0;
    prefs = MemoryPreferences();
  });

  group('SavedCopyStore', () {
    test('saves a reply with the time it was received and reads it back', () async {
      final store = open();
      await store.put('m1', SavedKind.weatherStatus, {'a': 1});

      final copy = store.get('m1', SavedKind.weatherStatus);
      expect(copy!.body, {'a': 1});
      expect(copy.savedAt, t0);
      expect(store.get('m1', SavedKind.alerts), isNull);
      expect(store.get('m2', SavedKind.weatherStatus), isNull);
    });

    test('survives a restart (reads what an earlier instance wrote)', () async {
      await open().put('m1', SavedKind.alerts, {'x': 'y'});
      expect(open().get('m1', SavedKind.alerts)!.body, {'x': 'y'});
    });

    test('a newer reply replaces the older copy', () async {
      final store = open();
      await store.put('m1', SavedKind.weather, {'v': 1});
      now = t0.add(const Duration(minutes: 5));
      await store.put('m1', SavedKind.weather, {'v': 2});

      final copy = store.get('m1', SavedKind.weather)!;
      expect(copy.body, {'v': 2});
      expect(copy.savedAt, now);
    });

    test('copies older than 14 days are never returned and are purged', () async {
      final store = open();
      await store.put('m1', SavedKind.weather, {'v': 1});
      now = t0.add(const Duration(days: 13));
      await store.put('m1', SavedKind.alerts, {'v': 2});

      now = t0.add(const Duration(days: 14, seconds: 1));
      expect(store.get('m1', SavedKind.weather), isNull, reason: 'expired on read');
      expect(store.get('m1', SavedKind.alerts), isNotNull);

      await store.purgeExpired();
      expect(open().get('m1', SavedKind.weather), isNull, reason: 'gone from the device');
      expect(open().get('m1', SavedKind.alerts), isNotNull);
    });

    test('removeMatch deletes every copy for that match only', () async {
      final store = open();
      await store.put('m1', SavedKind.weather, {'v': 1});
      await store.put('m1', SavedKind.match, {'v': 1});
      await store.put('m2', SavedKind.weather, {'v': 2});

      await store.removeMatch('m1');
      expect(store.get('m1', SavedKind.weather), isNull);
      expect(store.get('m1', SavedKind.match), isNull);
      expect(open().get('m2', SavedKind.weather), isNotNull);
    });

    test('keepOnly drops copies of every other match', () async {
      final store = open();
      await store.put('m1', SavedKind.weather, {'v': 1});
      await store.put('m2', SavedKind.weather, {'v': 2});

      await store.keepOnly('m2');
      expect(open().get('m1', SavedKind.weather), isNull);
      expect(open().get('m2', SavedKind.weather), isNotNull);
    });

    test('a damaged stored value is dropped instead of crashing', () async {
      prefs = MemoryPreferences({SavedCopyStore.prefKey: '{not json'});
      final store = open();
      expect(store.get('m1', SavedKind.weather), isNull);
      await store.put('m1', SavedKind.weather, {'v': 1});
      expect(open().get('m1', SavedKind.weather)!.body, {'v': 1});
    });

    test('stores only under its own key (never chat, token or other prefs)', () async {
      final store = open();
      await store.put('m1', SavedKind.assessment, {'v': 1});
      final stored = jsonDecode(prefs.getString(SavedCopyStore.prefKey)!) as Map;
      expect(stored.keys, ['m1']);
      expect((stored['m1'] as Map).keys, ['assessment']);
      // There is no kind for chat or session data at all.
      expect(SavedKind.values.map((k) => k.name), [
        'match',
        'weatherStatus',
        'weather',
        'trend',
        'alerts',
        'assessment',
      ]);
    });
  });

  group('allowsSavedCopy', () {
    ApiError err(int status, ApiErrorCode code) =>
        ApiError(statusCode: status, code: code, message: 'x');

    test('only when the backend could not be reached or failed itself', () {
      expect(allowsSavedCopy(const NetworkFailure()), isTrue);
      expect(allowsSavedCopy(const TimeoutFailure()), isTrue);
      expect(allowsSavedCopy(err(500, ApiErrorCode.internalError)), isTrue);
      expect(allowsSavedCopy(err(503, ApiErrorCode.serviceUnavailable)), isTrue);
      expect(allowsSavedCopy(const ContractFailure('html', statusCode: 502)), isTrue);
    });

    test('never for a real answer from the backend', () {
      expect(allowsSavedCopy(err(404, ApiErrorCode.notFound)), isFalse);
      expect(allowsSavedCopy(err(401, ApiErrorCode.invalidSession)), isFalse);
      expect(allowsSavedCopy(err(429, ApiErrorCode.rateLimited)), isFalse);
      expect(allowsSavedCopy(err(422, ApiErrorCode.validationError)), isFalse);
      expect(allowsSavedCopy(err(501, ApiErrorCode.notImplemented)), isFalse);
      expect(allowsSavedCopy(const ContractFailure('bad field')), isFalse);
      expect(allowsSavedCopy(const ContractFailure('bad', statusCode: 200)), isFalse);
    });
  });
}
