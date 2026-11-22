import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/network/http_pitchy_api.dart';
import 'core/network/pitchy_api.dart';
import 'core/theme/theme_controller.dart';
import 'shared/services/mock/mock_pitchy_api.dart';

void main() {
  final config = AppConfig.fromEnvironment();
  final PitchyApi api = config.useMocks
      ? MockPitchyApi()
      : HttpPitchyApi(baseUrl: config.apiBaseUrl);
  runApp(PitchyApp(config: config, api: api, theme: ThemeController()));
}
