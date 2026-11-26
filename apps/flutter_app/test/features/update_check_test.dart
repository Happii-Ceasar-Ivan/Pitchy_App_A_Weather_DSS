// Check for updates (P-08 option A, user 2026-11-26): ask GitHub for the
// newest published release and compare it with the installed version. Never
// downloads or installs anything; never claims "up to date" when it couldn't
// check.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitchy/core/config/project_links.dart';
import 'package:pitchy/features/settings/update_check.dart';

import '../app_harness.dart';

const _page = '${ProjectLinks.repo}/releases/tag/v1.1.0';

http.Response _release(String tag, {String url = _page}) => http.Response(
  jsonEncode({'tag_name': tag, 'html_url': url, 'name': 'Pitchy $tag', 'draft': false}),
  200,
  headers: {'content-type': 'application/json'},
);

UpdateChecker _checker(http.Response Function(http.Request) reply, {String installed = '1.0.0'}) =>
    UpdateChecker(client: MockClient((r) async => reply(r)), installedVersion: installed);

void main() {
  group('UpdateChecker', () {
    test('asks GitHub for the latest release, with no credentials', () async {
      late http.Request seen;
      await _checker((r) {
        seen = r;
        return _release('v1.0.0');
      }).check();
      expect(seen.url, ProjectLinks.latestRelease);
      expect(seen.method, 'GET');
      expect(seen.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
    });

    test('a newer tag is an update, with its release page', () async {
      final r = await _checker((_) => _release('v1.1.0')).check();
      expect(r, isA<UpdateAvailable>());
      r as UpdateAvailable;
      expect(r.version, '1.1.0');
      expect(r.page, Uri.parse(_page));
    });

    for (final (installed, tag) in [
      ('1.0.0', 'v1.0.0'),
      ('1.0.0', '1.0.0'),
      ('1.2.0', 'v1.1.9'), // a development build ahead of the release
      ('1.10.0', 'v1.9.0'), // numbers, not text
    ]) {
      test('installed $installed, release $tag: up to date', () async {
        final r = await _checker((_) => _release(tag), installed: installed).check();
        expect(r, isA<UpToDate>());
      });
    }

    test('1.9.0 installed, v1.10.0 released: an update (numbers, not text)', () async {
      final r = await _checker((_) => _release('v1.10.0'), installed: '1.9.0').check();
      expect(r, isA<UpdateAvailable>());
    });

    test('no release published yet (404)', () async {
      final r = await _checker((_) => http.Response('{"message":"Not Found"}', 404)).check();
      expect(r, isA<NoReleaseYet>());
    });

    for (final status in [403, 429]) {
      test('GitHub limiting checks ($status)', () async {
        final r = await _checker((_) => http.Response('{}', status)).check();
        expect(r, isA<CheckFailed>());
        expect((r as CheckFailed).limited, isTrue);
      });
    }

    test('no network: could not check (never "up to date")', () async {
      final r = await UpdateChecker(
        client: MockClient((_) async => throw http.ClientException('offline')),
        installedVersion: '1.0.0',
      ).check();
      expect(r, isA<CheckFailed>());
      expect((r as CheckFailed).limited, isFalse);
    });

    for (final (name, response) in [
      ('a tag that is not a version', _release('nightly')),
      ('a server error', http.Response('oops', 500)),
      ('not JSON', http.Response('<html>', 200)),
    ]) {
      test('$name: could not check', () async {
        expect(await _checker((_) => response).check(), isA<CheckFailed>());
      });
    }

    test('a release page outside this repository is never linked', () async {
      final r = await _checker(
        (_) => _release('v2.0.0', url: 'https://evil.example/pitchy.apk'),
      ).check();
      expect(r, isA<UpdateAvailable>());
      expect((r as UpdateAvailable).page, Uri.parse('${ProjectLinks.repo}/releases'));
    });
  });

  group('dialog', () {
    Future<void> open(WidgetTester tester, UpdateChecker checker) async {
      await pumpPitchyApp(tester, updates: checker);
      await tester.tap(find.byTooltip('Quick settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
    }

    testWidgets('an update: the version and a button to its release page', (tester) async {
      await open(tester, _checker((_) => _release('v1.1.0')));
      expect(find.text('Pitchy 1.1.0 is available. You have 1.0.0.'), findsOneWidget);
      expect(find.text('Open download page'), findsOneWidget);
    });

    testWidgets('up to date', (tester) async {
      await open(tester, _checker((_) => _release('v1.0.0')));
      expect(find.text('You have the latest version, Pitchy 1.0.0.'), findsOneWidget);
      expect(find.text('Open download page'), findsNothing);
    });

    testWidgets('nothing published yet', (tester) async {
      await open(tester, _checker((_) => http.Response('{}', 404)));
      expect(
        find.text('No version has been published yet. You have Pitchy 1.0.0.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed check says so, and can be tried again', (tester) async {
      var calls = 0;
      await open(
        tester,
        _checker((_) {
          calls++;
          return calls == 1 ? http.Response('oops', 500) : _release('v1.0.0');
        }),
      );
      expect(
        find.text('Couldn’t check for updates. Check your connection and try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('You have the latest version, Pitchy 1.0.0.'), findsOneWidget);
    });

    testWidgets('GitHub limiting checks', (tester) async {
      await open(tester, _checker((_) => http.Response('{}', 403)));
      expect(
        find.text('GitHub is limiting update checks right now. Try again in an hour.'),
        findsOneWidget,
      );
    });
  });
}
