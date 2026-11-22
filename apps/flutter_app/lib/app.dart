import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/app_scope.dart';
import 'core/config/app_config.dart';
import 'core/network/pitchy_api.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';

class PitchyApp extends StatefulWidget {
  const PitchyApp({
    super.key,
    required this.config,
    required this.api,
    required this.theme,
    this.initialLocation = Routes.dashboard,
  });

  final AppConfig config;
  final PitchyApi api;
  final ThemeController theme;
  final String initialLocation;

  @override
  State<PitchyApp> createState() => _PitchyAppState();
}

class _PitchyAppState extends State<PitchyApp> {
  late final GoRouter _router = buildRouter(initialLocation: widget.initialLocation);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    config: widget.config,
    api: widget.api,
    theme: widget.theme,
    child: ListenableBuilder(
      listenable: widget.theme,
      builder: (context, _) => MaterialApp.router(
        title: 'Pitchy',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(widget.theme.palette),
        routerConfig: _router,
      ),
    ),
  );
}
