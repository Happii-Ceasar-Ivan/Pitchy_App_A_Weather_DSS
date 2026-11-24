import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/config/app_info.dart';
import 'core/network/http_pitchy_api.dart';
import 'core/network/pitchy_api.dart';
import 'core/storage/preferences.dart';
import 'shared/services/mock/mock_pitchy_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final PitchyApi api = config.useMocks
      ? MockPitchyApi()
      : HttpPitchyApi(baseUrl: config.apiBaseUrl);
  final (info, preferences) = await (AppInfo.load(), SharedPreferencesStore.open()).wait;
  runApp(PitchyApp(config: config, info: info, api: api, preferences: preferences));
}
