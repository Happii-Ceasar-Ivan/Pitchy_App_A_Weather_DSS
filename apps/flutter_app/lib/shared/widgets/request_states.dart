import 'package:material_ui/material_ui.dart';

import '../../core/errors/api_failure.dart';
import '../../core/errors/failure_messages.dart';
import '../../core/state/loadable.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/pht_time.dart';
import '../models/weather.dart';
import 'retry_at.dart';

/// Loading: a request is in flight and nothing is known yet.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label = 'Loading'});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      liveRegion: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(dimension: 32, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 16),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    ),
  );
}

/// Shared layout for message states (empty, error, not available yet).
class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: iconColor),
              const SizedBox(height: 16),
              Text(title, style: text.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                detail,
                style: text.bodyMedium?.copyWith(color: context.palette.inkMuted),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty: the request worked and there is nothing to show yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.detail,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => _MessageState(
    icon: icon,
    iconColor: context.palette.inkMuted,
    title: title,
    detail: detail,
    action: action,
  );
}

/// Error: the request failed. Shows a plain reason and, when it helps, Try again.
/// A 429 shows when to try again (in PHT) and offers Try again only once that
/// time has passed.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.failure, this.onRetry, this.clock});

  final ApiFailure failure;
  final VoidCallback? onRetry;

  /// For tests; the device clock otherwise.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final message = describeFailure(failure);
    final limited = isRateLimited(failure);
    final retryAt = rateLimitRetryAt(failure);
    final notYet = failure is ApiError && (failure as ApiError).code == ApiErrorCode.notImplemented;
    return RetryAtBuilder(
      retryAt: retryAt,
      clock: clock,
      builder: (context, waiting) {
        final canRetry = limited ? !waiting : message.canRetry;
        return _MessageState(
          icon: notYet
              ? Icons.construction
              : waiting
              ? Icons.hourglass_top
              : Icons.error_outline,
          iconColor: notYet ? context.palette.inkMuted : context.safetyColors.requestErrorInk,
          title: limited && !waiting && retryAt != null ? 'You can try again now' : message.title,
          detail: !limited
              ? message.detail
              : waiting
              ? 'Pitchy’s server is limiting requests. ${tryAgainAtText(retryAt!)}'
              : retryAt == null
              ? 'Pitchy’s server is limiting requests. Wait a few minutes, then try again.'
              : 'The server asked to wait until ${formatPhtTime(retryAt)}. That time has passed.',
          action: canRetry && onRetry != null
              ? OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                )
              : null,
        );
      },
    );
  }
}

/// Renders a [Loadable]: loading, the built data, or the error state.
class LoadableView<T> extends StatelessWidget {
  const LoadableView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.loadingLabel = 'Loading',
  });

  final Loadable<T> value;
  final Widget Function(BuildContext context, T value) builder;
  final VoidCallback? onRetry;
  final String loadingLabel;

  @override
  Widget build(BuildContext context) => switch (value) {
    Loading<T>() => LoadingState(label: loadingLabel),
    Loaded<T>(:final value) => builder(context, value),
    Failed<T>(:final failure) => ErrorState(failure: failure, onRetry: onRetry),
  };
}

/// A full-width notice strip used above content: Updating, or a saved copy
/// shown while the server can't be reached (DEC-13). It never claims the data is
/// current.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.foreground,
    required this.background,
    this.busy = false,
    this.action,
    this.detail,
  });

  /// "Updating weather data..." while an ingestion job runs.
  factory NoticeBanner.updating(BuildContext context, {String? detail}) {
    final s = context.stateColors.of(WeatherDataState.updating);
    return NoticeBanner(
      icon: s.icon,
      busy: true,
      message: detail ?? 'Updating weather data. Values may change.',
      foreground: s.foreground,
      background: s.background,
    );
  }

  /// "Saved copy from 3:05 PM PHT, not live" (DEC-13). Uses the Stale colours.
  /// After a failed Try again ([tries] 2 or more) the reason says "still" with
  /// the try number and time, so the live region speaks again (F5 P2-2).
  factory NoticeBanner.savedCopy(
    BuildContext context, {
    required DateTime savedAt,
    int tries = 1,
    DateTime? lastTriedAt,
    Widget? action,
  }) {
    final s = context.stateColors.of(WeatherDataState.stale);
    return NoticeBanner(
      icon: Icons.cloud_off,
      message: 'Saved copy from ${formatPhtTime(savedAt)}, not live.',
      detail: tries < 2
          ? 'Pitchy can’t reach its server.'
          : lastTriedAt == null
          ? 'Still can’t reach its server (try $tries).'
          : 'Still can’t reach its server (try $tries, ${formatPhtTime(lastTriedAt)}).',
      foreground: s.foreground,
      background: s.background,
      action: action,
    );
  }

  final IconData icon;
  final String message;
  final Color foreground;
  final Color background;
  final bool busy;
  final Widget? action;

  /// A second, lighter line under [message] (the reason).
  final String? detail;

  /// Below this width, or at large text, the action goes under the text so
  /// the message keeps the full width.
  static const stackBelow = 400.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final lead = busy
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: foreground,
              backgroundColor: foreground.withValues(alpha: 0.2),
            ),
          )
        : Icon(icon, size: 20, color: foreground);
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: text.bodyMedium?.copyWith(color: foreground, fontWeight: FontWeight.w700),
        ),
        if (detail != null) Text(detail!, style: text.bodySmall?.copyWith(color: foreground)),
      ],
    );
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: LayoutBuilder(
          builder: (context, c) {
            final stacked =
                action != null && (c.maxWidth < stackBelow || AppTheme.isLargeText(context));
            // The icon sits on the first line, not centred on a tall block.
            final body = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: lead),
                const SizedBox(width: 12),
                Expanded(child: words),
                if (!stacked) ?action,
              ],
            );
            if (!stacked) return body;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                body,
                Align(alignment: AlignmentDirectional.centerEnd, child: action),
              ],
            );
          },
        ),
      ),
    );
  }
}
