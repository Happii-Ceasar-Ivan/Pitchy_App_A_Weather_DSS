import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../models/alerts.dart';

/// The fixed warning colour an official alert gets, read from PAGASA's own
/// level words (team decision P-18, 2026-11-24). The app never grades an alert
/// itself: an alert whose level words it doesn't recognise stays neutral.
enum AlertLevel {
  /// Yellow: thunderstorm watch, yellow rainfall warning, storm signal No. 1.
  advisory,

  /// Orange: thunderstorm advisory, orange rainfall warning, signals No. 2–3.
  warning,

  /// Red: thunderstorm warning, red rainfall warning, signals No. 4–5.
  danger,
}

bool _word(String text, String w) => RegExp('\\b$w\\b').hasMatch(text);

final _signal = RegExp(r'signal\s*(?:no\.?|number|#)?\s*([1-5])\b');

/// PAGASA's scale, as decided by the team:
/// - Rainfall warnings: Yellow, Orange, Red.
/// - Tropical cyclone wind signals: No. 1 yellow, No. 2–3 orange, No. 4–5 red.
/// - Thunderstorms: Watch yellow, Advisory orange, Warning red.
/// Anything else returns null (neutral).
AlertLevel? alertLevelOf(OfficialAlert a) {
  final kind = '${a.event} ${a.subtype}'.toLowerCase();
  final all = '$kind ${a.headline}'.toLowerCase();

  if (all.contains('rainfall')) {
    if (_word(all, 'red')) return AlertLevel.danger;
    if (_word(all, 'orange')) return AlertLevel.warning;
    if (_word(all, 'yellow')) return AlertLevel.advisory;
    return null;
  }
  if (all.contains('signal') && (all.contains('cyclone') || all.contains('wind'))) {
    final n = int.tryParse(_signal.firstMatch(all)?.group(1) ?? '');
    return switch (n) {
      1 => AlertLevel.advisory,
      2 || 3 => AlertLevel.warning,
      4 || 5 => AlertLevel.danger,
      _ => null,
    };
  }
  if (kind.contains('thunderstorm')) {
    if (kind.contains('warning')) return AlertLevel.danger;
    if (kind.contains('advisory')) return AlertLevel.warning;
    if (kind.contains('watch')) return AlertLevel.advisory;
  }
  return null;
}

/// Most severe first; unrecognised levels last. Stable for equal levels.
List<OfficialAlert> bySeverity(List<OfficialAlert> alerts) {
  int rank(OfficialAlert a) => switch (alertLevelOf(a)) {
    AlertLevel.danger => 0,
    AlertLevel.warning => 1,
    AlertLevel.advisory => 2,
    null => 3,
  };
  final indexed = alerts.indexed.toList()
    ..sort((x, y) {
      final r = rank(x.$2).compareTo(rank(y.$2));
      return r != 0 ? r : x.$1.compareTo(y.$1);
    });
  return [for (final (_, a) in indexed) a];
}

(Color, Color) _colours(BuildContext context, AlertLevel level) {
  final s = context.safetyColors;
  return switch (level) {
    AlertLevel.advisory => (s.advisory, s.onAdvisory),
    AlertLevel.warning => (s.warning, s.onWarning),
    AlertLevel.danger => (s.danger, s.onDanger),
  };
}

/// The 24 px leading mark of an alert row: a filled tile in the level's fixed
/// colour with a warning icon, or the plain megaphone when the level is unknown.
class AlertLevelMark extends StatelessWidget {
  const AlertLevelMark({super.key, required this.level});

  final AlertLevel? level;

  @override
  Widget build(BuildContext context) {
    final level = this.level;
    if (level == null) {
      return Icon(Icons.campaign_outlined, size: 24, color: context.palette.ink);
    }
    final (bg, fg) = _colours(context, level);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Icon(
        level == AlertLevel.danger ? Icons.warning : Icons.warning_amber_rounded,
        size: 16,
        color: fg,
      ),
    );
  }
}

/// PAGASA's own level words on the level's fixed colour, e.g. "THUNDERSTORM
/// WATCH". Word and colour together, so colour is never the only signal.
class AlertLevelPill extends StatelessWidget {
  const AlertLevelPill({super.key, required this.alert});

  final OfficialAlert alert;

  @override
  Widget build(BuildContext context) {
    final level = alertLevelOf(alert);
    final words = (alert.subtype.isNotEmpty ? alert.subtype : alert.event).toUpperCase();
    final palette = context.palette;
    final (bg, fg) = level == null ? (palette.ground, palette.ink) : _colours(context, level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: level == null ? Border.all(color: palette.hairline) : null,
      ),
      child: Text(
        words,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}
