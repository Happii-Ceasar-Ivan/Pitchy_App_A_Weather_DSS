import 'package:material_ui/material_ui.dart';

import '../../core/errors/api_failure.dart';
import '../../core/network/pitchy_api.dart';
import '../../core/state/loadable.dart';
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

  bool _refreshing = false;

  /// True while a refresh runs over data already on screen (no skeleton then).
  bool get refreshing => _refreshing;

  bool _disposed = false;

  Future<void> load() async {
    final hasData = _data is Loaded<DashboardData>;
    if (hasData) {
      _refreshing = true;
    } else {
      _data = const Loading();
    }
    notifyListeners();
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
    } finally {
      _refreshing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
