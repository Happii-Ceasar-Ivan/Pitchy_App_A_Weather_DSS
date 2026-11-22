import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:go_router/go_router.dart';

import '../../features/conversational_agent/chat_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/dev/state_gallery_screen.dart';
import '../../features/match_management/match_setup_screen.dart';
import '../../features/settings/credits_screen.dart';
import '../../features/settings/settings_screen.dart';
import 'app_shell.dart';

/// Route paths. Screen flow: docs/frontend/f0-screen-flow.md (local).
abstract final class Routes {
  static const dashboard = '/dashboard';
  static const matchSetup = '/match/setup';
  static const chat = '/chat';
  static const settings = '/settings';
  static const credits = '/settings/credits';
  static const stateGallery = '/dev/states';
}

GoRouter buildRouter({String initialLocation = Routes.dashboard}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: Routes.dashboard, builder: (_, _) => const DashboardScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: Routes.chat, builder: (_, _) => const ChatScreen())],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.settings,
              builder: (_, _) => const SettingsScreen(),
              routes: [
                GoRoute(path: 'credits', builder: (_, _) => const CreditsScreen()),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(path: Routes.matchSetup, builder: (_, _) => const MatchSetupScreen()),
    if (kDebugMode)
      GoRoute(path: Routes.stateGallery, builder: (_, _) => const StateGalleryScreen()),
  ],
);
