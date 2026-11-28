// Motion tokens (plan v2 A3/A4, C3–C6; P-29). One motion language for the app.
//
// Animate only: overlays opening/closing, expand/collapse, a newly arrived chat
// reply, the Updating spinner, press feedback on standalone buttons, step
// changes, validation messages, the trend chart's Value switch (the drawing
// only) and its hour marker. Never: tab
// switches, theme switches, values updating, safety and data-state elements,
// list loading.
//
// Reduced motion (Android "Remove animations", Windows "Animation effects"):
// fewer and gentler, not zero. Movement goes and size changes are instant;
// short opacity changes stay.
// Safety banners, alerts, state pills and stale stamps never animate in.

import 'package:material_ui/material_ui.dart';

abstract final class PitchyMotion {
  /// Press feedback (press-down).
  static const press = Duration(milliseconds: 100);

  /// A pressed button returning to rest.
  static const release = Duration(milliseconds: 150);

  /// How far a standalone button shrinks while held (P-29). Buttons only:
  /// never cards, list rows, data chips, nav items or hazard elements.
  static const pressScale = 0.97;

  /// The one spring (P-29): critically damped, so it never overshoots. It
  /// settles in about 270 ms. Only for something moving between two places
  /// (the trend chart's hour marker), never for values or states.
  static final spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 600, ratio: 1);

  /// Tooltips stay up this long after a long-press (Android).
  static const tooltipShow = Duration(milliseconds: 1500);

  /// Tooltips leave quickly once the pointer goes.
  static const tooltipExit = Duration(milliseconds: 100);

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

  /// Scale of a held standalone button; 1 (no movement) when reduced.
  double get pressScale => reduced ? 1 : PitchyMotion.pressScale;

  /// A switch between two views of the same thing (a step change, the trend
  /// chart's Value): the incoming view's fade.
  Duration get switchIn => reduced ? PitchyMotion.quick : PitchyMotion.standard;

  /// The outgoing view's fade; faster than [switchIn].
  Duration get switchOut => reduced ? messageOut : PitchyMotion.exit;

  /// A small message appearing in place (form validation): a short fade.
  Duration get message => PitchyMotion.quick;

  /// A small message (or any reduced-motion fade) leaving: faster than it came.
  Duration get messageOut => const Duration(milliseconds: 100);

  /// Whether the spring runs; when reduced, things jump to their place.
  bool get spring => !reduced;

  /// Snackbars: Material's rise, exit faster than entrance.
  AnimationStyle get snackBar => AnimationStyle(
    duration: reduced ? PitchyMotion.quick : PitchyMotion.overlay,
    reverseDuration: reduced ? messageOut : PitchyMotion.exit,
  );
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

  /// The same small rise as everything else ([PitchyMotionSpec.rise], 4 px),
  /// not a share of the page height.
  static const _risePx = 4.0;

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
    // Ease-out both ways: the exit curve is flipped because it runs backwards,
    // so a closing page fades fast instead of lingering (no ease-in).
    final curved = CurvedAnimation(
      parent: animation,
      curve: PitchyMotion.enter,
      reverseCurve: PitchyMotion.enter.flipped,
    );
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) =>
            Transform.translate(offset: Offset(0, _risePx * (1 - curved.value)), child: child),
        child: child,
      ),
    );
  }
}
