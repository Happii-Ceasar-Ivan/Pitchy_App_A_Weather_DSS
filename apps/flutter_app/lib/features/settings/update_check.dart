import 'package:material_ui/material_ui.dart';

import '../../core/app_scope.dart';

/// Check for Updates (P-17). Release signing and distribution (P-08) are not
/// decided, so there is nothing to check against yet: show the installed
/// version and say so plainly. Never fake a check.
Future<void> showUpdateCheck(BuildContext context) {
  final info = AppScope.of(context).info;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.system_update_alt),
      title: const Text('Check for updates'),
      content: Text(
        'You have Pitchy ${info.label}.\n\n'
        'Automatic update checks aren’t set up yet. New versions will be announced by the '
        'Pitchy team.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
      ],
    ),
  );
}
