import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';

/// How strongly a backend level is shown (team decision P-19, updated
/// 2026-11-25, option A). The backend decides the level and sends its
/// `severity` from the approved rules file; the app only maps it to a colour.
/// When `severity` is missing, the P-19 table by level id is the fallback.
/// Any other id, or none, stays neutral. The backend's own label is always
/// shown with the colour.
enum SafetyTone {
  /// A calm info style, not amber: e.g. "below the cooling-break level",
  /// whose action text says it is not a statement that conditions are safe.
  advisory,
  warning,
  danger;

  static SafetyTone? fromSeverity(String? severity) =>
      values.where((t) => t.name == severity).firstOrNull;
}

/// P-19 fallback table, used only when the backend sends no `severity`.
const _tones = <String, SafetyTone>{
  // Heat (senior and youth_u20 level sets): cooling breaks may be introduced.
  'cooling_breaks_required': SafetyTone.warning,
  // Lightning: detected within the AFC 30-second distance.
  'within_30_second_distance': SafetyTone.danger,
  // 'below_cooling_break_level' and any unknown id: neutral (null).
};

/// The fallback tone for a level id (P-19 table).
SafetyTone? safetyToneOf(String? levelId) => levelId == null ? null : _tones[levelId];

/// The backend's `severity` when it is one the app knows, else the P-19
/// fallback by level id.
SafetyTone? safetyToneFor({String? severity, String? levelId}) =>
    SafetyTone.fromSeverity(severity) ?? safetyToneOf(levelId);

(Color bg, Color fg) safetyToneColours(BuildContext context, SafetyTone tone) {
  final s = context.safetyColors;
  return switch (tone) {
    SafetyTone.advisory => (s.calmInfo, s.onCalmInfo),
    SafetyTone.warning => (s.warning, s.onWarning),
    SafetyTone.danger => (s.danger, s.onDanger),
  };
}

/// The backend's level label on its fixed colour, with an icon so colour is
/// never the only signal. Advisory and neutral levels get an outline and an
/// info icon. Every colour here is fixed (SafetyColors), never themed.
class SafetyLevelPill extends StatelessWidget {
  const SafetyLevelPill({
    super.key,
    required this.levelId,
    required this.label,
    this.severity,
    this.icon,
  });

  final String? levelId;

  /// The backend's `severity` for this level (P-19); null falls back to the
  /// table by [levelId].
  final String? severity;

  /// The backend's label, verbatim.
  final String label;

  /// Overrides the neutral icon (for example "No level"). Advisory, warning
  /// and danger levels always keep their own icons.
  final IconData? icon;

  /// Minimum height of the pill.
  static const minHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    final tone = safetyToneFor(severity: severity, levelId: levelId);
    final palette = context.palette;
    final (bg, fg) = tone == null
        ? (palette.ground, palette.ink)
        : safetyToneColours(context, tone);
    final shownIcon = switch (tone) {
      SafetyTone.danger => Icons.warning,
      SafetyTone.warning => Icons.warning_amber_rounded,
      // One icon per level everywhere (Q6): advisory is always the info icon.
      SafetyTone.advisory => Icons.info_outline,
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
          border: switch (tone) {
            null => Border.all(color: palette.hairline),
            SafetyTone.advisory => Border.all(color: context.safetyColors.calmInfoBorder),
            _ => null,
          },
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
