import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/errors/api_failure.dart';
import '../../core/network/pitchy_api.dart';
import '../../shared/models/ingestion.dart';

/// What the last update attempt ended with. Shown once, then replaced by the
/// next attempt. None of these change a weather state: the dashboard reloads
/// and shows what the backend reports.
sealed class IngestOutcome {
  const IngestOutcome();
}

/// Every job finished and succeeded.
class IngestUpdated extends IngestOutcome {
  const IngestUpdated();
}

/// 409 `INGESTION_NOT_NEEDED`: the backend says nothing needs updating.
class IngestNotNeeded extends IngestOutcome {
  const IngestNotNeeded();
}

/// 409 `CONFLICT`: the backend says an update for this venue is busy. The
/// board reloads and follows any job it reports.
class IngestBusy extends IngestOutcome {
  const IngestBusy();
}

/// 429: the sources needing data must wait until [retryAt] (PAGASA 4-hour gap,
/// or the cooldown after a failed attempt). The backend decides; the app waits.
class IngestMustWait extends IngestOutcome {
  const IngestMustWait(this.retryAt);
  final DateTime? retryAt;
}

/// At least one job ended `failed` or `expired`.
class IngestJobsFailed extends IngestOutcome {
  const IngestJobsFailed(this.failures);
  final List<IngestionFailure> failures;
}

/// The update request itself didn't get through (offline, timeout, server error).
/// Sending it again is safe: the backend reuses a job that is already running.
class IngestRequestFailed extends IngestOutcome {
  const IngestRequestFailed(this.failure);
  final ApiFailure failure;
}

/// Pitchy stopped checking the jobs (no answer for a while, or they ran longer
/// than [IngestionController.maxWait]). The jobs may still finish on the server.
class IngestStoppedChecking extends IngestOutcome {
  const IngestStoppedChecking();
}

enum IngestPhase {
  /// Nothing in flight.
  idle,

  /// `POST .../ingestions` sent, no answer yet.
  requesting,

  /// Jobs accepted (202) or found running; polling `GET /ingestions/{id}`.
  polling,
}

/// Runs the manual update flow for one match:
///
/// 1. [request] sends `POST .../ingestions` once. While a request or poll is in
///    flight, or while the backend's `retry_at` is ahead, further requests are
///    ignored, so a double tap never sends two.
/// 2. A 202 gives a job list (some may be other people's running jobs, reused).
///    Jobs are polled every [pollInterval] until each is succeeded, failed or
///    expired.
/// 3. Jobs already running for the venue (from `weather-status.active_job_ids`)
///    are watched the same way with [watch], without sending anything.
/// 4. When every job has finished, [onFinished] is called so the dashboard
///    reloads its status and values from the backend.
///
/// Updating shows only after the backend accepts (P-17: no optimistic UI for
/// ingestion).
class IngestionController extends ChangeNotifier {
  IngestionController({
    required this.api,
    required this.matchContextId,
    required this.onFinished,
    this.onAccepted,
    DateTime Function()? clock,
    this.pollInterval = const Duration(seconds: 3),
    this.maxWait = const Duration(minutes: 4),
    this.maxPollFailures = 3,
  }) : _clock = clock ?? DateTime.now;

  final PitchyApi api;
  final String matchContextId;

  /// Called after every job has finished (any result). Reloads the dashboard.
  final Future<void> Function() onFinished;

  /// Called once the backend accepts a request (202), so the board reloads
  /// and shows the backend's own Updating states.
  final Future<void> Function()? onAccepted;
  final DateTime Function() _clock;

  final Duration pollInterval;

  /// The backend leases a job for 5 minutes and reports it `expired` once the
  /// lease runs out, so a job never runs longer than that without an answer.
  final Duration maxWait;

  /// Consecutive failed polls before Pitchy stops checking.
  final int maxPollFailures;

  IngestPhase _phase = IngestPhase.idle;
  IngestPhase get phase => _phase;

  /// Jobs being watched, latest state per id.
  final Map<String, IngestionJob?> _jobs = {};

  /// Jobs this controller has seen finish; never watched again.
  final Set<String> _finished = {};

  int get jobCount => _jobs.length;
  int get finishedCount => _jobs.values.where((j) => j != null && j.state.isFinished).length;

  IngestOutcome? _outcome;
  IngestOutcome? get outcome => _outcome;

  DateTime? _waitUntil;

  /// Set after a 429: the backend's `retry_at`. Requests are held until then.
  DateTime? get waitUntil => _waitUntil;

  bool get busy => _phase != IngestPhase.idle;
  bool get canRequest => !busy && _waitUntil == null;

  Timer? _pollTimer;
  Timer? _waitTimer;
  DateTime? _pollStarted;
  int _pollFailures = 0;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Clears the last outcome (the user dismissed it).
  void dismissOutcome() {
    _outcome = null;
    _notify();
  }

  /// Sends one update request. Ignored while busy or while the backend's
  /// `retry_at` is ahead.
  Future<void> request() async {
    if (!canRequest) return;
    _phase = IngestPhase.requesting;
    _outcome = null;
    _notify();
    try {
      final result = await api.requestIngestion(matchContextId);
      if (_disposed) return;
      _startPolling(result.jobs.map((j) => j.id), initial: result.jobs);
      if (_phase == IngestPhase.polling) await onAccepted?.call();
    } on ApiError catch (e) {
      if (_disposed) return;
      _phase = IngestPhase.idle;
      switch (e.code) {
        case ApiErrorCode.ingestionNotNeeded || ApiErrorCode.conflict:
          // Reload first, so the message lands with the backend's new states.
          await onFinished();
          if (_disposed) return;
          _outcome = e.code == ApiErrorCode.conflict ? const IngestBusy() : const IngestNotNeeded();
          _notify();
        case ApiErrorCode.rateLimited:
          _outcome = IngestMustWait(e.retryAt);
          _holdUntil(e.retryAt);
          _notify();
        case _:
          _outcome = IngestRequestFailed(e);
          _notify();
      }
    } on ApiFailure catch (e) {
      if (_disposed) return;
      _phase = IngestPhase.idle;
      _outcome = IngestRequestFailed(e);
      _notify();
    }
  }

  /// Watches jobs the backend reports as running for this venue (someone
  /// else's request, or the 6-hourly schedule). Sends nothing. Jobs already
  /// watched or seen finished are skipped.
  void watch(List<String> jobIds) {
    if (busy) return;
    final fresh = jobIds.where((id) => !_finished.contains(id)).toList();
    if (fresh.isEmpty) return;
    _outcome = null;
    _startPolling(fresh);
  }

  void _startPolling(Iterable<String> ids, {List<IngestionJob> initial = const []}) {
    _jobs
      ..clear()
      ..addEntries(ids.map((id) => MapEntry(id, null)));
    for (final j in initial) {
      _jobs[j.id] = j;
    }
    _phase = IngestPhase.polling;
    _pollStarted = _clock();
    _pollFailures = 0;
    _notify();
    if (_allFinished) {
      unawaited(_finish());
    } else {
      _schedulePoll();
    }
  }

  bool get _allFinished => _jobs.values.every((j) => j != null && j.state.isFinished);

  void _schedulePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer(pollInterval, () => unawaited(_poll()));
  }

  Future<void> _poll() async {
    if (_disposed) return;
    final pending = [
      for (final e in _jobs.entries)
        if (e.value == null || !e.value!.state.isFinished) e.key,
    ];
    var anyFailed = false;
    for (final id in pending) {
      try {
        _jobs[id] = await api.getIngestionJob(id);
      } on ApiError catch (e) {
        if (e.code == ApiErrorCode.notFound) {
          // The job is gone (cleaned up); the status reload shows the result.
          _finished.add(id);
          _jobs.remove(id);
        } else {
          anyFailed = true;
        }
      } on ApiFailure {
        anyFailed = true;
      }
      if (_disposed) return;
    }
    _pollFailures = anyFailed ? _pollFailures + 1 : 0;
    _notify();

    if (_allFinished) {
      await _finish();
      return;
    }
    final waited = _clock().difference(_pollStarted!);
    if (_pollFailures >= maxPollFailures || waited >= maxWait) {
      _stop(const IngestStoppedChecking());
      return;
    }
    _schedulePoll();
  }

  Future<void> _finish() async {
    final jobs = _jobs.values.whereType<IngestionJob>().toList();
    _finished.addAll(_jobs.keys);
    final failures = [
      for (final j in jobs)
        if (j.state != IngestionJobState.succeeded) ...j.failures,
    ];
    final anyBad = jobs.any((j) => j.state != IngestionJobState.succeeded);
    _pollTimer?.cancel();
    _jobs.clear();
    // Reload first, so "updated" never shows over the old board.
    await onFinished();
    if (_disposed) return;
    _stop(anyBad ? IngestJobsFailed(failures) : const IngestUpdated());
  }

  void _stop(IngestOutcome outcome) {
    _pollTimer?.cancel();
    _phase = IngestPhase.idle;
    _jobs.clear();
    _outcome = outcome;
    _notify();
  }

  void _holdUntil(DateTime? retryAt) {
    _waitTimer?.cancel();
    if (retryAt == null) return;
    final wait = retryAt.difference(_clock());
    if (wait <= Duration.zero) return;
    _waitUntil = retryAt;
    // A local timer only re-enables the button; whether data is needed is
    // still the backend's answer on the next request.
    _waitTimer = Timer(wait, () {
      _waitUntil = null;
      _notify();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _waitTimer?.cancel();
    super.dispose();
  }
}
