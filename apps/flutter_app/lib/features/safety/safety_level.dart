import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';

/// The fixed safety colour a backend level gets (team decision P-19,
/// 2026-11-24). The backend decides the level; this only picks a colour for
/// level ids from the approved rules (`rules.yaml`). Any other id, or none,
/// stays neutral. The backend's own label is always shown with the colour.
enum SafetyTone { warning, danger }

const _tones = <String, SafetyTone>{
  // Heat (senior and youth_u20 level sets): cooling breaks may be introduced.
  'cooling_breaks_required': SafetyTone.warning,
  // Lightning: detected within the AFC 30-second distance.
  'within_30_second_distance': SafetyTone.danger,
  // 'below_cooling_break_level' and any unknown id: neutral (null).
};

SafetyTone? safetyToneOf(String? levelId) => levelId == null ? null : _tones[levelId];

(Color bg, Color fg) safetyToneColours(BuildContext context, SafetyTone tone) {
  final s = context.safetyColors;
  return switch (tone) {
    SafetyTone.warning => (s.warning, s.onWarning),
    SafetyTone.danger => (s.danger, s.onDanger),
  };
}

/// The backend's level label on its fixed colour, with an icon so colour is
/// never the only signal. Neutral levels get a hairline outline and an info icon.
class SafetyLevelPill extends StatelessWidget {
  const SafetyLevelPill({super.key, required this.levelId, required this.label, this.icon});

  final String? levelId;

  /// The backend's label, verbatim.
  final String label;

  /// Overrides the neutral icon (for example "No level"). Warning and danger
  /// levels always keep their own icons.
  final IconData? icon;

  /// Minimum height of the pill.
  static const minHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    final tone = safetyToneOf(levelId);
    final palette = context.palette;
    final (bg, fg) = tone == null
        ? (palette.ground, palette.ink)
        : safetyToneColours(context, tone);
    final shownIcon = switch (tone) {
      SafetyTone.danger => Icons.warning,
      SafetyTone.warning => Icons.warning_amber_rounded,
      null => icon ?? Icons.info_outline,
    };
    return Semantics(
      label: 'Level: $label',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: tone == null ? Border.all(color: palette.hairline) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(shownIcon, size: 20, color: fg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
