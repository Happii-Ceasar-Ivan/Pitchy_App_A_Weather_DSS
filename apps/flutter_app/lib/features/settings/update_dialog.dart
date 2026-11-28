import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/app_scope.dart';
import '../../core/theme/spacing.dart';
import '../../shared/widgets/link_text.dart';
import '../../shared/widgets/press_scale.dart';
import 'update_check.dart';
import 'update_installer.dart';

/// Check for updates (Settings / Quick settings): runs one check, then offers
/// the update if there is one.
Future<void> showUpdateCheck(BuildContext context) => _show(context, null);

/// The prompt after the automatic check on app open found a newer version.
Future<void> showUpdatePrompt(BuildContext context, UpdateAvailable update) =>
    _show(context, update);

Future<void> _show(BuildContext context, UpdateAvailable? found) {
  final scope = AppScope.of(context);
  return showDialog<void>(
    context: context,
    // Never dismissed by a stray tap while a download is running.
    barrierDismissible: false,
    builder: (_) => UpdateDialog(
      checker: scope.updates,
      installer: scope.updateInstaller,
      installed: scope.info.version,
      found: found,
    ),
  );
}

sealed class _Phase {
  const _Phase();
}

class _Checking extends _Phase {
  const _Checking();
}

/// A check that found no update (or failed).
class _Checked extends _Phase {
  const _Checked(this.result);
  final UpdateResult result;
}

class _Offer extends _Phase {
  const _Offer();
}

class _Downloading extends _Phase {
  const _Downloading(this.received, this.total);
  final int received;
  final int total;
}

class _Installing extends _Phase {
  const _Installing();
}

class _NeedsPermission extends _Phase {
  const _NeedsPermission(this.file);
  final Downloaded file;
}

/// Android's prompt is showing, or the Windows installer started.
class _HandedOff extends _Phase {
  const _HandedOff();
}

/// Android reported that the update installed.
class _Installed extends _Phase {
  const _Installed();
}

class _Failed extends _Phase {
  const _Failed(this.message, {this.retry = false, this.page = false, this.note});
  final String message;
  final String? note;

  /// Offer "Try again" (download again).
  final bool retry;

  /// Offer "Open download page".
  final bool page;
}

/// The update dialog (P-26, user's design 2026-11-26): "There's a new Pitchy
/// (version). Would you like to update?" → Update downloads the file for this
/// device, checks its SHA-256 and hands it to the system installer; Later
/// closes. It never says an update installed unless Android reported it.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.checker,
    required this.installer,
    required this.installed,
    this.found,
  });

  final UpdateChecker checker;
  final UpdateInstaller installer;
  final String installed;

  /// Already found by the automatic check; null runs a check first.
  final UpdateAvailable? found;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  static const _stayOnline = 'Please stay connected to the internet while it updates.';
  static const _nothingInstalled = 'Nothing was installed.';

  late _Phase _phase = widget.found == null ? const _Checking() : const _Offer();
  UpdateAvailable? _update;
  bool _cancelled = false;
  StreamSubscription<InstallReport>? _reports;

  @override
  void initState() {
    super.initState();
    _update = widget.found;
    if (widget.found == null) _check();
  }

  @override
  void dispose() {
    _cancelled = true;
    unawaited(_reports?.cancel());
    super.dispose();
  }

  void _set(_Phase p) {
    if (mounted) setState(() => _phase = p);
  }

  void _check() {
    _set(const _Checking());
    unawaited(
      widget.checker.check().then((r) {
        if (r is UpdateAvailable) {
          _update = r;
          _set(const _Offer());
        } else {
          _set(_Checked(r));
        }
      }),
    );
  }

  Future<void> _download() async {
    final update = _update!;
    _cancelled = false;
    _set(_Downloading(0, widget.installer.fileFor(update)?.size ?? 0));
    final outcome = await widget.installer.download(
      update,
      onProgress: (received, total) {
        if (!_cancelled) _set(_Downloading(received, total));
      },
      isCancelled: () => _cancelled,
    );
    if (!mounted) return;
    switch (outcome) {
      case Downloaded():
        await _install(outcome);
      case DownloadCancelled():
        Navigator.of(context).pop();
      case DownloadFailed():
        _set(
          const _Failed(
            'The download didn’t finish. $_nothingInstalled Check your connection and try again.',
            retry: true,
          ),
        );
      case ChecksumMismatch():
        _set(
          const _Failed(
            'The downloaded file didn’t match its published checksum, so Pitchy deleted it. '
            '$_nothingInstalled',
            retry: true,
          ),
        );
      case ChecksumMissing():
        _set(
          const _Failed(
            'This release has no published checksum for its file, so Pitchy won’t install it. '
            'You can get it from the download page.',
            page: true,
          ),
        );
      case NoFileForPlatform():
        _set(
          const _Failed(
            'This release has no file for this device yet. You can check the download page.',
            page: true,
          ),
        );
    }
  }

  Future<void> _install(Downloaded file) async {
    _set(const _Installing());
    _reports ??= widget.installer.reports.listen(_onReport);
    final handOff = await widget.installer.install(file);
    if (!mounted) return;
    switch (handOff) {
      case HandOff.opened:
        _set(const _HandedOff());
        if (widget.installer.target == UpdateTarget.windows) {
          // Let the message show, then close so the installer can replace Pitchy.
          await Future<void>.delayed(const Duration(seconds: 2));
          await widget.installer.quit();
        }
      case HandOff.needsPermission:
        _set(_NeedsPermission(file));
      case HandOff.failed:
        _set(
          const _Failed(
            'Pitchy couldn’t open the installer. $_nothingInstalled',
            retry: true,
            page: true,
          ),
        );
    }
  }

  void _onReport(InstallReport r) {
    if (r.succeeded) return _set(const _Installed());
    if (r.cancelledByUser) {
      return _set(const _Failed('The update was cancelled. Nothing changed.', retry: true));
    }
    _set(
      _Failed(
        'Android didn’t install the update. Nothing changed.',
        note: r.signatureProblem
            ? 'This usually means your copy of Pitchy was signed with a different key. '
                  'Uninstall Pitchy, then install the new version from the download page.'
            : null,
        page: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final installed = widget.installed;
    final update = _update;
    final version = update?.version ?? '';
    final canInstall = update != null && widget.installer.fileFor(update) != null;
    final busy = _phase is _Checking || _phase is _Downloading || _phase is _Installing;

    Widget press(Widget button) => PitchyPressScale(child: button);
    void close() => Navigator.of(context).pop();
    void openPage() {
      close();
      if (update != null) unawaited(openExternalLink(context, update.page));
    }

    final later = press(TextButton(onPressed: close, child: const Text('Later')));
    final ok = press(TextButton(onPressed: close, child: const Text('OK')));
    final closeButton = press(TextButton(onPressed: close, child: const Text('Close')));
    final pageButton = press(
      TextButton(onPressed: openPage, child: const Text('Open download page')),
    );

    final (String title, String message, String? note, List<Widget> actions) = switch (_phase) {
      _Checking() => ('Check for updates', 'Checking for a newer version…', null, <Widget>[]),
      _Checked(result: UpToDate()) => (
        'Check for updates',
        'You have the latest version, Pitchy $installed.',
        null,
        [ok],
      ),
      _Checked(result: NoReleaseYet()) => (
        'Check for updates',
        'No version has been published yet. You have Pitchy $installed.',
        null,
        [ok],
      ),
      _Checked(result: CheckFailed(limited: true)) => (
        'Check for updates',
        'GitHub is limiting update checks right now. Try again in an hour.',
        null,
        [ok],
      ),
      _Checked() => (
        'Check for updates',
        'Couldn’t check for updates. Check your connection and try again.',
        null,
        [press(TextButton(onPressed: _check, child: const Text('Try again'))), ok],
      ),
      _Offer() when canInstall => (
        'Update available',
        'There’s a new Pitchy ($version). Would you like to update?',
        _stayOnline,
        [later, press(FilledButton(onPressed: _download, child: const Text('Update')))],
      ),
      _Offer() => (
        'Update available',
        'There’s a new Pitchy ($version). You have $installed.',
        'Pitchy can’t install it on this device itself. Get it from the download page.',
        [
          later,
          press(FilledButton(onPressed: openPage, child: const Text('Open download page'))),
        ],
      ),
      _Downloading(:final received, :final total) => (
        'Updating Pitchy',
        total > 0
            ? 'Downloading Pitchy $version… ${_mb(received)} of ${_mb(total)} MB'
            : 'Downloading Pitchy $version…',
        _stayOnline,
        [press(TextButton(onPressed: () => _cancelled = true, child: const Text('Cancel')))],
      ),
      _Installing() => (
        'Updating Pitchy',
        'Checking the file and opening the installer…',
        null,
        <Widget>[],
      ),
      _NeedsPermission(:final file) => (
        'Allow installs from Pitchy',
        'Android needs your permission before Pitchy can install updates. In the screen that '
            'opened, turn on “Allow from this source”, then come back and tap Install.',
        null,
        [
          closeButton,
          press(FilledButton(onPressed: () => _install(file), child: const Text('Install'))),
        ],
      ),
      _HandedOff() when widget.installer.target == UpdateTarget.windows => (
        'Updating Pitchy',
        'The installer is opening. Pitchy will close now; follow the installer’s steps.',
        null,
        <Widget>[],
      ),
      _HandedOff() => (
        'Updating Pitchy',
        'Follow Android’s prompt to install Pitchy $version. Pitchy closes while it installs; '
            'then open it again.',
        'Android installs it only over a copy signed with the same key.',
        [closeButton],
      ),
      _Installed() => (
        'Updating Pitchy',
        'Android reports that Pitchy $version is installed.',
        null,
        [ok],
      ),
      _Failed(:final message, :final note, :final retry, :final page) => (
        'Update not installed',
        message,
        note,
        [
          if (page) pageButton,
          closeButton,
          if (retry) press(FilledButton(onPressed: _download, child: const Text('Try again'))),
        ],
      ),
    };

    final phase = _phase;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        icon: const Icon(Icons.system_update_alt),
        title: Text(title),
        content: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (phase is _Checking || phase is _Installing) ...[
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: PitchySpace.lg),
                  ],
                  Expanded(child: Text(message)),
                ],
              ),
              if (phase case _Downloading(:final received, :final total)) ...[
                const SizedBox(height: PitchySpace.lg),
                LinearProgressIndicator(
                  value: total > 0 ? (received / total).clamp(0.0, 1.0) : null,
                  semanticsLabel: 'Download progress',
                  semanticsValue: total > 0 ? '${(100 * received / total).floor()}%' : null,
                ),
              ],
              if (note != null) ...[
                const SizedBox(height: PitchySpace.md),
                Text(note, style: text.bodySmall),
              ],
            ],
          ),
        ),
        actions: actions,
      ),
    );
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}
