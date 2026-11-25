import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/errors/api_failure.dart';
import '../../core/utils/pht_time.dart';

/// The backend's `retry_at` when [failure] is a 429 (`RATE_LIMITED`), else null.
DateTime? rateLimitRetryAt(Object? failure) =>
    failure is ApiError && failure.code == ApiErrorCode.rateLimited ? failure.retryAt : null;

/// True when [failure] is a 429 (`RATE_LIMITED`), with or without `retry_at`.
bool isRateLimited(Object? failure) =>
    failure is ApiError && failure.code == ApiErrorCode.rateLimited;

/// `You can try again at 3:25 PM PHT.`
String tryAgainAtText(DateTime retryAt) => 'You can try again at ${formatPhtTime(retryAt)}.';

/// Rebuilds once [retryAt] has passed, so a "try again at" state can turn its
/// action back on at that time without a reload.
///
/// The device clock only re-enables the action. Whether the next request is
/// allowed is still the backend's answer.
class RetryAtBuilder extends StatefulWidget {
  const RetryAtBuilder({super.key, required this.retryAt, required this.builder, this.clock});

  /// When to allow the action again. Null: no wait.
  final DateTime? retryAt;

  /// `waiting` is true until [retryAt] has passed.
  final Widget Function(BuildContext context, bool waiting) builder;

  /// For tests; the device clock otherwise.
  final DateTime Function()? clock;

  @override
  State<RetryAtBuilder> createState() => _RetryAtBuilderState();
}

class _RetryAtBuilderState extends State<RetryAtBuilder> {
  Timer? _timer;
  bool _waiting = false;

  DateTime _now() => (widget.clock ?? DateTime.now)().toUtc();

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(RetryAtBuilder old) {
    super.didUpdateWidget(old);
    if (old.retryAt != widget.retryAt) _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    final at = widget.retryAt;
    final wait = at == null ? Duration.zero : at.toUtc().difference(_now());
    _waiting = wait > Duration.zero;
    if (_waiting) {
      // One extra second so the backend's window has surely closed.
      _timer = Timer(wait + const Duration(seconds: 1), () {
        if (mounted) setState(() => _waiting = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _waiting);
}
