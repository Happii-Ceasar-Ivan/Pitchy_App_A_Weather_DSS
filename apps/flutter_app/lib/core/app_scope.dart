import 'package:material_ui/material_ui.dart';

import '../features/match_management/match_controller.dart';
import 'config/app_config.dart';
import 'config/app_info.dart';
import 'network/pitchy_api.dart';
import 'storage/preferences.dart';
import 'theme/theme_controller.dart';

/// App-wide services, provided once at the root. Plain Flutter, no extra state
/// package: screens read what they need with `AppScope.of(context)`.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.config,
    required this.info,
    required this.api,
    required this.preferences,
    required this.theme,
    required this.match,
    required super.child,
  });

  final AppConfig config;
  final AppInfo info;
  final PitchyApi api;
  final Preferences preferences;
  final ThemeController theme;
  final MatchController match;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope old) =>
      old.api != api || old.theme != theme || old.match != match || old.config != config;
}
