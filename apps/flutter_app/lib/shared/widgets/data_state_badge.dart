import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../models/weather.dart';
import 'dashed_border.dart';

/// Marks a subtree as the DEC-13 saved copy (server unreachable). Inside it no
/// state pill reads Current or Updating, whatever the saved reply said: a copy
/// is never labelled live. Other states (Stale, Missing, Unavailable) show as
/// the backend sent them; nothing is recalculated.
class SavedCopyScope extends InheritedWidget {
  const SavedCopyScope({super.key, required this.savedAt, required super.child});

  final DateTime savedAt;

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SavedCopyScope>() != null;

  @override
  bool updateShouldNotify(SavedCopyScope old) => old.savedAt != savedAt;
}

/// True when [state] would claim live data inside a [SavedCopyScope].
bool claimsLiveInSavedCopy(BuildContext context, WeatherDataState state) =>
    (state == WeatherDataState.current || state == WeatherDataState.updating) &&
    SavedCopyScope.isActive(context);

/// Pill wording for a saved copy that held Current or Updating.
const savedCopyLabel = 'Saved copy';

/// Pill wording for a backend Stale state inside a saved copy: the same
/// colours as [savedCopyLabel], so the word says it is both (F5 P2-1). The
/// state itself is the backend's and is not changed.
const staleSavedLabel = 'Stale · saved';

/// The word for [state] as shown here: [savedCopyLabel] inside a saved copy
/// when the state would claim live data, [staleSavedLabel] for a saved Stale,
/// else the state's own label.
/// [stateWord] as a screen reader should say it: "Stale, saved copy" rather
/// than reading the dot of "Stale · saved".
String spokenStateWord(BuildContext context, WeatherDataState state) {
  final word = stateWord(context, state);
  return word == staleSavedLabel ? 'Stale, saved copy' : word;
}

String stateWord(BuildContext context, WeatherDataState state) {
  if (claimsLiveInSavedCopy(context, state)) return savedCopyLabel;
  if (state == WeatherDataState.stale && SavedCopyScope.isActive(context)) return staleSavedLabel;
  return context.stateColors.of(state).label;
}

/// The state pill: icon + word on the fixed state colour. Stale is drawn as a
/// dashed "stamp" so it reads differently from Current even in greyscale.
class DataStateBadge extends StatelessWidget {
  const DataStateBadge({super.key, required this.state, this.dense = false});

  final WeatherDataState state;
  final bool dense;

  /// Height of a dense pill, for skeletons that stand in for one.
  static double denseHeight(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    final line =
        MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 11) * (style?.height ?? 1.45);
    return (line > 14 ? line : 14) + 4;
  }

  @override
  Widget build(BuildContext context) {
    final saved = claimsLiveInSavedCopy(context, state);
    // A saved Current/Updating uses the Stale colours and stamp, so it never
    // looks like the live green.
    final style = context.stateColors.of(saved ? WeatherDataState.stale : state);
    final label = stateWord(context, state);
    final icon = saved ? Icons.cloud_off : style.icon;
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
          Icon(icon, size: dense ? 14 : 16, color: style.foreground),
          SizedBox(width: dense ? 3 : 4),
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: 'Data state: ${spokenStateWord(context, state)}',
      excludeSemantics: true,
      child: style.dashed
          ? DashedBorder(color: style.foreground, radius: AppTheme.radiusPill, child: pill)
          : pill,
    );
  }
}
