import 'api_failure.dart';

/// Plain-language title and recovery for a failed request. Never exposes request
/// URLs, tokens or raw backend text beyond its safe generic message.
class FailureMessage {
  const FailureMessage({required this.title, required this.detail, required this.canRetry});

  final String title;
  final String detail;
  final bool canRetry;
}

FailureMessage describeFailure(ApiFailure failure) => switch (failure) {
  NetworkFailure() => const FailureMessage(
    title: 'No connection',
    detail: 'Pitchy can’t reach its server. Check your internet connection, then try again.',
    canRetry: true,
  ),
  TimeoutFailure() => const FailureMessage(
    title: 'The server is taking too long',
    detail: 'It may be starting up. Try again in a moment.',
    canRetry: true,
  ),
  ContractFailure() => const FailureMessage(
    title: 'Unexpected reply from the server',
    detail: 'This app version may be out of date with the server. Nothing was changed.',
    canRetry: true,
  ),
  ApiError(code: ApiErrorCode.notImplemented) => const FailureMessage(
    title: 'Not available yet',
    detail: 'This part of Pitchy is still being built on the server.',
    canRetry: false,
  ),
  ApiError(code: ApiErrorCode.notFound) => const FailureMessage(
    title: 'Not found',
    detail: 'This match may have been removed. Set up the match again.',
    canRetry: false,
  ),
  ApiError(code: ApiErrorCode.rateLimited) => const FailureMessage(
    title: 'Too many requests',
    detail: 'Wait until the time shown, then try again.',
    canRetry: false,
  ),
  ApiError(code: ApiErrorCode.serviceUnavailable) => const FailureMessage(
    title: 'Server temporarily unavailable',
    detail: 'Try again in a few minutes.',
    canRetry: true,
  ),
  ApiError() => const FailureMessage(
    title: 'Something went wrong',
    detail: 'The request didn’t complete. Try again.',
    canRetry: true,
  ),
};
