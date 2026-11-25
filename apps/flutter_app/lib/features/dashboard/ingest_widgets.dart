import 'package:material_ui/material_ui.dart';

import '../../core/errors/failure_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/pht_time.dart';
import '../../shared/models/weather.dart';
import '../../shared/widgets/weather_value_card.dart' show shortSourceName;
import 'ingestion_controller.dart';

/// The source rail's header slot: "Update" when the backend reports
/// `ingestion_needed`, progress while jobs run, nothing otherwise.
///
/// Returns null when there is nothing to show, so the header keeps its text only.
Widget? updateAction(
  BuildContext context, {
  required IngestionController ingest,
  required bool ingestionNeeded,
}) {
  if (ingest.phase == IngestPhase.polling) return _Progress(ingest: ingest);
  if (!ingestionNeeded && ingest.phase == IngestPhase.idle) return null;
  final sending = ingest.phase == IngestPhase.requesting;
  return Semantics(
    hint: ingest.waitUntil == null
        ? null
        : 'You can update again at ${formatPhtTime(ingest.waitUntil!)}',
    child: FilledButton.icon(
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)),
      onPressed: ingest.canRequest ? ingest.request : null,
      icon: sending
          ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.sync, size: 18),
      label: Text(sending ? 'Sending' : 'Update'),
    ),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.ingest});

  final IngestionController ingest;

  @override
  Widget build(BuildContext context) {
    final s = context.stateColors.of(WeatherDataState.updating);
    final total = ingest.jobCount;
    final done = ingest.finishedCount;
    return Semantics(
      liveRegion: true,
      label: total > 1
          ? 'Updating weather data, $done of $total source groups done'
          : 'Updating weather data',
      excludeSemantics: true,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: s.background,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: s.foreground,
                backgroundColor: s.foreground.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              // The count is in the screen-reader label; the visible text stays
              // short so the header keeps its "checked ... PHT" time.
              'Updating',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: s.foreground, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// The result of the last update attempt that needs reading (must wait,
/// failed, couldn't send, stopped checking), under the rail header. Success
/// and "already up to date" are brief snack bars instead.
class IngestNotice extends StatelessWidget {
  const IngestNotice({
    super.key,
    required this.outcome,
    required this.sources,
    required this.onDismiss,
    required this.onCheckAgain,
  });

  final IngestOutcome outcome;

  /// Used to name a failed source ("PAGASA ECMWF") from its id.
  final List<SourceStatus> sources;

  /// Null hides the close button (a 429 notice stays while the wait lasts).
  final VoidCallback? onDismiss;
  final VoidCallback onCheckAgain;

  /// Whether [outcome] is shown here (the others become snack bars).
  static bool shows(IngestOutcome? o) =>
      o is IngestMustWait ||
      o is IngestJobsFailed ||
      o is IngestRequestFailed ||
      o is IngestStoppedChecking;

  String _name(String? id) {
    for (final s in sources) {
      if (s.sourceId == id) return shortSourceName(s.sourceName);
    }
    return id ?? 'Update';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final errorColor = context.safetyColors.requestErrorInk;
    final (
      IconData icon,
      Color iconColor,
      String title,
      String detail,
      bool checkAgain,
    ) = switch (outcome) {
      IngestMustWait(:final retryAt) => (
        Icons.schedule,
        palette.ink,
        retryAt == null ? 'Update again later' : 'Update again at ${formatPhtTime(retryAt)}',
        'The sources that need data were asked recently. Pitchy limits how often each '
            'source is asked.',
        false,
      ),
      IngestJobsFailed(:final failures) => (
        Icons.error_outline,
        errorColor,
        'The update didn’t finish',
        failures.isEmpty
            ? 'The server stopped the update. The board shows the data the server has.'
            : [
                for (final f in failures.take(3)) '${_name(f.sourceId)}: ${f.message}',
                if (failures.length > 3) 'and ${failures.length - 3} more',
              ].join('\n'),
        false,
      ),
      IngestRequestFailed(:final failure) => (
        Icons.error_outline,
        errorColor,
        'Update not sent: ${describeFailure(failure).title.toLowerCase()}',
        'Trying again is safe. It joins an update already running instead of starting '
            'a second one.',
        false,
      ),
      IngestStoppedChecking() => (
        Icons.sync_problem,
        palette.ink,
        'Pitchy stopped checking the update',
        'It may still finish on the server. Check again to see the result.',
        true,
      ),
      _ => (Icons.info_outline, palette.ink, '', '', false),
    };
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
        decoration: BoxDecoration(
          color: palette.ground,
          border: Border.all(color: palette.hairline, width: AppTheme.hairline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(detail, style: text.bodySmall),
                  if (checkAgain)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(48, AppTheme.minTarget),
                          tapTargetSize: MaterialTapTargetSize.padded,
                        ),
                        onPressed: onCheckAgain,
                        child: const Text('Check again'),
                      ),
                    ),
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                tooltip: 'Dismiss',
                onPressed: onDismiss,
                icon: Icon(Icons.close, size: 18, color: palette.inkMuted),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}
