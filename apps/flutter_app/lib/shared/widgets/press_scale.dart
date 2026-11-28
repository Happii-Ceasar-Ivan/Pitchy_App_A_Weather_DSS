import 'package:material_ui/material_ui.dart';

import '../../core/theme/motion.dart';

/// Press feedback for a standalone button (P-29): it shrinks to
/// [PitchyMotion.pressScale] on press-down and returns on release, on top of
/// the button's own ripple.
///
/// Wrap filled, outlined and text buttons, the send button, top-bar icon
/// buttons and dialog actions. Never wrap cards, list rows, chips that carry
/// data, nav items, or any hazard, safety or data-state element.
///
/// The scale is a paint transform, so the layout box never changes. It reads
/// pointers through a [Listener], so it never takes the tap or the ripple from
/// the button. Keyboard activation doesn't scale (the focus ring is the
/// feedback). Pass [enabled] `false` for a disabled button. Under reduced
/// motion nothing moves.
class PitchyPressScale extends StatefulWidget {
  const PitchyPressScale({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// Whether the wrapped button can be pressed; a disabled button stays still.
  final bool enabled;

  @override
  State<PitchyPressScale> createState() => _PitchyPressScaleState();
}

class _PitchyPressScaleState extends State<PitchyPressScale> with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: PitchyMotion.press,
    reverseDuration: PitchyMotion.release,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _press,
    curve: PitchyMotion.enter,
    reverseCurve: PitchyMotion.enter.flipped,
  );

  @override
  void didUpdateWidget(PitchyPressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _press.value = 0;
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent _) {
    if (widget.enabled) _press.forward();
  }

  void _up(PointerEvent _) {
    if (_press.value > 0 || _press.isAnimating) _press.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final scale = PitchyMotion.of(context).pressScale;
    if (scale == 1) {
      if (_press.value != 0) _press.value = 0;
      return widget.child;
    }
    return Listener(
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) =>
            Transform.scale(scale: 1 - (1 - scale) * _curve.value, child: child),
        child: widget.child,
      ),
    );
  }
}
