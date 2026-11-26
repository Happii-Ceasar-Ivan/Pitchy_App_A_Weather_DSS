import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/app_scope.dart';
import 'core/config/app_config.dart';
import 'core/config/app_info.dart';
import 'core/network/pitchy_api.dart';
import 'core/routing/app_router.dart';
import 'core/storage/preferences.dart';
import 'core/storage/saved_copies.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/conversational_agent/chat_session.dart';
import 'features/match_management/match_controller.dart';
import 'features/settings/update_check.dart';
import 'features/settings/update_dialog.dart';
import 'features/settings/update_installer.dart';
import 'shared/widgets/demo_data_strip.dart';

class PitchyApp extends StatefulWidget {
  const PitchyApp({
    super.key,
    required this.config,
    required this.info,
    required this.api,
    required this.preferences,
    this.savedCopies,
    this.initialLocation = Routes.dashboard,
    this.clock,
    this.updates,
    this.updateInstaller,
    this.checkForUpdatesOnOpen = true,
  });

  final AppConfig config;
  final AppInfo info;
  final PitchyApi api;
  final Preferences preferences;

  /// The DEC-13 store. Pass the same instance the API client saves into;
  /// defaults to one over [preferences].
  final SavedCopyStore? savedCopies;
  final String initialLocation;

  /// For tests and previews; the device clock otherwise. Only used to word ages
  /// and check that a kickoff isn't in the past.
  final DateTime Function()? clock;

  /// For tests; a real check against GitHub releases otherwise.
  final UpdateChecker? updates;

  /// For tests; downloads to this device's installer otherwise.
  final UpdateInstaller? updateInstaller;

  /// Ask GitHub for a newer version when the app opens, at most once a day
  /// (P-26). Tests turn it off unless they test it.
  final bool checkForUpdatesOnOpen;

  @override
  State<PitchyApp> createState() => _PitchyAppState();
}

class _PitchyAppState extends State<PitchyApp> {
  late final UpdateChecker _updates =
      widget.updates ?? UpdateChecker(installedVersion: widget.info.version);
  late final UpdateInstaller _updateInstaller =
      widget.updateInstaller ?? UpdateInstaller(platform: UpdatePlatform.forThisDevice());
  late final GoRouter _router = buildRouter(initialLocation: widget.initialLocation);
  late final ThemeController _theme = ThemeController(preferences: widget.preferences);
  late final SavedCopyStore _savedCopies =
      (widget.savedCopies ?? SavedCopyStore(widget.preferences, clock: widget.clock))
        ..purgeExpired();
  late final MatchController _match = MatchController(
    api: widget.api,
    preferences: widget.preferences,
    clock: widget.clock,
    savedCopies: _savedCopies,
  )..restore();
  late final ChatSession _chatSession = ChatSession(api: widget.api);

  @override
  void initState() {
    super.initState();
    if (widget.checkForUpdatesOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdatesOnOpen());
    }
  }

  /// At most once a day; quiet unless there is a newer version. A failed check
  /// isn't recorded, so the next app open tries again.
  Future<void> _checkForUpdatesOnOpen() async {
    final now = (widget.clock ?? DateTime.now)().toUtc();
    final last = DateTime.tryParse(widget.preferences.getString(PrefKeys.lastUpdateCheck) ?? '');
    if (last != null && now.difference(last) < const Duration(days: 1) && !last.isAfter(now)) {
      return;
    }
    final result = await _updates.check();
    if (result is CheckFailed) return;
    await widget.preferences.setString(PrefKeys.lastUpdateCheck, now.toIso8601String());
    final context = _router.routerDelegate.navigatorKey.currentContext;
    if (result is UpdateAvailable && mounted && context != null && context.mounted) {
      await showUpdatePrompt(context, result);
    }
  }

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
    savedCopies: _savedCopies,
    theme: _theme,
    match: _match,
    chatSession: _chatSession,
    updates: _updates,
    updateInstaller: _updateInstaller,
    child: ListenableBuilder(
      listenable: _theme,
      builder: (context, _) => MaterialApp.router(
        title: 'Pitchy',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(_theme.palette),
        routerConfig: _router,
        // Mock builds say so on every screen; release builds never show it.
        builder: widget.config.useMocks
            ? (context, child) => DemoDataStrip(child: child ?? const SizedBox.shrink())
            : null,
      ),
    ),
  );
}
