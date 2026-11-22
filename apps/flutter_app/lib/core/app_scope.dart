import 'package:material_ui/material_ui.dart';

import 'config/app_config.dart';
import 'network/pitchy_api.dart';
import 'theme/theme_controller.dart';

/// App-wide services, provided once at the root. Plain Flutter, no extra state
/// package: screens read what they need with `AppScope.of(context)`.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.config,
    required this.api,
    required this.theme,
    required super.child,
  });

  final AppConfig config;
  final PitchyApi api;
  final ThemeController theme;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope old) =>
      old.api != api || old.theme != theme || old.config != config;
}
