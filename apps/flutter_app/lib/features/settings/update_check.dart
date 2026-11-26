import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/project_links.dart';

/// What one check found.
sealed class UpdateResult {
  const UpdateResult();
}

/// The installed version is the newest published one (or newer: a
/// development build).
class UpToDate extends UpdateResult {
  const UpToDate();
}

class UpdateAvailable extends UpdateResult {
  const UpdateAvailable({required this.version, required this.page, this.assets = const []});

  /// `1.1.0`, from the release tag.
  final String version;

  /// The GitHub release page (files and checksums). Always in this
  /// repository; anything else is replaced by the repository's releases page.
  final Uri page;

  /// The release's files whose download address is inside this repository's
  /// releases (anything else in the reply is dropped).
  final List<ReleaseAsset> assets;

  ReleaseAsset? asset(String name) {
    for (final a in assets) {
      if (a.name == name) return a;
    }
    return null;
  }
}

/// One file of a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, required this.size});

  /// `pitchy-1.1.0-android.apk`. Letters, digits, `.`, `_` and `-` only.
  final String name;

  /// Always `https://github.com/<this repo>/releases/download/...`.
  final Uri url;

  /// Bytes, as GitHub reports it (1 byte to [maxBytes]).
  final int size;

  /// Larger files are refused (the APK and installer are tens of MB).
  static const maxBytes = 300 * 1024 * 1024;

  static final _name = RegExp(r'^[A-Za-z0-9._-]{1,120}$');

  /// The asset if every field is safe to use, else null. The GitHub reply is
  /// untrusted: only this repository's release download addresses are kept.
  static ReleaseAsset? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final name = json['name'];
    final url = json['browser_download_url'];
    final size = json['size'];
    if (name is! String || !_name.hasMatch(name) || name.startsWith('.')) return null;
    if (size is! int || size <= 0 || size > maxBytes) return null;
    if (url is! String) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !isRepoDownload(uri)) return null;
    return ReleaseAsset(name: name, url: uri, size: size);
  }

  /// `https://github.com/<owner>/<repo>/releases/download/<tag>/<file>`, with
  /// nothing else (no user info, port, query, `.` or `..` segments).
  static bool isRepoDownload(Uri uri) {
    final repo = Uri.parse(ProjectLinks.repo);
    final s = uri.pathSegments;
    return uri.scheme == 'https' &&
        uri.host == repo.host &&
        !uri.hasPort &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        s.length == 6 &&
        s[0] == repo.pathSegments[0] &&
        s[1] == repo.pathSegments[1] &&
        s[2] == 'releases' &&
        s[3] == 'download' &&
        s.skip(4).every((p) => p.isNotEmpty && p != '.' && p != '..');
  }
}

/// GitHub has no published release yet (404).
class NoReleaseYet extends UpdateResult {
  const NoReleaseYet();
}

/// The check didn't work. Never shown as "up to date".
class CheckFailed extends UpdateResult {
  const CheckFailed({this.limited = false});

  /// GitHub is rate-limiting unauthenticated checks (403/429).
  final bool limited;
}

/// Check for Updates (P-08 option A, user 2026-11-26; P-26): asks GitHub for
/// the newest published release and compares its tag with the installed
/// version. It sends no credentials and treats the reply as untrusted: only a
/// version number, a page and file links inside this repository are used.
/// Downloading and installing is [UpdateInstaller]'s job, and only after the
/// user confirms.
class UpdateChecker {
  UpdateChecker({required this.installedVersion, http.Client? client})
    : _client = client ?? http.Client();

  final String installedVersion;
  final http.Client _client;

  static const timeout = Duration(seconds: 15);

  Future<UpdateResult> check() async {
    final http.Response response;
    try {
      response = await _client
          .get(
            ProjectLinks.latestRelease,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(timeout);
    } on Exception {
      // No network, DNS, TLS or timeout.
      return const CheckFailed();
    }
    switch (response.statusCode) {
      case 404:
        return const NoReleaseYet();
      case 403 || 429:
        return const CheckFailed(limited: true);
      case != 200:
        return const CheckFailed();
    }
    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      return const CheckFailed();
    }
    if (body is! Map<String, Object?>) return const CheckFailed();
    final tag = body['tag_name'];
    final latest = tag is String ? _parse(tag) : null;
    final installed = _parse(installedVersion);
    if (latest == null || installed == null) return const CheckFailed();
    if (_compare(latest, installed) <= 0) return const UpToDate();
    final rawAssets = body['assets'];
    return UpdateAvailable(
      version: latest.join('.'),
      page: _safePage(body['html_url']),
      assets: [
        if (rawAssets is List)
          for (final a in rawAssets) ?ReleaseAsset.fromJson(a),
      ],
    );
  }

  /// `v1.2.3`, `1.2.3` or `1.2.3+4` → [1, 2, 3]; anything else → null.
  static List<int>? _parse(String text) {
    final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$').firstMatch(text.trim());
    if (m == null) return null;
    return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
  }

  static int _compare(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return 0;
  }

  static Uri _safePage(Object? url) {
    const releases = '${ProjectLinks.repo}/releases';
    if (url is String && url.startsWith('$releases/')) {
      final parsed = Uri.tryParse(url);
      if (parsed != null && parsed.scheme == 'https') return parsed;
    }
    return Uri.parse(releases);
  }
}
