import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../../core/app_scope.dart';
import '../../core/config/project_links.dart';
import '../../shared/widgets/link_text.dart';

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
  const UpdateAvailable({required this.version, required this.page});

  /// `1.1.0`, from the release tag.
  final String version;

  /// The GitHub release page (files and checksums). Always in this
  /// repository; anything else is replaced by the repository's releases page.
  final Uri page;
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

/// Check for Updates (P-08 option A, user 2026-11-26): asks GitHub for the
/// newest published release and compares its tag with the installed version.
/// It never downloads or installs anything, sends no credentials, and treats
/// the reply as untrusted (only a version number and a link in this repo are
/// used).
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
    return UpdateAvailable(version: latest.join('.'), page: _safePage(body['html_url']));
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

/// Opens the Check for Updates dialog and runs one check.
Future<void> showUpdateCheck(BuildContext context) {
  final scope = AppScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => _UpdateDialog(checker: scope.updates, installed: scope.info.version),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.checker, required this.installed});

  final UpdateChecker checker;
  final String installed;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  UpdateResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _run() {
    setState(() => _result = null);
    unawaited(
      widget.checker.check().then((r) {
        if (mounted) setState(() => _result = r);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final you = 'Pitchy ${widget.installed}';
    final result = _result;
    final (String message, List<Widget> actions) = switch (result) {
      null => ('Checking for a newer version…', const <Widget>[]),
      UpdateAvailable(:final version, :final page) => (
        'Pitchy $version is available. You have ${widget.installed}.',
        [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Later')),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(openExternalLink(context, page));
            },
            child: const Text('Open download page'),
          ),
        ],
      ),
      UpToDate() => ('You have the latest version, $you.', const <Widget>[]),
      NoReleaseYet() => ('No version has been published yet. You have $you.', const <Widget>[]),
      CheckFailed(limited: true) => (
        'GitHub is limiting update checks right now. Try again in an hour.',
        const <Widget>[],
      ),
      CheckFailed() => (
        'Couldn’t check for updates. Check your connection and try again.',
        [TextButton(onPressed: _run, child: const Text('Try again'))],
      ),
    };
    return AlertDialog(
      icon: const Icon(Icons.system_update_alt),
      title: const Text('Check for updates'),
      content: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            if (result == null) ...[
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
      actions: [
        ...actions,
        if (result is! UpdateAvailable)
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
      ],
    );
  }
}
