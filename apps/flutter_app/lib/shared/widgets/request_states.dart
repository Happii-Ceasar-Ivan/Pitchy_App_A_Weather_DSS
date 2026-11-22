import 'package:material_ui/material_ui.dart';

import '../../core/errors/api_failure.dart';
import '../../core/errors/failure_messages.dart';
import '../../core/state/loadable.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/pht_time.dart';
import '../models/weather.dart';

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
/// A 429 shows when to try again (in PHT).
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.failure, this.onRetry});

  final ApiFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = describeFailure(failure);
    final retryAt = failure is ApiError ? (failure as ApiError).retryAt : null;
    final notYet = failure is ApiError && (failure as ApiError).code == ApiErrorCode.notImplemented;
    return _MessageState(
      icon: notYet ? Icons.construction : Icons.error_outline,
      iconColor: notYet ? context.palette.inkMuted : context.safetyColors.requestError,
      title: message.title,
      detail: retryAt == null
          ? message.detail
          : '${message.detail} You can try again at ${formatPhtTime(retryAt)}.',
      action: message.canRetry && onRetry != null
          ? OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            )
          : null,
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
  factory NoticeBanner.savedCopy(
    BuildContext context, {
    required DateTime savedAt,
    Widget? action,
  }) {
    final s = context.stateColors.of(WeatherDataState.stale);
    return NoticeBanner(
      icon: Icons.cloud_off,
      message:
          'Saved copy from ${formatPhtTime(savedAt)}, not live. '
          'Pitchy can’t reach its server.',
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

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    container: true,
    child: Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (busy)
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: foreground,
                backgroundColor: foreground.withValues(alpha: 0.2),
              ),
            )
          else
            Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?action,
        ],
      ),
    ),
  );
}
