// The update dialog and the check on app open (P-26, user's design
// 2026-11-26). GitHub is faked with MockClient; the installer is scripted, so
// nothing is downloaded or installed here (update_installer_test covers that).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/config/project_links.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/features/settings/update_check.dart';
import 'package:pitchy/features/settings/update_installer.dart';

import '../app_harness.dart';
import '../helpers.dart';

const _download = '${ProjectLinks.repo}/releases/download/v1.1.0';

http.Response _release(String tag) => http.Response(
  jsonEncode({
    'tag_name': tag,
    'html_url': '${ProjectLinks.repo}/releases/tag/$tag',
    'assets': [
      {
        'name': 'pitchy-1.1.0-android.apk',
        'browser_download_url': '$_download/pitchy-1.1.0-android.apk',
        'size': 40 * 1024 * 1024,
      },
      {
        'name': 'SHA256SUMS.txt',
        'browser_download_url': '$_download/SHA256SUMS.txt',
        'size': 200,
      },
    ],
  }),
  200,
);

UpdateChecker _checker(http.Response Function() reply, {void Function()? onCall}) => UpdateChecker(
  installedVersion: '1.0.0',
  client: MockClient((_) async {
    onCall?.call();
    return reply();
  }),
);

/// Plays back what a download and an install would do.
class _ScriptedInstaller implements UpdateInstaller {
  _ScriptedInstaller({
    this.target = UpdateTarget.android,
    this.outcome = const DownloadFailed(),
    this.handOffs = const [HandOff.opened],
  });

  @override
  final UpdateTarget target;
  DownloadOutcome outcome;
  List<HandOff> handOffs;

  /// When set, the download waits for it (to look at the progress).
  Completer<void>? gate;
  var downloads = 0;
  var installs = 0;
  var quits = 0;
  final _reports = StreamController<InstallReport>.broadcast();

  void report(InstallReport r) => _reports.add(r);

  @override
  UpdatePlatform get platform => const NoUpdatePlatform();

  @override
  ReleaseAsset? fileFor(UpdateAvailable u) =>
      target == UpdateTarget.none ? null : u.asset('pitchy-${u.version}-android.apk');

  @override
  Future<DownloadOutcome> download(
    UpdateAvailable update, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    downloads++;
    const total = 40 * 1024 * 1024;
    onProgress?.call(total ~/ 4, total);
    if (gate case final g?) await g.future;
    if (isCancelled?.call() ?? false) return const DownloadCancelled();
    return outcome;
  }

  @override
  Future<HandOff> install(Downloaded downloaded) async {
    installs++;
    return handOffs.length > 1 ? handOffs.removeAt(0) : handOffs.single;
  }

  @override
  Stream<InstallReport> get reports => _reports.stream;

  @override
  Future<void> quit() async => quits++;
}

final _verified = Downloaded(file: File('pitchy-1.1.0-android.apk'), sha256: 'a' * 64);

Future<void> _openCheck(
  WidgetTester tester,
  UpdateChecker checker,
  UpdateInstaller installer,
) async {
  await pumpPitchyApp(tester, updates: checker, updateInstaller: installer);
  await tester.tap(find.byTooltip('Quick settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Check for updates'));
  await tester.pumpAndSettle();
}

const _ask = 'There’s a new Pitchy (1.1.0). Would you like to update?';
const _stayOnline = 'Please stay connected to the internet while it updates.';

void main() {
  setUpAll(loadAppFonts);

  group('the offer', () {
    testWidgets('asks first, with the stay-connected note', (tester) async {
      final installer = _ScriptedInstaller();
      await _openCheck(tester, _checker(() => _release('v1.1.0')), installer);
      expect(find.text(_ask), findsOneWidget);
      expect(find.text(_stayOnline), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
      expect(installer.downloads, 0, reason: 'nothing downloads before the user says yes');
    });

    testWidgets('Later closes and downloads nothing', (tester) async {
      final installer = _ScriptedInstaller();
      await _openCheck(tester, _checker(() => _release('v1.1.0')), installer);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text(_ask), findsNothing);
      expect(installer.downloads, 0);
    });

    testWidgets('a device that can’t install itself gets the download page', (tester) async {
      await _openCheck(
        tester,
        _checker(() => _release('v1.1.0')),
        _ScriptedInstaller(target: UpdateTarget.none),
      );
      expect(find.text('There’s a new Pitchy (1.1.0). You have 1.0.0.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Open download page'), findsOneWidget);
      expect(find.text('Update'), findsNothing);
    });
  });

  group('updating', () {
    Future<_ScriptedInstaller> update(WidgetTester tester, _ScriptedInstaller installer) async {
      await _openCheck(tester, _checker(() => _release('v1.1.0')), installer);
      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await tester.pumpAndSettle();
      return installer;
    }

    testWidgets('shows progress, then Android’s prompt; never claims success', (tester) async {
      final installer = _ScriptedInstaller(outcome: _verified)..gate = Completer<void>();
      await update(tester, installer);
      expect(find.text('Downloading Pitchy 1.1.0… 10.0 of 40.0 MB'), findsOneWidget);
      expect(find.text(_stayOnline), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(bar.value, 0.25);
      installer.gate!.complete();
      await tester.pumpAndSettle();
      expect(installer.installs, 1);
      expect(
        find.textContaining('Follow Android’s prompt to install Pitchy 1.1.0.'),
        findsOneWidget,
      );
      expect(find.textContaining('signed with the same key'), findsOneWidget);
      expect(find.textContaining('is installed'), findsNothing);
    });

    testWidgets('the dialog can’t be dismissed while downloading; Cancel stops it', (tester) async {
      final installer = _ScriptedInstaller(outcome: _verified)..gate = Completer<void>();
      await update(tester, installer);
      await tester.tapAt(const Offset(5, 5)); // the barrier
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      installer.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(installer.installs, 0);
    });

    testWidgets('Android reports success: only then "installed"', (tester) async {
      final installer = await update(tester, _ScriptedInstaller(outcome: _verified));
      installer.report(const InstallReport(0));
      await tester.pumpAndSettle();
      expect(find.text('Android reports that Pitchy 1.1.0 is installed.'), findsOneWidget);
    });

    testWidgets('a different signing key: says why, offers the download page', (tester) async {
      final installer = await update(tester, _ScriptedInstaller(outcome: _verified));
      installer.report(const InstallReport(5, 'INSTALL_FAILED_UPDATE_INCOMPATIBLE'));
      await tester.pumpAndSettle();
      expect(find.text('Android didn’t install the update. Nothing changed.'), findsOneWidget);
      expect(find.textContaining('signed with a different key'), findsOneWidget);
      expect(find.text('Open download page'), findsOneWidget);
    });

    testWidgets('the user says no in Android’s prompt', (tester) async {
      final installer = await update(tester, _ScriptedInstaller(outcome: _verified));
      installer.report(const InstallReport(3));
      await tester.pumpAndSettle();
      expect(find.text('The update was cancelled. Nothing changed.'), findsOneWidget);
    });

    testWidgets('first time: allow installs from Pitchy, then Install', (tester) async {
      final installer = await update(
        tester,
        _ScriptedInstaller(outcome: _verified, handOffs: [HandOff.needsPermission, HandOff.opened]),
      );
      expect(find.text('Allow installs from Pitchy'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Install'));
      await tester.pumpAndSettle();
      expect(installer.installs, 2);
      expect(installer.downloads, 1, reason: 'the verified file is reused');
      expect(find.textContaining('Follow Android’s prompt'), findsOneWidget);
    });

    testWidgets('Windows: the installer opens and Pitchy closes', (tester) async {
      final installer = await update(
        tester,
        _ScriptedInstaller(target: UpdateTarget.windows, outcome: _verified),
      );
      expect(
        find.textContaining('The installer is opening. Pitchy will close now'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
      expect(installer.quits, 1);
    });

    for (final (outcome, message, retry) in [
      (
        const DownloadFailed(),
        'The download didn’t finish. Nothing was installed. Check your connection and try again.',
        true,
      ),
      (
        const ChecksumMismatch(),
        'The downloaded file didn’t match its published checksum, so Pitchy deleted it. '
            'Nothing was installed.',
        true,
      ),
      (
        const ChecksumMissing(),
        'This release has no published checksum for its file, so Pitchy won’t install it. '
            'You can get it from the download page.',
        false,
      ),
    ]) {
      testWidgets('${outcome.runtimeType}: says so, installs nothing', (tester) async {
        final installer = await update(tester, _ScriptedInstaller(outcome: outcome));
        expect(find.text('Update not installed'), findsOneWidget);
        expect(find.text(message), findsOneWidget);
        expect(installer.installs, 0);
        expect(find.text('Try again'), retry ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('Try again downloads again', (tester) async {
      final installer = await update(tester, _ScriptedInstaller());
      installer.outcome = _verified;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(installer.downloads, 2);
      expect(find.textContaining('Follow Android’s prompt'), findsOneWidget);
    });

    testWidgets('the installer won’t open: nothing installed', (tester) async {
      final installer = await update(
        tester,
        _ScriptedInstaller(outcome: _verified, handOffs: [HandOff.failed]),
      );
      expect(
        find.text('Pitchy couldn’t open the installer. Nothing was installed.'),
        findsOneWidget,
      );
      expect(installer.installs, 1);
    });
  });

  group('check on app open', () {
    testWidgets('a newer version: the prompt appears by itself', (tester) async {
      final (_, prefs) = await pumpPitchyApp(
        tester,
        updates: _checker(() => _release('v1.1.0')),
        updateInstaller: _ScriptedInstaller(),
        checkForUpdatesOnOpen: true,
      );
      expect(find.text(_ask), findsOneWidget);
      expect(prefs.getString(PrefKeys.lastUpdateCheck), testNow.toIso8601String());
    });

    testWidgets('up to date: nothing shown', (tester) async {
      await pumpPitchyApp(
        tester,
        updates: _checker(() => _release('v1.0.0')),
        checkForUpdatesOnOpen: true,
      );
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('at most once a day', (tester) async {
      var calls = 0;
      await pumpPitchyApp(
        tester,
        updates: _checker(() => _release('v1.1.0'), onCall: () => calls++),
        checkForUpdatesOnOpen: true,
        prefs: {
          PrefKeys.lastUpdateCheck: testNow.subtract(const Duration(hours: 20)).toIso8601String(),
        },
      );
      expect(calls, 0);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a day later it checks again', (tester) async {
      var calls = 0;
      await pumpPitchyApp(
        tester,
        updates: _checker(() => _release('v1.0.0'), onCall: () => calls++),
        checkForUpdatesOnOpen: true,
        prefs: {
          PrefKeys.lastUpdateCheck: testNow.subtract(const Duration(hours: 25)).toIso8601String(),
        },
      );
      expect(calls, 1);
    });

    testWidgets('a failed check stays quiet and is tried again next open', (tester) async {
      final (_, prefs) = await pumpPitchyApp(
        tester,
        updates: _checker(() => http.Response('oops', 500)),
        checkForUpdatesOnOpen: true,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(prefs.getString(PrefKeys.lastUpdateCheck), isNull);
    });
  });
}
