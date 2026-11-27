// Motion tokens (plan v2 A3/A4, C3–C6). One motion language for the app.
//
// Animate only: overlays opening/closing, expand/collapse, a newly arrived chat
// reply, the Updating spinner and press feedback. Never: tab switches, values
// updating, safety and data-state elements, list loading.
//
// Reduced motion (Android "Remove animations", Windows "Animation effects"):
// fewer and gentler, not zero. Movement goes; short opacity changes stay.
// Safety banners, alerts, state pills and stale stamps never animate in.

import 'package:material_ui/material_ui.dart';

abstract final class PitchyMotion {
  /// Press feedback.
  static const press = Duration(milliseconds: 100);

  /// Small state changes; also the ceiling for any reduced-motion fade.
  static const quick = Duration(milliseconds: 150);

  /// Route entrances and the new chat reply.
  static const standard = Duration(milliseconds: 200);

  /// Expand and collapse (unchanged from the existing expanders).
  static const expand = Duration(milliseconds: 220);

  /// Drawer, dialogs and other overlays.
  static const overlay = Duration(milliseconds: 250);

  /// Exits are faster than entrances.
  static const exit = Duration(milliseconds: 150);

  /// Strong ease-out for anything entering.
  static const enter = Cubic(0.23, 1, 0.32, 1);

  /// Ease-in-out for something moving between two places on screen.
  static const move = Cubic(0.77, 0, 0.175, 1);

  /// Colour changes (theme switch, hover).
  static const colour = Curves.ease;

  /// The reduced-motion and normal values for this context, read once.
  static PitchyMotionSpec of(BuildContext context) =>
      PitchyMotionSpec(reduced: MediaQuery.maybeDisableAnimationsOf(context) ?? false);
}

/// Motion values for one context. Under reduced motion, movement durations are
/// zero and fades are capped at [PitchyMotion.quick].
@immutable
class PitchyMotionSpec {
  const PitchyMotionSpec({required this.reduced});

  final bool reduced;

  /// Expand (size change): instant under reduced motion.
  Duration get expand => reduced ? Duration.zero : PitchyMotion.expand;

  /// Collapse: faster than the expand (exits beat entrances); instant when
  /// reduced.
  Duration get collapse => reduced ? Duration.zero : PitchyMotion.exit;

  /// Scrolling to show something new: instant (jump) under reduced motion.
  Duration get scroll => reduced ? Duration.zero : PitchyMotion.overlay;

  /// Opacity-only fades: kept, but short, under reduced motion.
  Duration get fade => reduced ? PitchyMotion.quick : PitchyMotion.standard;

  /// Distance a newly arrived element rises (logical pixels); none when reduced.
  double get rise => reduced ? 0 : 4;
}

/// Route transitions for pushed pages (Settings, About, Match setup, …). The
/// three main tabs live in an IndexedStack and never transition (C5).
///
/// Motion on: fade in with a small rise, strong ease-out, 200 ms; exit 150 ms.
/// Reduced motion: opacity only, finished within 150 ms.
class PitchyPageTransitionsBuilder extends PageTransitionsBuilder {
  const PitchyPageTransitionsBuilder();

  @override
  Duration get transitionDuration => PitchyMotion.standard;

  @override
  Duration get reverseTransitionDuration => PitchyMotion.exit;

  static final _reducedFade = CurveTween(curve: const Interval(0, 0.75, curve: Curves.linear));
  static final _fade = CurveTween(curve: PitchyMotion.enter);
  static final _rise = Tween<Offset>(
    begin: const Offset(0, 0.02),
    end: Offset.zero,
  ).chain(CurveTween(curve: PitchyMotion.enter));

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (PitchyMotion.of(context).reduced) {
      return FadeTransition(opacity: animation.drive(_reducedFade), child: child);
    }
    return FadeTransition(
      opacity: animation.drive(_fade),
      child: SlideTransition(position: animation.drive(_rise), child: child),
    );
  }
}
