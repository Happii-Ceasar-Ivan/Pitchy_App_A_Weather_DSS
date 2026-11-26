// In-app updater (P-26, user's design 2026-11-26): download the release file
// for this device from this repository's GitHub release, check its SHA-256
// against SHA256SUMS.txt, and only then hand it to the system installer.
// GitHub is faked with MockClient; files go to a real temporary folder.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitchy/core/config/project_links.dart';
import 'package:pitchy/features/settings/update_check.dart';
import 'package:pitchy/features/settings/update_installer.dart';

const _download = '${ProjectLinks.repo}/releases/download/v1.1.0';
const _apkName = 'pitchy-1.1.0-android.apk';
const _exeName = 'pitchy-1.1.0-windows-setup.exe';

final _apk = utf8.encode('pretend APK bytes ' * 5000);
String _hex(List<int> bytes) => sha256.convert(bytes).toString();

class _FakePlatform implements UpdatePlatform {
  _FakePlatform(this.dir, {this.target = UpdateTarget.android});

  final Directory dir;
  @override
  final UpdateTarget target;
  final installed = <File>[];

  @override
  Future<Directory> downloadDirectory() async => dir;

  @override
  Future<HandOff> install(File file) async {
    installed.add(file);
    return HandOff.opened;
  }

  @override
  Stream<InstallReport> get reports => const Stream.empty();

  @override
  Future<void> quit() async {}
}

UpdateAvailable _update({List<int>? apk, bool sums = true, int? size}) => UpdateAvailable(
  version: '1.1.0',
  page: Uri.parse('${ProjectLinks.repo}/releases/tag/v1.1.0'),
  assets: [
    ReleaseAsset(
      name: _apkName,
      url: Uri.parse('$_download/$_apkName'),
      size: size ?? (apk ?? _apk).length,
    ),
    ReleaseAsset(name: _exeName, url: Uri.parse('$_download/$_exeName'), size: 10),
    if (sums)
      ReleaseAsset(name: 'SHA256SUMS.txt', url: Uri.parse('$_download/SHA256SUMS.txt'), size: 200),
  ],
);

/// A fake GitHub release: serves the checksum list and the APK (optionally
/// different bytes from the ones the checksum was made from).
MockClient _github({
  String? sums,
  List<int>? served,
  int apkStatus = 200,
  bool dropMidway = false,
  List<Uri>? seen,
}) => MockClient.streaming((request, _) async {
  seen?.add(request.url);
  if (request.url.path.endsWith('SHA256SUMS.txt')) {
    final body = sums ?? '${_hex(_apk)}  $_apkName\n${'0' * 64}  $_exeName\n';
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
  if (request.url.path.endsWith(_apkName)) {
    final bytes = served ?? _apk;
    if (dropMidway) {
      final controller = StreamController<List<int>>();
      controller.add(bytes.sublist(0, 1000));
      unawaited(
        Future(() {
          controller.addError(const SocketException('connection reset'));
          return controller.close();
        }),
      );
      return http.StreamedResponse(controller.stream, apkStatus);
    }
    // In chunks, like a real transfer.
    return http.StreamedResponse(
      Stream.fromIterable([
        for (var i = 0; i < bytes.length; i += 16 * 1024)
          bytes.sublist(i, (i + 16 * 1024).clamp(0, bytes.length)),
      ]),
      apkStatus,
    );
  }
  return http.StreamedResponse(const Stream.empty(), 404);
});

void main() {
  late Directory dir;
  late _FakePlatform platform;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pitchy_update_test');
    platform = _FakePlatform(dir);
  });
  tearDown(() => dir.delete(recursive: true));

  List<String> filesLeft() => [for (final f in dir.listSync()) f.uri.pathSegments.last];

  group('download', () {
    test('verified: the file is complete, named after the asset, with progress', () async {
      final progress = <int>[];
      final seen = <Uri>[];
      final installer = UpdateInstaller(
        platform: platform,
        client: _github(seen: seen),
      );
      final r = await installer.download(
        _update(),
        onProgress: (got, total) {
          expect(total, _apk.length);
          progress.add(got);
        },
      );
      expect(r, isA<Downloaded>());
      r as Downloaded;
      expect(r.file.readAsBytesSync(), _apk);
      expect(r.file.path, endsWith(_apkName));
      expect(r.sha256, _hex(_apk));
      expect(progress.first, 0);
      expect(progress.last, _apk.length);
      expect(filesLeft(), [_apkName]);
      // Only this repository's release files were requested.
      expect(seen.every((u) => u.toString().startsWith('$_download/')), isTrue);
      expect(platform.installed, isEmpty, reason: 'downloading never installs');
    });

    test('Windows picks the installer, not the APK', () async {
      final exe = utf8.encode('pretend installer');
      final installer = UpdateInstaller(
        platform: _FakePlatform(dir, target: UpdateTarget.windows),
        client: MockClient((r) async {
          if (r.url.path.endsWith('SHA256SUMS.txt')) {
            return http.Response('${_hex(exe)} *$_exeName\n', 200);
          }
          if (r.url.path.endsWith(_exeName)) return http.Response.bytes(exe, 200);
          return http.Response('', 404);
        }),
      );
      final u = _update();
      expect(installer.fileFor(u)?.name, _exeName);
      final r = UpdateAvailable(
        version: u.version,
        page: u.page,
        assets: [
          for (final a in u.assets)
            a.name == _exeName ? ReleaseAsset(name: a.name, url: a.url, size: exe.length) : a,
        ],
      );
      expect(await installer.download(r), isA<Downloaded>());
    });

    test('checksum mismatch: file deleted, nothing installed', () async {
      final tampered = [..._apk]..[10] ^= 1;
      final installer = UpdateInstaller(
        platform: platform,
        client: _github(served: tampered),
      );
      expect(await installer.download(_update()), isA<ChecksumMismatch>());
      expect(filesLeft(), isEmpty);
      expect(platform.installed, isEmpty);
    });

    test('more bytes than GitHub said: refused as a mismatch', () async {
      final installer = UpdateInstaller(
        platform: platform,
        client: _github(served: [..._apk, 1, 2, 3]),
      );
      expect(await installer.download(_update(apk: _apk)), isA<ChecksumMismatch>());
      expect(filesLeft(), isEmpty);
    });

    test('no SHA256SUMS.txt in the release: never downloaded', () async {
      final seen = <Uri>[];
      final installer = UpdateInstaller(
        platform: platform,
        client: _github(seen: seen),
      );
      expect(await installer.download(_update(sums: false)), isA<ChecksumMissing>());
      expect(seen, isEmpty);
    });

    test('SHA256SUMS.txt without this file: never downloaded', () async {
      final seen = <Uri>[];
      final installer = UpdateInstaller(
        platform: platform,
        client: _github(sums: '${'a' * 64}  other-file.apk\n', seen: seen),
      );
      expect(await installer.download(_update()), isA<ChecksumMissing>());
      expect(seen.where((u) => u.path.endsWith(_apkName)), isEmpty);
    });

    test('no network: download failed, nothing left', () async {
      final installer = UpdateInstaller(
        platform: platform,
        client: MockClient((_) async => throw const SocketException('offline')),
      );
      expect(await installer.download(_update()), isA<DownloadFailed>());
      expect(filesLeft(), isEmpty);
    });

    test('connection drops midway: download failed, partial file deleted', () async {
      final installer = UpdateInstaller(platform: platform, client: _github(dropMidway: true));
      expect(await installer.download(_update()), isA<DownloadFailed>());
      expect(filesLeft(), isEmpty);
    });

    test('a server error: download failed', () async {
      final installer = UpdateInstaller(platform: platform, client: _github(apkStatus: 500));
      expect(await installer.download(_update()), isA<DownloadFailed>());
    });

    test('fewer bytes than GitHub said: download failed', () async {
      final installer = UpdateInstaller(platform: platform, client: _github());
      expect(await installer.download(_update(size: _apk.length + 10)), isA<DownloadFailed>());
      expect(filesLeft(), isEmpty);
    });

    test('cancelled: nothing left, nothing installed', () async {
      var chunks = 0;
      final installer = UpdateInstaller(platform: platform, client: _github());
      final r = await installer.download(
        _update(),
        onProgress: (_, _) => chunks++,
        isCancelled: () => chunks > 2,
      );
      expect(r, isA<DownloadCancelled>());
      expect(filesLeft(), isEmpty);
      expect(platform.installed, isEmpty);
    });

    test('old update files are cleared first', () async {
      File('${dir.path}/pitchy-1.0.9-android.apk').writeAsStringSync('old');
      final installer = UpdateInstaller(platform: platform, client: _github());
      await installer.download(_update());
      expect(filesLeft(), [_apkName]);
    });

    test('a device with no installer: no file to download', () async {
      final installer = UpdateInstaller(platform: const NoUpdatePlatform(), client: _github());
      expect(installer.fileFor(_update()), isNull);
      expect(await installer.download(_update()), isA<NoFileForPlatform>());
    });
  });

  group('install', () {
    test('a verified file goes to the system installer', () async {
      final installer = UpdateInstaller(platform: platform, client: _github());
      final d = await installer.download(_update()) as Downloaded;
      expect(await installer.install(d), HandOff.opened);
      expect(platform.installed.single.path, d.file.path);
    });

    test('a file changed after the download is never handed over', () async {
      final installer = UpdateInstaller(platform: platform, client: _github());
      final d = await installer.download(_update()) as Downloaded;
      d.file.writeAsBytesSync([...d.file.readAsBytesSync()..[0] ^= 1]);
      expect(await installer.install(d), HandOff.failed);
      expect(platform.installed, isEmpty);
      expect(d.file.existsSync(), isFalse);
    });
  });

  group('SHA256SUMS.txt', () {
    final a = 'a' * 64;
    final b = 'B' * 64;

    test('sha256sum format, binary marker, CRLF, upper case', () {
      final sums = UpdateInstaller.parseChecksums('$a  one.apk\r\n$b *two.exe\n\n# note\n');
      expect(sums, {'one.apk': a, 'two.exe': 'b' * 64});
    });

    test('junk lines are ignored', () {
      expect(UpdateInstaller.parseChecksums('abc  one.apk\n$a  ../one.apk\n$a\n'), isEmpty);
    });

    test('a name listed twice with different values is dropped', () {
      expect(UpdateInstaller.parseChecksums('$a  one.apk\n${'c' * 64}  one.apk\n'), isEmpty);
    });
  });

  group('release assets (untrusted GitHub reply)', () {
    Map<String, Object?> asset(String url, {String name = _apkName, Object size = 100}) => {
      'name': name,
      'browser_download_url': url,
      'size': size,
    };

    test('this repository\'s release download is kept', () {
      final a = ReleaseAsset.fromJson(asset('$_download/$_apkName'));
      expect(a?.url.toString(), '$_download/$_apkName');
      expect(a?.size, 100);
    });

    for (final (why, json) in [
      (
        'another host',
        asset('https://evil.example/Happii-Ceasar-Ivan/x/releases/download/v1/a.apk'),
      ),
      (
        'another repository',
        asset('https://github.com/someone/else/releases/download/v1.1.0/a.apk'),
      ),
      (
        'plain http',
        asset(
          'http://github.com/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS/releases/download/v1.1.0/a.apk',
        ),
      ),
      ('a dot-dot path', asset('$_download/../../../evil/a.apk')),
      ('a query', asset('$_download/$_apkName?x=1')),
      (
        'user info',
        asset(
          'https://me@github.com/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS/releases/download/v1.1.0/a.apk',
        ),
      ),
      ('not a download path', asset('${ProjectLinks.repo}/archive/main.zip')),
      ('a name with a slash', asset('$_download/$_apkName', name: '../a.apk')),
      ('a hidden name', asset('$_download/$_apkName', name: '.apk')),
      ('a huge file', asset('$_download/$_apkName', size: ReleaseAsset.maxBytes + 1)),
      ('no size', asset('$_download/$_apkName', size: 'big')),
    ]) {
      test('$why: dropped', () => expect(ReleaseAsset.fromJson(json), isNull));
    }

    test('the checker keeps only safe assets', () async {
      final checker = UpdateChecker(
        installedVersion: '1.0.0',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'tag_name': 'v1.1.0',
              'html_url': '${ProjectLinks.repo}/releases/tag/v1.1.0',
              'assets': [
                asset('$_download/$_apkName'),
                asset('https://evil.example/a.apk', name: 'evil.apk'),
                'not an object',
              ],
            }),
            200,
          ),
        ),
      );
      final r = await checker.check() as UpdateAvailable;
      expect(r.assets.map((a) => a.name), [_apkName]);
    });
  });
}
