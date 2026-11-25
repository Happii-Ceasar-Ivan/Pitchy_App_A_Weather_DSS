import 'package:material_ui/material_ui.dart';

import '../features/conversational_agent/chat_session.dart';
import '../features/match_management/match_controller.dart';
import 'config/app_config.dart';
import 'config/app_info.dart';
import 'network/pitchy_api.dart';
import 'storage/preferences.dart';
import 'storage/saved_copies.dart';
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
    required this.savedCopies,
    required this.theme,
    required this.match,
    required this.chatSession,
    required super.child,
  });

  final AppConfig config;
  final AppInfo info;
  final PitchyApi api;
  final Preferences preferences;

  /// DEC-13 saved copies (last successful reads, shown only offline).
  final SavedCopyStore savedCopies;
  final ThemeController theme;
  final MatchController match;

  /// The anonymous chat session, shared by every chat in this app run.
  final ChatSession chatSession;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope old) =>
      old.api != api ||
      old.savedCopies != savedCopies ||
      old.theme != theme ||
      old.match != match ||
      old.chatSession != chatSession ||
      old.config != config;
}
