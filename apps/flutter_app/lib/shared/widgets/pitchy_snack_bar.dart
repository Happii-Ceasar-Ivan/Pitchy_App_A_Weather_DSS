import 'package:material_ui/material_ui.dart';

import '../../core/theme/motion.dart';

/// Shows [snackBar] with Pitchy's snackbar motion (Material's floating rise,
/// exit faster than entrance; shorter under reduced motion), replacing any
/// snackbar already on screen. Use it instead of calling
/// `ScaffoldMessenger.showSnackBar` directly.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showPitchySnackBar(
  BuildContext context,
  SnackBar snackBar,
) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return null;
  messenger.hideCurrentSnackBar();
  return messenger.showSnackBar(
    snackBar,
    snackBarAnimationStyle: PitchyMotion.of(context).snackBar,
  );
}
