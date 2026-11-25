import '../errors/api_failure.dart';

/// Client request state (FR-CLI-002: loading, success, error). Separate from the
/// weather data states (current, stale, missing, updating, unavailable), which
/// come inside a successful response.
sealed class Loadable<T> {
  const Loadable();
}

class Loading<T> extends Loadable<T> {
  const Loading();
}

class Loaded<T> extends Loadable<T> {
  const Loaded(this.value);
  final T value;
}

class Failed<T> extends Loadable<T> {
  const Failed(this.failure, {this.saved});
  final ApiFailure failure;

  /// The DEC-13 saved copy, set only when the backend could not be reached or
  /// failed itself and a copy exists. Never current: screens show it with the
  /// saved-copy banner and keep backend actions off.
  final SavedCopy<T>? saved;
}

/// A last successful reply kept on the device (DEC-13), with the time the app
/// received it.
class SavedCopy<T> {
  const SavedCopy(this.value, {required this.savedAt});

  final T value;
  final DateTime savedAt;
}
