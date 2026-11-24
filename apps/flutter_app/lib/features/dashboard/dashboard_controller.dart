import 'package:material_ui/material_ui.dart';

import '../../core/errors/api_failure.dart';
import '../../core/network/pitchy_api.dart';
import '../../core/state/loadable.dart';
import '../../shared/models/alerts.dart';
import '../../shared/models/weather.dart';

/// What the dashboard shows for one match: weather status (per-source states)
/// and consolidated weather (values). Both come straight from the backend.
@immutable
class DashboardData {
  const DashboardData({required this.status, required this.weather});

  final WeatherStatus status;
  final ConsolidatedWeather weather;
}

class DashboardController extends ChangeNotifier {
  DashboardController({required this.api, required this.matchContextId});

  final PitchyApi api;
  final String matchContextId;

  Loadable<DashboardData> _data = const Loading();
  Loadable<DashboardData> get data => _data;

  /// Official alerts load on their own: a failed alerts check never hides the
  /// weather, and the weather never waits for PAGASA's alert check.
  Loadable<VenueAlerts> _alerts = const Loading();
  Loadable<VenueAlerts> get alerts => _alerts;

  bool _refreshing = false;

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
    _notify();
    await Future.wait([_loadWeather(), loadAlerts()]);
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
    } on ApiFailure catch (e) {
      // A failed refresh never keeps showing older data as if it were fresh.
      _data = Failed(e);
    }
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
      // Older alerts are never kept on screen after a failed check.
      _alerts = Failed(e);
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
