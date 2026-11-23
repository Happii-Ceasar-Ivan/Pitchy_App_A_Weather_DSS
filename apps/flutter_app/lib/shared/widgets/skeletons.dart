import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';

/// Loading placeholders shaped like the content they stand for (P-17): the
/// same cards, paddings and line heights as the real widgets, so content lands
/// where the skeleton was. A gentle pulse; static when the OS asks for reduced
/// motion. Hidden from screen readers, which hear one "Loading" label instead.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child, this.label = 'Loading'});

  final Widget child;
  final String label;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    liveRegion: true,
    child: ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween(
          begin: 0.55,
          end: 1.0,
        ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: widget.child,
      ),
    ),
  );
}

/// A rounded placeholder block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Color.alphaBlend(p.ink.withValues(alpha: 0.09), p.surface),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A placeholder occupying exactly one line of [style], with the bar drawn at
/// roughly cap height inside it (so stacked lines keep the real line spacing).
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, required this.style, this.width, this.widthFactor});

  final TextStyle? style;
  final double? width;
  final double? widthFactor;

  /// The line box height Flutter gives a single line of [style].
  static double lineHeight(BuildContext context, TextStyle? style) {
    final scaler = MediaQuery.textScalerOf(context);
    final size = scaler.scale(style?.fontSize ?? 14);
    return size * (style?.height ?? 1.2);
  }

  @override
  Widget build(BuildContext context) {
    final h = lineHeight(context, style);
    final bar = (h * 0.62).clamp(6.0, h);
    final box = SkeletonBox(width: width, height: bar, radius: bar / 2);
    return SizedBox(
      height: h,
      child: Align(
        alignment: Alignment.centerLeft,
        child: widthFactor == null
            ? box
            : FractionallySizedBox(widthFactor: widthFactor, child: box),
      ),
    );
  }
}
