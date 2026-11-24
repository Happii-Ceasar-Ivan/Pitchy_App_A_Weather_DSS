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
  const Failed(this.failure);
  final ApiFailure failure;
}
