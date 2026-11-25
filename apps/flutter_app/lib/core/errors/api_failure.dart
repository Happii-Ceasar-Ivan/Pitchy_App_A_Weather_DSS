// Errors the API client can return. Backend errors use the standard envelope
// (contract schemas ErrorEnvelope, ErrorBody, ErrorDetail, ErrorCode):
//   {"error": {"code", "message", "request_id", "retry_at", "details"}}

import '../../shared/models/json.dart';

enum ApiErrorCode {
  badRequest('BAD_REQUEST'),
  invalidSession('INVALID_SESSION'),
  validationError('VALIDATION_ERROR'),
  notFound('NOT_FOUND'),
  methodNotAllowed('METHOD_NOT_ALLOWED'),
  conflict('CONFLICT'),
  ingestionNotNeeded('INGESTION_NOT_NEEDED'),
  payloadTooLarge('PAYLOAD_TOO_LARGE'),
  rateLimited('RATE_LIMITED'),
  notImplemented('NOT_IMPLEMENTED'),
  serviceUnavailable('SERVICE_UNAVAILABLE'),
  internalError('INTERNAL_ERROR'),

  /// Not a contract code: the backend sent a code this app version doesn't know.
  unknown('UNKNOWN');

  const ApiErrorCode(this.wire);
  final String wire;

  static ApiErrorCode fromWire(String value) =>
      values.firstWhere((c) => c.wire == value, orElse: () => unknown);
}

class ApiErrorDetail {
  const ApiErrorDetail({required this.field, required this.issue});

  factory ApiErrorDetail.fromJson(Json json) =>
      ApiErrorDetail(field: readStringOrNull(json, 'field'), issue: readString(json, 'issue'));

  final String? field;
  final String issue;
}

/// Everything a request can fail with. Screens map these to the shared error and
/// unavailable states; none of them is ever shown as current data.
sealed class ApiFailure implements Exception {
  const ApiFailure();
}

/// The backend answered with the standard error envelope.
class ApiError extends ApiFailure {
  const ApiError({
    required this.statusCode,
    required this.code,
    required this.message,
    this.requestId,
    this.retryAt,
    this.details = const [],
  });

  factory ApiError.fromEnvelope(int statusCode, Json envelope) {
    final body = asJson(envelope['error'], 'error');
    return ApiError(
      statusCode: statusCode,
      code: ApiErrorCode.fromWire(readString(body, 'code')),
      message: readString(body, 'message'),
      requestId: readStringOrNull(body, 'request_id'),
      retryAt: readTimeOrNull(body, 'retry_at'),
      details: readList(body, 'details', ApiErrorDetail.fromJson, optional: true),
    );
  }

  final int statusCode;
  final ApiErrorCode code;

  /// Safe, generic backend message (no stack traces or echoed values).
  final String message;
  final String? requestId;

  /// Set on 429 (rate limited, ingestion cooldown): when to try again.
  final DateTime? retryAt;
  final List<ApiErrorDetail> details;

  @override
  String toString() => 'ApiError($statusCode ${code.wire})';
}

/// No usable connection to the backend (offline, DNS, refused, TLS).
class NetworkFailure extends ApiFailure {
  const NetworkFailure();

  @override
  String toString() => 'NetworkFailure';
}

/// The backend didn't answer in time.
class TimeoutFailure extends ApiFailure {
  const TimeoutFailure();

  @override
  String toString() => 'TimeoutFailure';
}

/// The backend answered with something that doesn't match the contract.
class ContractFailure extends ApiFailure {
  const ContractFailure(this.reason, {this.statusCode});

  final String reason;

  /// The HTTP status when the reply was not JSON at all (e.g. a host's 502
  /// page while the server is down). Null when the JSON broke the contract.
  final int? statusCode;

  @override
  String toString() => 'ContractFailure($reason)';
}
