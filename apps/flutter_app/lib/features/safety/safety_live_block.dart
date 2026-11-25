import 'package:material_ui/material_ui.dart';

import '../../core/errors/api_failure.dart';
import '../../core/errors/failure_messages.dart';
import '../../core/state/loadable.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/assessment.dart';
import '../../shared/models/lightning.dart';
import '../../shared/models/weather.dart';
import '../../shared/widgets/dashed_border.dart';
import '../../shared/widgets/data_state_badge.dart';
import '../../shared/widgets/link_text.dart';
import '../../shared/widgets/skeletons.dart';
import 'safety_level.dart';
import 'safety_widgets.dart';

/// Words for the backend's `shown_because` codes. Any other code is shown as sent.
String shownBecauseWords(String code) => switch (code) {
  'LIGHTNING_DETECTED' => 'Lightning detected nearby',
  'PAGASA_THUNDERSTORM_ALERT' => 'PAGASA thunderstorm alert for this area',
  _ => code,
};

/// Numbered official procedure steps, verbatim.
class ProcedureSteps extends StatelessWidget {
  const ProcedureSteps(this.steps, {super.key});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var n = 0; n < steps.length; n++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 24, child: Text('${n + 1}.', style: style)),
                Expanded(child: Text(steps[n], style: style)),
              ],
            ),
          ),
      ],
    );
  }
}

/// The live lightning reading (`/lightning`): state, last check, what was
/// detected, the live level when it differs from the assessment's, the official
/// procedure when the backend shows it, the note and the attribution.
///
/// Shown in the lightning card, or on its own card when the assessment failed.
class LightningLiveBlock extends StatelessWidget {
  const LightningLiveBlock({
    super.key,
    required this.lightning,
    required this.assessmentLevel,
    required this.assessedAt,
    required this.indicatorProcedure,
    required this.now,
    required this.onRetry,
  });

  final Loadable<VenueLightning> lightning;

  /// The assessment's lightning level (null when it has none or failed), and when
  /// the assessment was made.
  final AssessmentLevel? assessmentLevel;
  final DateTime? assessedAt;

  /// The assessment's own procedure steps, shown when `/lightning` has no guidance.
  final List<String> indicatorProcedure;
  final DateTime now;
  final VoidCallback onRetry;

  static const _padding = 12.0;

  @override
  Widget build(BuildContext context) => SafetySection(
    label: 'Live lightning check',
    child: switch (lightning) {
      Loading() => const LightningLiveSkeleton(),
      Failed(:final failure) => _Failure(failure: failure, onRetry: onRetry),
      Loaded(:final value) => _Loaded(
        reading: value,
        assessmentLevel: assessmentLevel,
        assessedAt: assessedAt,
        indicatorProcedure: indicatorProcedure,
        now: now,
      ),
    },
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.failure, required this.onRetry});

  final ApiFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final m = describeFailure(failure);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.error_outline, size: 18, color: context.safetyColors.requestError),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Live check unavailable: ${m.title}', style: text.titleSmall),
                  Text(
                    m.detail,
                    style: text.bodyMedium?.copyWith(color: context.palette.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (m.canRetry)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ),
          ),
      ],
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.reading,
    required this.assessmentLevel,
    required this.assessedAt,
    required this.indicatorProcedure,
    required this.now,
  });

  final VenueLightning reading;
  final AssessmentLevel? assessmentLevel;
  final DateTime? assessedAt;
  final List<String> indicatorProcedure;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final v = reading;
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    final state = v.status.state;
    final stateStyle = context.stateColors.of(state);
    final notCurrent = state != WeatherDataState.current;
    final ink = text.bodyMedium?.copyWith(color: palette.ink);
    final muted = text.bodyMedium?.copyWith(color: palette.inkMuted);
    final level = v.level;
    final differs = level != null && level.id != assessmentLevel?.id;
    final guidance = v.guidance;
    final steps = guidance != null && guidance.procedure.isNotEmpty
        ? guidance.procedure
        : indicatorProcedure;
    final checked = v.status.lastCheckedAt == null
        ? 'Not checked yet'
        : 'Last checked ${phtStamp(v.status.lastCheckedAt!, now)}';

    // One compact summary is announced when it changes; polling that brings the
    // same answer announces nothing.
    final summary =
        'Live lightning check. ${stateStyle.label}. $checked.'
        '${level == null ? '' : ' Level: ${level.label}.'}';

    final content = Padding(
      padding: const EdgeInsets.all(LightningLiveBlock._padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            key: const ValueKey('safetyLiveSummary'),
            liveRegion: true,
            label: summary,
            excludeSemantics: true,
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DataStateBadge(state: state),
                Text(checked, style: muted),
              ],
            ),
          ),
          if (!v.inLiveWindow) ...[
            const SizedBox(height: 8),
            Text(
              'Live checks run from ${phtStamp(v.liveWindow.start, now)} '
              'to ${phtStamp(v.liveWindow.end, now)}',
              style: muted,
            ),
          ] else if (v.flashCount != null) ...[
            const SizedBox(height: 8),
            if (notCurrent) ...[
              Row(
                children: [
                  Icon(Icons.history, size: 18, color: stateStyle.foreground),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Not current. Last reading:',
                      style: text.labelLarge?.copyWith(
                        color: stateStyle.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            if (v.flashCount == 0)
              Text(
                'No flashes within ${shortNumber(v.radiusKm)} km '
                'in the last ${v.detectionMinutes} min',
                style: text.titleSmall?.copyWith(color: palette.ink),
              )
            else ...[
              if (v.nearestKm != null)
                Text(
                  'Nearest ${shortNumber(v.nearestKm!)} km',
                  style: text.titleSmall?.copyWith(color: palette.ink),
                ),
              Text(
                '${v.flashCount} ${v.flashCount == 1 ? 'flash' : 'flashes'} '
                'within ${shortNumber(v.radiusKm)} km in the last ${v.detectionMinutes} min',
                style: ink,
              ),
              if (v.latestFlashAt != null)
                Text('Latest ${phtStamp(v.latestFlashAt!, now)}', style: muted),
            ],
          ],
          if (differs) ...[
            const SizedBox(height: 10),
            if (assessmentLevel != null && assessedAt != null)
              _LevelRow(
                label: 'Assessment (${phtStamp(assessedAt!, now)}):',
                levelId: assessmentLevel!.id,
                severity: assessmentLevel!.severity,
                levelLabel: assessmentLevel!.label,
              ),
            _LevelRow(
              label:
                  'Live check'
                  '${v.status.lastCheckedAt == null ? '' : ' (${phtStamp(v.status.lastCheckedAt!, now)})'}:',
              levelId: level.id,
              severity: level.severity,
              levelLabel: level.label,
            ),
          ],
          if (guidance != null && guidance.shownBecause.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Shown because: ${guidance.shownBecause.map(shownBecauseWords).join(', ')}',
              style: text.labelLarge,
            ),
          ],
          if (steps.isNotEmpty) ...[const SizedBox(height: 8), ProcedureSteps(steps)],
          if (guidance != null) ...[
            if (guidance.appliesNote.isNotEmpty) Text(guidance.appliesNote, style: muted),
            if (guidance.source.isNotEmpty) Text('Source: ${guidance.source}', style: muted),
          ],
          const SizedBox(height: 8),
          Text(v.note, style: ink),
          LinkText(v.attribution.url, label: v.attribution.text),
        ],
      ),
    );

    final stale = context.stateColors.of(WeatherDataState.stale);
    return state == WeatherDataState.stale
        ? DashedBorder(color: stale.foreground, radius: AppTheme.radiusCard, child: content)
        : DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: palette.hairline, width: AppTheme.hairline),
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            ),
            child: content,
          );
  }
}

/// "Live check (11:59 AM PHT):" and its level pill.
class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.label,
    required this.levelId,
    required this.severity,
    required this.levelLabel,
  });

  final String label;
  final String levelId;
  final String? severity;
  final String levelLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SafetyLevelPill(levelId: levelId, severity: severity, label: levelLabel),
      ],
    ),
  );
}

/// Stands in for the live block while the live reading loads.
class LightningLiveSkeleton extends StatelessWidget {
  const LightningLiveSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.palette.hairline, width: AppTheme.hairline),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Padding(
        padding: const EdgeInsets.all(LightningLiveBlock._padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: LevelRow.badgeHeight(context),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(width: 120, height: 24, radius: 12),
              ),
            ),
            const SizedBox(height: 8),
            SkeletonLine(style: text.bodyMedium, widthFactor: 1),
            SkeletonLine(style: text.bodyMedium, widthFactor: 0.6),
            const SizedBox(height: 8),
            for (var n = 0; n < 4; n++)
              SkeletonLine(style: text.bodyMedium, widthFactor: n == 3 ? 0.5 : 1),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
