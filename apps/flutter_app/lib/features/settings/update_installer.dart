import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitType;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'update_check.dart';

/// Where this copy of Pitchy can install an update itself.
enum UpdateTarget {
  android,
  windows,

  /// Anything else (and tests by default): the dialog offers the download
  /// page instead.
  none,
}

/// The release file names the app looks for (P-26, user 2026-11-26). Every
/// release publishes exactly these, plus [checksums].
abstract final class ReleaseFiles {
  static String android(String version) => 'pitchy-$version-android.apk';
  static String windows(String version) => 'pitchy-$version-windows-setup.exe';

  /// One line per file, as `sha256sum` and the release checklist write it:
  /// `<64 hex digits><two spaces><file name>` (an optional `*` before the name
  /// is allowed).
  static const checksums = 'SHA256SUMS.txt';
}

/// What a download ended with. Only [Downloaded] can be installed.
sealed class DownloadOutcome {
  const DownloadOutcome();
}

/// The file is complete and its SHA-256 matches the published one.
class Downloaded extends DownloadOutcome {
  const Downloaded({required this.file, required this.sha256});

  final File file;

  /// Lower-case hex, the published value.
  final String sha256;
}

/// No network, a failed request, or the transfer stopped early.
class DownloadFailed extends DownloadOutcome {
  const DownloadFailed();
}

/// The release has no file for this platform.
class NoFileForPlatform extends DownloadOutcome {
  const NoFileForPlatform();
}

/// The release publishes no checksum for the file, so it is never installed.
class ChecksumMissing extends DownloadOutcome {
  const ChecksumMissing();
}

/// The file's SHA-256 (or size) differs from the published one. The file was
/// deleted.
class ChecksumMismatch extends DownloadOutcome {
  const ChecksumMismatch();
}

class DownloadCancelled extends DownloadOutcome {
  const DownloadCancelled();
}

/// What handing a verified file to the system installer did. None of these
/// means "installed": only Android's own report ([InstallReport]) can say so.
enum HandOff {
  /// Android is showing its install prompt / the Windows installer started.
  opened,

  /// Android: the user must allow installs from Pitchy first; the system
  /// screen for that was opened.
  needsPermission,

  /// The installer couldn't be opened (or the file failed its re-check).
  failed,
}

/// Android's final word on an install it was handed (PackageInstaller status).
/// For an update of Pitchy itself Android usually closes Pitchy before a
/// success can be reported, so normally only failures arrive.
class InstallReport {
  const InstallReport(this.status, [this.message]);

  /// PackageInstaller.STATUS_*: 0 success, 3 aborted (the user said no),
  /// 5 conflict and 7 incompatible (usually a different signing key).
  final int status;
  final String? message;

  bool get succeeded => status == 0;
  bool get cancelledByUser => status == 3;
  bool get signatureProblem => status == 5 || status == 7;
}

/// The device side of installing: where downloads go, and how a verified file
/// reaches the system installer.
abstract interface class UpdatePlatform {
  UpdateTarget get target;

  /// A directory only Pitchy uses for update files.
  Future<Directory> downloadDirectory();

  Future<HandOff> install(File file);

  /// Android's install reports (empty elsewhere).
  Stream<InstallReport> get reports;

  /// Windows: closes Pitchy so the installer can replace it.
  Future<void> quit();

  /// The platform this app is running on.
  static UpdatePlatform forThisDevice() {
    if (kIsWeb) return const NoUpdatePlatform();
    if (Platform.isAndroid) return AndroidUpdatePlatform();
    if (Platform.isWindows) return WindowsUpdatePlatform();
    return const NoUpdatePlatform();
  }
}

class NoUpdatePlatform implements UpdatePlatform {
  const NoUpdatePlatform();

  @override
  UpdateTarget get target => UpdateTarget.none;

  @override
  Future<Directory> downloadDirectory() => throw UnsupportedError('no installer here');

  @override
  Future<HandOff> install(File file) async => HandOff.failed;

  @override
  Stream<InstallReport> get reports => const Stream.empty();

  @override
  Future<void> quit() async {}
}

/// Android: `MainActivity.kt` writes the APK into a PackageInstaller session;
/// Android then shows its own prompt (and, the first time, asks the user to
/// allow installs from Pitchy). Android only installs it over this copy when
/// both are signed with the same release key (P-08 step 1).
class AndroidUpdatePlatform implements UpdatePlatform {
  AndroidUpdatePlatform() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'installStatus' && call.arguments is Map) {
        final args = call.arguments as Map;
        final status = args['status'];
        final message = args['message'];
        _reports.add(InstallReport(status is int ? status : 1, message is String ? message : null));
      }
    });
  }

  static const _channel = MethodChannel('ph.pitchy.pitchy/updater');
  final _reports = StreamController<InstallReport>.broadcast();

  @override
  UpdateTarget get target => UpdateTarget.android;

  @override
  Future<Directory> downloadDirectory() async {
    final cache = await _channel.invokeMethod<String>('cacheDir');
    if (cache == null) throw const FileSystemException('no cache directory');
    // MainActivity only installs files from this folder.
    return Directory('$cache${Platform.pathSeparator}updates').create(recursive: true);
  }

  @override
  Future<HandOff> install(File file) async {
    try {
      final reply = await _channel.invokeMethod<String>('install', {'path': file.path});
      return switch (reply) {
        'opened' => HandOff.opened,
        'needs_permission' => HandOff.needsPermission,
        _ => HandOff.failed,
      };
    } on PlatformException {
      return HandOff.failed;
    }
  }

  @override
  Stream<InstallReport> get reports => _reports.stream;

  @override
  Future<void> quit() async {}
}

/// Windows: runs the downloaded installer (its own window, its own prompts),
/// then Pitchy closes so the installer can replace its files.
class WindowsUpdatePlatform implements UpdatePlatform {
  @override
  UpdateTarget get target => UpdateTarget.windows;

  @override
  Future<Directory> downloadDirectory() =>
      Directory('${Directory.systemTemp.path}${Platform.pathSeparator}pitchy-update')
          .create(recursive: true);

  @override
  Future<HandOff> install(File file) async {
    try {
      await Process.start(file.path, const [], mode: ProcessStartMode.detached);
      return HandOff.opened;
    } on ProcessException {
      return HandOff.failed;
    }
  }

  @override
  Stream<InstallReport> get reports => const Stream.empty();

  @override
  Future<void> quit() => ServicesBinding.instance.exitApplication(AppExitType.required);
}

/// Downloads the release file for this platform from this repository's
/// GitHub release, checks its SHA-256 against the release's
/// [ReleaseFiles.checksums], and only then hands it to the system installer.
/// Nothing is installed after a failed, cancelled or mismatched download.
///
/// The checksum comes from the same release, so it catches broken or
/// altered downloads, not a compromised repository; Android's signature check
/// (same release key) is the second lock.
class UpdateInstaller {
  UpdateInstaller({required this.platform, http.Client? client})
    : _client = client ?? http.Client();

  final UpdatePlatform platform;
  final http.Client _client;

  /// No data for this long while downloading means the download failed.
  static const stallTimeout = Duration(seconds: 30);

  /// The checksum list is a few lines; anything bigger is refused.
  static const _maxChecksumBytes = 64 * 1024;

  UpdateTarget get target => platform.target;

  Stream<InstallReport> get reports => platform.reports;

  Future<void> quit() => platform.quit();

  /// The release file for this platform, if the release has it.
  ReleaseAsset? fileFor(UpdateAvailable update) => switch (platform.target) {
    UpdateTarget.android => update.asset(ReleaseFiles.android(update.version)),
    UpdateTarget.windows => update.asset(ReleaseFiles.windows(update.version)),
    UpdateTarget.none => null,
  };

  /// Downloads and verifies the file. [onProgress] gets bytes received and the
  /// expected total; [isCancelled] is checked as data arrives.
  Future<DownloadOutcome> download(
    UpdateAvailable update, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final asset = fileFor(update);
    if (asset == null) return const NoFileForPlatform();
    final sumsAsset = update.asset(ReleaseFiles.checksums);
    if (sumsAsset == null) return const ChecksumMissing();

    final String sumsText;
    try {
      final r = await _client.get(sumsAsset.url).timeout(stallTimeout);
      if (r.statusCode != 200) return const DownloadFailed();
      if (r.bodyBytes.length > _maxChecksumBytes) return const ChecksumMissing();
      sumsText = String.fromCharCodes(r.bodyBytes);
    } on Exception {
      return const DownloadFailed();
    }
    final expected = parseChecksums(sumsText)[asset.name];
    if (expected == null) return const ChecksumMissing();

    final Directory dir;
    try {
      dir = await platform.downloadDirectory();
      // Old update files never pile up.
      await for (final old in dir.list()) {
        await old.delete(recursive: true);
      }
    } on Exception {
      return const DownloadFailed();
    }
    final part = File('${dir.path}${Platform.pathSeparator}${asset.name}.part');
    final outcome = await _fetch(asset, part, expected, onProgress, isCancelled);
    if (outcome is! Downloaded) {
      await _deleteQuietly(part);
      return outcome;
    }
    try {
      final file = await part.rename('${dir.path}${Platform.pathSeparator}${asset.name}');
      return Downloaded(file: file, sha256: expected);
    } on FileSystemException {
      await _deleteQuietly(part);
      return const DownloadFailed();
    }
  }

  Future<DownloadOutcome> _fetch(
    ReleaseAsset asset,
    File part,
    String expected,
    void Function(int, int)? onProgress,
    bool Function()? isCancelled,
  ) async {
    IOSink? sink;
    try {
      final response = await _client.send(http.Request('GET', asset.url)).timeout(stallTimeout);
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        return const DownloadFailed();
      }
      sink = part.openWrite();
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      var received = 0;
      onProgress?.call(0, asset.size);
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        if (isCancelled?.call() ?? false) return const DownloadCancelled();
        received += chunk.length;
        // More than GitHub said the file holds: not the published file.
        if (received > asset.size) return const ChecksumMismatch();
        hasher.add(chunk);
        sink.add(chunk);
        onProgress?.call(received, asset.size);
      }
      if (isCancelled?.call() ?? false) return const DownloadCancelled();
      if (received != asset.size) return const DownloadFailed();
      hasher.close();
      await sink.flush();
      if (digest.value.toString() != expected) return const ChecksumMismatch();
      return Downloaded(file: part, sha256: expected);
    } on Exception {
      return const DownloadFailed();
    } finally {
      await sink?.close();
    }
  }

  /// Hands a verified file to the system installer, after checking its
  /// SHA-256 once more (the file sat on disk in between).
  Future<HandOff> install(Downloaded downloaded) async {
    try {
      final actual = await sha256.bind(downloaded.file.openRead()).first;
      if (actual.toString() != downloaded.sha256) {
        await _deleteQuietly(downloaded.file);
        return HandOff.failed;
      }
    } on Exception {
      return HandOff.failed;
    }
    return platform.install(downloaded.file);
  }

  /// `SHA256SUMS.txt` → file name to lower-case hex. Lines that don't match
  /// the format are ignored; a name listed twice with different values is
  /// dropped (never guess which is right).
  static Map<String, String> parseChecksums(String text) {
    final line = RegExp(r'^([0-9a-fA-F]{64})\s+\*?([A-Za-z0-9._-]+)$');
    final out = <String, String>{};
    final conflicting = <String>{};
    for (final raw in text.split('\n')) {
      final m = line.firstMatch(raw.trim());
      if (m == null) continue;
      final name = m.group(2)!;
      final hex = m.group(1)!.toLowerCase();
      if (out[name] case final seen? when seen != hex) conflicting.add(name);
      out[name] = hex;
    }
    return out..removeWhere((name, _) => conflicting.contains(name));
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (f.existsSync()) await f.delete();
    } on FileSystemException {
      // Left in Pitchy's own update folder; cleared before the next download.
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
