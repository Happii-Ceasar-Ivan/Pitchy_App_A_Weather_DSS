// Manual ingestion (contract schemas IngestionJob, IngestionRequestResult,
// IngestionFailure). Confirmed: live since Backend Sprint B3.
//
// POST .../ingestions answers 202 with a list of group jobs (some may be reused
// existing jobs), 409 when not needed or already running, or 429 with retry_at.

import 'json.dart';

enum IngestionJobState {
  queued('queued'),
  running('running'),
  succeeded('succeeded'),
  failed('failed'),
  expired('expired');

  const IngestionJobState(this.wire);
  final String wire;

  static String wireOf(IngestionJobState s) => s.wire;

  bool get isFinished => this == succeeded || this == failed || this == expired;
}

class IngestionFailure {
  const IngestionFailure({required this.sourceId, required this.code, required this.message});

  factory IngestionFailure.fromJson(Json json) => IngestionFailure(
    sourceId: readStringOrNull(json, 'source_id'),
    code: readString(json, 'code'),
    message: readString(json, 'message'),
  );

  final String? sourceId;
  final String code;
  final String message;
}

class IngestionJob {
  const IngestionJob({
    required this.id,
    required this.state,
    required this.venue,
    required this.sourceIds,
    required this.createdAt,
    required this.startedAt,
    required this.finishedAt,
    required this.failures,
    required this.reusedExistingJob,
  });

  factory IngestionJob.fromJson(Json json) => IngestionJob(
    id: readString(json, 'id'),
    state: readEnum(json, 'state', IngestionJobState.values, IngestionJobState.wireOf),
    venue: readString(json, 'venue'),
    sourceIds: readStringList(json, 'source_ids'),
    createdAt: readTime(json, 'created_at'),
    startedAt: readTimeOrNull(json, 'started_at'),
    finishedAt: readTimeOrNull(json, 'finished_at'),
    failures: readList(json, 'failures', IngestionFailure.fromJson, optional: true),
    reusedExistingJob: readBool(json, 'reused_existing_job'),
  );

  final String id;
  final IngestionJobState state;
  final String venue;
  final List<String> sourceIds;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final List<IngestionFailure> failures;

  /// True when another user's running job was reused (shared lock).
  final bool reusedExistingJob;
}

class IngestionRequestResult {
  const IngestionRequestResult({required this.matchContextId, required this.jobs});

  factory IngestionRequestResult.fromJson(Json json) => IngestionRequestResult(
    matchContextId: readString(json, 'match_context_id'),
    jobs: readList(json, 'jobs', IngestionJob.fromJson),
  );

  final String matchContextId;
  final List<IngestionJob> jobs;
}
