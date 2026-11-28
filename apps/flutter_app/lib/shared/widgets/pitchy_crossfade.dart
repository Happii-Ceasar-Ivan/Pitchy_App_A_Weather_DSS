import 'package:material_ui/material_ui.dart';

import '../../core/theme/motion.dart';

/// A switch between two views of the same place: a step change (Ask Pitchy's
/// welcome → chat) or another view of the same data (the trend chart's Value).
///
/// The incoming view fades in with a small rise ([PitchyMotionSpec.rise]);
/// the outgoing one fades out faster. Under reduced motion it is opacity only,
/// within 150 ms. Give each child a distinct [Key] so a change is noticed.
///
/// Never use it for weather values, data states or safety and hazard
/// elements: those change on the frame the data arrives.
class PitchyCrossfade extends StatelessWidget {
  const PitchyCrossfade({super.key, required this.child, this.alignment = Alignment.topCenter});

  final Widget child;

  /// Where the views sit while both are on screen.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final motion = PitchyMotion.of(context);
    return AnimatedSwitcher(
      duration: motion.switchIn,
      reverseDuration: motion.switchOut,
      switchInCurve: PitchyMotion.enter,
      // Applied backwards on exit; flipped so the old view fades fast, then settles.
      switchOutCurve: PitchyMotion.enter.flipped,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) {
        final rise = motion.rise;
        final faded = FadeTransition(opacity: animation, child: child);
        if (rise == 0) return faded;
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) =>
              Transform.translate(offset: Offset(0, rise * (1 - animation.value)), child: child),
          child: faded,
        );
      },
      child: child,
    );
  }
}
