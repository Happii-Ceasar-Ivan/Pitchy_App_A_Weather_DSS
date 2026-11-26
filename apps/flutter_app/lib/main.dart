import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/app_licenses.dart';
import 'core/config/app_config.dart';
import 'core/config/app_info.dart';
import 'core/network/http_pitchy_api.dart';
import 'core/network/pitchy_api.dart';
import 'core/storage/preferences.dart';
import 'core/storage/saved_copies.dart';
import 'shared/services/mock/mock_pitchy_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppLicenses();
  final config = AppConfig.fromEnvironment();
  final (info, preferences) = await (AppInfo.load(), SharedPreferencesStore.open()).wait;
  // One store: the client saves into it and the screens read from it (DEC-13).
  final savedCopies = SavedCopyStore(preferences);
  final PitchyApi api = config.useMocks
      ? MockPitchyApi(savedCopies: savedCopies)
      : HttpPitchyApi(baseUrl: config.apiBaseUrl, savedCopies: savedCopies);
  runApp(
    PitchyApp(
      config: config,
      info: info,
      api: api,
      preferences: preferences,
      savedCopies: savedCopies,
    ),
  );
}
