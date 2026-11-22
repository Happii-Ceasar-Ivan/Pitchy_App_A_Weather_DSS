import 'package:material_ui/material_ui.dart';

import 'pitchy_logo.dart';

/// Top app bar for every screen: the Pitchy logo to the left of the screen name
/// (P-13), on the shell colour.
class PitchyTopBar extends StatelessWidget implements PreferredSizeWidget {
  const PitchyTopBar({super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return AppBar(
      automaticallyImplyLeading: canPop,
      titleSpacing: canPop ? 0 : 16,
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
