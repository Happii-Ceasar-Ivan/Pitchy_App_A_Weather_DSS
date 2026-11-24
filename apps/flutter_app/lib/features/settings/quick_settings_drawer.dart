import 'dart:math' as math;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_scope.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/pitchy_logo.dart';
import 'update_check.dart';

/// Quick Settings (P-17): a modal drawer from the left with the Light/Dark
/// switch, Check for Updates, About Pitchy and Open full settings. Closes with
/// the close button, a tap outside, Back, or Esc.
class QuickSettingsDrawer extends StatelessWidget {
  const QuickSettingsDrawer({super.key});

  void _open(BuildContext context, String route) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop(); // close the drawer first
    router.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = scope.theme;
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final width = math.min(320.0, MediaQuery.sizeOf(context).width * 0.85);

    return Drawer(
      width: width,
      backgroundColor: palette.ground,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: theme,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: palette.shell,
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
                child: Row(
                  children: [
                    const PitchyLogo(size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pitchy', style: text.titleLarge?.copyWith(color: palette.onShell)),
                          Text(
                            'Quick settings',
                            style: text.bodySmall?.copyWith(color: palette.onShellMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: palette.onShell),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: theme.isDark,
                onChanged: theme.setDark,
                secondary: Icon(
                  theme.isDark ? Icons.dark_mode : Icons.light_mode,
                  color: palette.ink,
                ),
                thumbIcon: WidgetStateProperty.resolveWith(
                  (s) => Icon(
                    s.contains(WidgetState.selected) ? Icons.dark_mode : Icons.light_mode,
                  ),
                ),
                title: const Text('Dark mode'),
                subtitle: Text('${theme.mode.label} theme'),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.system_update_alt),
                title: const Text('Check for updates'),
                subtitle: Text('Pitchy ${scope.info.label}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  showUpdateCheck(navigator.context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About Pitchy'),
                subtitle: const Text('Version, information and credits'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, Routes.about),
              ),
              const Spacer(),
              Divider(color: palette.hairline),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => _open(context, Routes.settings),
                  icon: const Icon(Icons.settings),
                  label: const Text('Open full settings'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
