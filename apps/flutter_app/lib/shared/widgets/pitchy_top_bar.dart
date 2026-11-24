import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/routing/app_router.dart';
import '../../core/routing/app_shell.dart';
import 'pitchy_logo.dart';

/// Top app bar for every screen (P-13, P-17): on top-level screens the settings
/// button sits top left, then the Pitchy logo, then the screen name. On pushed
/// screens the Back arrow takes the settings button's place; a screen opened
/// directly gets a Back to dashboard arrow.
class PitchyTopBar extends StatelessWidget implements PreferredSizeWidget {
  const PitchyTopBar({super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final shell = ShellScope.maybeOf(context);
    return AppBar(
      automaticallyImplyLeading: canPop,
      leading: canPop
          ? null
          : shell != null
          ? IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Quick settings',
              onPressed: shell.openSettings,
            )
          // Opened directly (a link or restored route): there is nothing to go
          // back to, and Windows has no system Back, so offer the way home.
          : IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to dashboard',
              onPressed: () => context.go(Routes.dashboard),
            ),
      titleSpacing: 0,
      title: Row(
        children: [
          const PitchyLogo(size: 32),
          const SizedBox(width: 12),
          Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
        ],
      ),
      actions: actions,
    );
  }
}
