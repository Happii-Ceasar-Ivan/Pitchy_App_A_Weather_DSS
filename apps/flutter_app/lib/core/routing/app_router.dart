import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:go_router/go_router.dart';

import '../../features/conversational_agent/chat_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/dev/state_gallery_screen.dart';
import '../../features/match_management/match_setup_screen.dart';
import '../../features/safety/safety_screen.dart';
import '../../features/settings/about_screen.dart';
import '../../features/settings/credits_screen.dart';
import '../../features/settings/policy_pages.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/support_screen.dart';
import '../config/donations.dart';
import 'app_shell.dart';

/// Route paths. Screen flow: docs/frontend/f0-screen-flow.md (local).
abstract final class Routes {
  static const dashboard = '/dashboard';
  static const safety = '/safety';
  static const chat = '/chat';
  static const matchSetup = '/match/setup';
  static const settings = '/settings';
  static const about = '/about';
  static const credits = '/credits';
  static const privacy = '/privacy';
  static const disclaimer = '/disclaimer';
  static const support = '/support';
  static const stateGallery = '/dev/states';
}

GoRouter buildRouter({String initialLocation = Routes.dashboard}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: Routes.dashboard, builder: (_, _) => const DashboardScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: Routes.safety, builder: (_, _) => const SafetyScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: Routes.chat, builder: (_, _) => const ChatScreen())],
        ),
      ],
    ),
    // Pushed screens: Back returns to where the user came from.
    GoRoute(path: Routes.matchSetup, builder: (_, _) => const MatchSetupScreen()),
    GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
    GoRoute(path: Routes.about, builder: (_, _) => const AboutScreen()),
    GoRoute(path: Routes.credits, builder: (_, _) => const CreditsScreen()),
    GoRoute(
      path: Routes.privacy,
      builder: (_, _) => const PolicyScreen(page: PolicyPages.privacy),
    ),
    GoRoute(
      path: Routes.disclaimer,
      builder: (_, _) => const PolicyScreen(page: PolicyPages.disclaimer),
    ),
    if (Donations.maya case final qr?)
      GoRoute(
        path: Routes.support,
        builder: (_, _) => SupportScreen(qr: qr, saver: QrSaver.forThisDevice()),
      ),
    if (kDebugMode)
      GoRoute(path: Routes.stateGallery, builder: (_, _) => const StateGalleryScreen()),
  ],
);
