import 'package:material_ui/material_ui.dart';

import '../../core/errors/api_failure.dart';
import '../../core/network/pitchy_api.dart';
import '../../core/state/loadable.dart';
import '../../core/storage/saved_copies.dart';
import '../../shared/models/alerts.dart';
import '../../shared/models/weather.dart';
import 'trend/trend_series.dart' show trendHours, trendHoursBefore;

/// What the dashboard shows for one match: weather status (per-source states)
/// and consolidated weather (values). Both come straight from the backend.
@immutable
class DashboardData {
  const DashboardData({required this.status, required this.weather});

  final WeatherStatus status;
  final ConsolidatedWeather weather;
}

class DashboardController extends ChangeNotifier {
  DashboardController({
    required this.api,
    required this.matchContextId,
    this.savedCopies,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  final PitchyApi api;
  final String matchContextId;

  /// The DEC-13 saved copies; null turns the fallback off.
  final SavedCopyStore? savedCopies;

  Loadable<DashboardData> _data = const Loading();
  Loadable<DashboardData> get data => _data;

  /// Official alerts load on their own: a failed alerts check never hides the
  /// weather, and the weather never waits for PAGASA's alert check.
  Loadable<VenueAlerts> _alerts = const Loading();
  Loadable<VenueAlerts> get alerts => _alerts;

  /// The hourly trend window (P-27), kickoff - 6 h to + 5 h in one call. Loads
  /// on its own like the alerts: a failed trend never hides the tiles.
  Loadable<ConsolidatedWeather> _trend = const Loading();
  Loadable<ConsolidatedWeather> get trend => _trend;

  bool _refreshing = false;

  /// How many loads in a row fell back to the saved copy, and when the last
  /// one ended (F5 P2-2): the banner says "still" after a failed Try again,
  /// so a second failure is seen and heard. Reset when the server answers.
  int get savedCopyTries => _savedCopyTries;
  int _savedCopyTries = 0;
  DateTime? get lastTriedAt => _lastTriedAt;
  DateTime? _lastTriedAt;

  void _countTry(bool fellBack) {
    _savedCopyTries = fellBack ? _savedCopyTries + 1 : 0;
    _lastTriedAt = fellBack ? _clock().toUtc() : null;
  }

  /// True while a refresh runs over data already on screen (no skeleton then).
  bool get refreshing => _refreshing;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (_data is Loaded<DashboardData>) {
      _refreshing = true;
    } else {
      _data = const Loading();
    }
    if (_alerts is! Loaded<VenueAlerts>) _alerts = const Loading();
    if (_trend is! Loaded<ConsolidatedWeather>) _trend = const Loading();
    _notify();
    await Future.wait([_loadWeather(), loadAlerts(), loadTrend()]);
    _refreshing = false;
    _notify();
  }

  Future<void> _loadWeather() async {
    try {
      final results = await Future.wait([
        api.getWeatherStatus(matchContextId),
        api.getWeather(matchContextId),
      ]);
      _data = Loaded(
        DashboardData(
          status: results[0] as WeatherStatus,
          weather: results[1] as ConsolidatedWeather,
        ),
      );
      _countTry(false);
    } on ApiFailure catch (e) {
      // A failed refresh never keeps showing older data as if it were fresh:
      // at most the saved copy, labelled as one.
      final saved = _savedBoard(e);
      _data = Failed(e, saved: saved);
      _countTry(saved != null);
    }
  }

  /// The saved board, only when both halves were saved. Its time is the older
  /// of the two, so the banner never makes the copy look newer than it is.
  SavedCopy<DashboardData>? _savedBoard(ApiFailure e) {
    final store = savedCopies;
    if (store == null || !allowsSavedCopy(e)) return null;
    final status = store.read(matchContextId, SavedKind.weatherStatus, WeatherStatus.fromJson);
    final weather = store.read(matchContextId, SavedKind.weather, ConsolidatedWeather.fromJson);
    if (status == null || weather == null) return null;
    return SavedCopy(
      DashboardData(status: status.value, weather: weather.value),
      savedAt: status.savedAt.isBefore(weather.savedAt) ? status.savedAt : weather.savedAt,
    );
  }

  /// Tries the trend again (after a failed load).
  Future<void> retryTrend() {
    _trend = const Loading();
    _notify();
    return loadTrend();
  }

  /// Loads the trend window only. Read-only and cache-only on the backend.
  Future<void> loadTrend() async {
    try {
      _trend = Loaded(
        await api.getWeather(matchContextId, hours: trendHours, hoursBefore: trendHoursBefore),
      );
    } on ApiFailure catch (e) {
      // Never the previous live trend after a failure: only the labelled
      // saved copy, and only when the server can't be reached.
      _trend = Failed(
        e,
        saved: allowsSavedCopy(e)
            ? savedCopies?.read(matchContextId, SavedKind.trend, ConsolidatedWeather.fromJson)
            : null,
      );
    }
    _notify();
  }

  /// Tries the official alerts again (after a failed check).
  Future<void> retryAlerts() {
    _alerts = const Loading();
    _notify();
    return loadAlerts();
  }

  /// Loads the official alerts only.
  Future<void> loadAlerts() async {
    try {
      _alerts = Loaded(await api.getAlerts(matchContextId));
    } on ApiFailure catch (e) {
      // Older alerts are never kept on screen after a failed check, except as
      // the labelled saved copy when the server can't be reached.
      _alerts = Failed(
        e,
        saved: allowsSavedCopy(e)
            ? savedCopies?.read(matchContextId, SavedKind.alerts, VenueAlerts.fromJson)
            : null,
      );
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
