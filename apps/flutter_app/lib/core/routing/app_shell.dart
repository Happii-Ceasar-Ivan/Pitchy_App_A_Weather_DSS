import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/settings/quick_settings_drawer.dart';
import '../theme/app_theme.dart';

/// Lets a screen's top bar open the Quick Settings drawer, which belongs to the
/// shell (P-17).
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.openSettings, required super.child});

  final VoidCallback openSettings;

  static ShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope old) => false;
}

/// Main navigation, matched to window size (Material): a bottom navigation bar
/// on phones, a navigation rail on the shell colour on wide windows. Settings
/// lives in the Quick Settings drawer, opened from the top-left button (P-17).
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// Width at which the rail replaces the bottom bar (Material "medium").
  static const railBreakpoint = 600.0;

  static const destinations = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
    (Icons.health_and_safety_outlined, Icons.health_and_safety, 'Safety'),
    (Icons.forum_outlined, Icons.forum, 'Ask Pitchy'),
  ];

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffold = GlobalKey<ScaffoldState>();

  void _go(int index) =>
      widget.shell.goBranch(index, initialLocation: index == widget.shell.currentIndex);

  void _openSettings() => _scaffold.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppShell.railBreakpoint;
    final body = ShellScope(openSettings: _openSettings, child: widget.shell);
    return CallbackShortcuts(
      // Esc closes the drawer on Windows (Back already does on Android).
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_scaffold.currentState?.isDrawerOpen ?? false) _scaffold.currentState!.closeDrawer();
        },
      },
      child: Scaffold(
        key: _scaffold,
        drawer: const QuickSettingsDrawer(),
        body: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: widget.shell.currentIndex,
                    onDestinationSelected: _go,
                    labelType: NavigationRailLabelType.all,
                    minWidth: 88,
                    groupAlignment: -0.85,
                    destinations: [
                      for (final (icon, selected, label) in AppShell.destinations)
                        NavigationRailDestination(
                          icon: Icon(icon),
                          selectedIcon: Icon(selected),
                          label: Text(label),
                        ),
                    ],
                  ),
                  VerticalDivider(width: AppTheme.hairline, color: context.palette.hairline),
                  Expanded(child: body),
                ],
              )
            : body,
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: widget.shell.currentIndex,
                onDestinationSelected: _go,
                destinations: [
                  for (final (icon, selected, label) in AppShell.destinations)
                    NavigationDestination(
                      icon: Icon(icon),
                      selectedIcon: Icon(selected),
                      label: label,
                    ),
                ],
              ),
      ),
    );
  }
}
