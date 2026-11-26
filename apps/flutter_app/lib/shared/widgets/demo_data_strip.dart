import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';

/// Shown above every screen when the app runs on mock data
/// (`PITCHY_USE_MOCKS`, the default for development builds). Mock weather is
/// invented, so it must never look real. Release builds are made with
/// `PITCHY_USE_MOCKS=false`, and then this strip never appears.
///
/// Not a data-state or safety colour: the theme's accent, which stands apart
/// from the top bar in every theme (white or dark text on it is checked by the
/// theme tests).
class DemoDataStrip extends StatelessWidget {
  const DemoDataStrip({super.key, required this.child});

  final Widget child;

  static const text = 'Demo data: not real weather';
  static const spoken = 'Demo data. This is not real weather.';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: palette.onAccent, fontWeight: FontWeight.w700);
    final top = MediaQuery.paddingOf(context).top;
    // Laid out bottom-up so the strip is painted after the screens: a route
    // blocks the semantics of whatever was painted before it, and screen
    // readers must hear this. It still sits at the top.
    return Column(
      verticalDirection: VerticalDirection.up,
      children: [
        // The strip takes the status-bar inset; screens below start under it.
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
        ),
        Semantics(
          container: true,
          label: spoken,
          excludeSemantics: true,
          child: Container(
            width: double.infinity,
            color: palette.accent,
            padding: EdgeInsets.fromLTRB(16, top + 4, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.science_outlined, size: 16, color: palette.onAccent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(text, style: style, textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
