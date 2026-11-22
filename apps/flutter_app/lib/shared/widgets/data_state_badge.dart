import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../models/weather.dart';
import 'dashed_border.dart';

/// The state pill: icon + word on the fixed state colour. Stale is drawn as a
/// dashed "stamp" so it reads differently from Current even in greyscale.
class DataStateBadge extends StatelessWidget {
  const DataStateBadge({super.key, required this.state, this.dense = false});

  final WeatherDataState state;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final style = context.stateColors.of(state);
    final textStyle =
        (dense ? Theme.of(context).textTheme.labelSmall : Theme.of(context).textTheme.labelMedium)
            ?.copyWith(color: style.foreground, fontWeight: FontWeight.w700);
    final pill = Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: dense ? 14 : 16, color: style.foreground),
          SizedBox(width: dense ? 3 : 4),
          Text(style.label.toUpperCase(), style: textStyle),
        ],
      ),
    );
    return Semantics(
      label: 'Data state: ${style.label}',
      excludeSemantics: true,
      child: style.dashed
          ? DashedBorder(color: style.foreground, radius: AppTheme.radiusPill, child: pill)
          : pill,
    );
  }
}
