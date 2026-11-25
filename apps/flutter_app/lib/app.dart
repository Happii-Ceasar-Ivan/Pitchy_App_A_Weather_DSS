import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/app_scope.dart';
import 'core/config/app_config.dart';
import 'core/config/app_info.dart';
import 'core/network/pitchy_api.dart';
import 'core/routing/app_router.dart';
import 'core/storage/preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/conversational_agent/chat_session.dart';
import 'features/match_management/match_controller.dart';

class PitchyApp extends StatefulWidget {
  const PitchyApp({
    super.key,
    required this.config,
    required this.info,
    required this.api,
    required this.preferences,
    this.initialLocation = Routes.dashboard,
    this.clock,
  });

  final AppConfig config;
  final AppInfo info;
  final PitchyApi api;
  final Preferences preferences;
  final String initialLocation;

  /// For tests and previews; the device clock otherwise. Only used to word ages
  /// and check that a kickoff isn't in the past.
  final DateTime Function()? clock;

  @override
  State<PitchyApp> createState() => _PitchyAppState();
}

class _PitchyAppState extends State<PitchyApp> {
  late final GoRouter _router = buildRouter(initialLocation: widget.initialLocation);
  late final ThemeController _theme = ThemeController(preferences: widget.preferences);
  late final MatchController _match = MatchController(
    api: widget.api,
    preferences: widget.preferences,
    clock: widget.clock,
  )..restore();
  late final ChatSession _chatSession = ChatSession(api: widget.api);

  @override
  void dispose() {
    _router.dispose();
    _theme.dispose();
    _match.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    config: widget.config,
    info: widget.info,
    api: widget.api,
    preferences: widget.preferences,
    theme: _theme,
    match: _match,
    chatSession: _chatSession,
    child: ListenableBuilder(
      listenable: _theme,
      builder: (context, _) => MaterialApp.router(
        title: 'Pitchy',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(_theme.palette),
        routerConfig: _router,
      ),
    ),
  );
}
