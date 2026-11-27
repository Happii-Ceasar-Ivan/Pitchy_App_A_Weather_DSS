import 'package:material_ui/material_ui.dart';

import '../../core/state/loadable.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/spacing.dart';
import '../../shared/models/assessment.dart';
import '../../shared/models/lightning.dart';
import '../../shared/models/weather.dart';
import '../../shared/widgets/dashed_border.dart';
import '../../shared/widgets/skeletons.dart';
import 'safety_level.dart';
import 'safety_live_block.dart';
import 'safety_widgets.dart';

(IconData, String) _hazardLook(Hazard h) => switch (h) {
  Hazard.heat => (Icons.thermostat, 'Heat'),
  Hazard.lightning => (Icons.bolt, 'Lightning'),
  Hazard.rainfall => (Icons.water_drop, 'Rainfall'),
};

/// One card per indicator, in the backend's order. Heat and rainfall: level,
/// what officials do, who decides, value, limitations, then the "How this was
/// worked out" expander. The lightning card puts the live block right after the
/// level, then who decides, value and limitations.
class HazardCard extends StatefulWidget {
  const HazardCard({
    super.key,
    required this.indicator,
    required this.now,
    required this.assessedAt,
    required this.lightning,
    required this.onRetryLightning,
    this.rulesApproved = true,
    this.notCurrent = false,
  });

  final HazardIndicator indicator;
  final DateTime now;
  final DateTime assessedAt;

  /// The live reading; used only by the lightning card.
  final Loadable<VenueLightning> lightning;
  final VoidCallback onRetryLightning;

  /// False while the rule set is a draft: levels get a "Draft rules" marker.
  final bool rulesApproved;

  /// True for the last assessment shown after a failed refresh.
  final bool notCurrent;

  @override
  State<HazardCard> createState() => _HazardCardState();
}

class _HazardCardState extends State<HazardCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final i = widget.indicator;
    final text = Theme.of(context).textTheme;
    final (icon, name) = _hazardLook(i.hazard);
    final valueLabel = switch (i.hazard) {
      Hazard.heat => 'WBGT (forecast estimate)',
      Hazard.lightning => 'Nearest detected flash (at assessment)',
      Hazard.rainfall => 'Value used for the level',
    };
    final lightning = i.hazard == Hazard.lightning;

    final live = LightningLiveBlock(
      lightning: widget.lightning,
      assessmentLevel: i.level,
      assessedAt: widget.assessedAt,
      indicatorProcedure: i.procedure,
      now: widget.now,
      onRetry: widget.onRetryLightning,
    );
    final officials = [
      if (i.level != null)
        SafetySection(
          label: 'What officials do',
          child: Text(i.level!.action, style: text.bodyMedium),
        ),
      if (i.decidedBy != null)
        SafetySection(
          label: 'Who decides',
          child: Text(
            i.decidedBy!,
            style: text.bodyMedium?.copyWith(color: context.palette.ink),
          ),
        ),
    ];
    final value = i.indicatorValue == null
        ? null
        : SafetySection(
            label: valueLabel,
            child: Text(
              '${i.indicatorValue!.toStringAsFixed(1)}'
              '${i.indicatorUnit == null ? '' : ' ${i.indicatorUnit}'}',
              style: text.titleLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          );
    final limitations = i.limitations.isEmpty
        ? null
        : SafetySection(
            label: 'Limitations',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final l in i.limitations) LimitationLine(l.message)],
            ),
          );

    final card = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(safetyCardInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafetyTitleRow(
              icon: icon,
              title: name,
              trailing: IndicatorStatusPill(status: i.status, notCurrent: widget.notCurrent),
            ),
            SafetySection(
              label: 'Level',
              child: LevelRow(level: i.level, draft: !widget.rulesApproved),
            ),
            if (lightning) live,
            ...officials,
            ?value,
            ?limitations,
            SafetyExpander(
              hazardName: name,
              expanded: _expanded,
              onToggle: () => setState(() => _expanded = !_expanded),
              child: HazardDetails(indicator: i, now: widget.now),
            ),
          ],
        ),
      ),
    );
    // A limited indicator, or a last assessment that could not be refreshed,
    // carries the dashed stamp like stale weather data.
    return i.status == IndicatorStatus.limited || widget.notCurrent
        ? DashedBorder(
            color: context.stateColors.of(WeatherDataState.stale).foreground,
            radius: AppTheme.radiusCard,
            child: card,
          )
        : card;
  }
}

/// The lightning card when the assessment could not be loaded: only the live block.
class LightningOnlyCard extends StatelessWidget {
  const LightningOnlyCard({
    super.key,
    required this.lightning,
    required this.now,
    required this.onRetry,
  });

  final Loadable<VenueLightning> lightning;
  final DateTime now;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(safetyCardInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SafetyTitleRow(icon: Icons.bolt, title: 'Lightning near the venue'),
          LightningLiveBlock(
            lightning: lightning,
            assessmentLevel: null,
            assessedAt: null,
            indicatorProcedure: const [],
            now: now,
            onRetry: onRetry,
          ),
        ],
      ),
    ),
  );
}

/// Loading shape of the whole screen: header, one card per hazard, notices. The
/// same boxes and positions as the loaded, collapsed layout.
class SafetySkeleton extends StatelessWidget {
  const SafetySkeleton({super.key});

  @override
  Widget build(BuildContext context) => const SkeletonPulse(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SafetyHeaderSkeleton(),
        SizedBox(height: safetyCardGap),
        HazardCardSkeleton(
          actionLines: 5,
          decidedLines: 2,
          hasValue: true,
          // Line counts match the heatBelow fixture at phone width in Switzer
          // (re-measured for the P-28 font change: limitations 13 -> 12;
          // and for the 16 px card inset of the 4/8 rhythm: 12 -> 13).
          limitationLines: 13,
          limitationGaps: 2,
        ),
        SizedBox(height: safetyCardGap),
        HazardCardSkeleton(
          actionLines: 0,
          decidedLines: 2,
          limitationLines: 8,
          limitationGaps: 2,
          live: true,
        ),
        SizedBox(height: safetyCardGap),
        HazardCardSkeleton(actionLines: 0, decidedLines: 0, limitationLines: 4, limitationGaps: 1),
        SizedBox(height: safetyCardGap),
        NoticesSkeleton(),
      ],
    ),
  );
}

class SafetyHeaderSkeleton extends StatelessWidget {
  const SafetyHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(safetyCardInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SkeletonLine(style: text.titleSmall, widthFactor: 0.55),
            const SizedBox(height: PitchySpace.xxs),
            SkeletonLine(style: text.bodyMedium, widthFactor: 0.5),
            const SizedBox(height: PitchySpace.xxs),
            SkeletonLine(style: text.bodyMedium, widthFactor: 0.4),
            const SizedBox(height: PitchySpace.md),
            for (var n = 0; n < 3; n++)
              SkeletonLine(style: text.bodyMedium, widthFactor: n == 2 ? 0.6 : 1),
            const SizedBox(height: PitchySpace.xs),
          ],
        ),
      ),
    );
  }
}

/// The level pill's exact size, drawn as a skeleton bar.
class _LevelPillSkeleton extends StatelessWidget {
  const _LevelPillSkeleton();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Stack(
      children: [
        const Opacity(opacity: 0, child: SafetyLevelPill(levelId: null, label: 'Level')),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, box) => SkeletonBox(
              width: box.maxWidth,
              height: box.maxHeight,
              radius: AppTheme.radiusCard,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton({
    required this.lines,
    this.pill = false,
    this.gaps = 0,
  });

  final int lines;
  final bool pill;

  /// Spacing the loaded section has under each of its lines of text (4 px per item).
  final int gaps;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: SafetySection.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonLine(style: text.labelMedium, width: 90),
          const SizedBox(height: SafetySection.labelGap),
          if (pill)
            const _LevelPillSkeleton()
          else
            for (var n = 0; n < lines; n++)
              SkeletonLine(style: text.bodyMedium, widthFactor: n == lines - 1 ? 0.6 : 1),
          SizedBox(height: 4.0 * gaps),
        ],
      ),
    );
  }
}

/// Stands in for one hazard card.
class HazardCardSkeleton extends StatelessWidget {
  const HazardCardSkeleton({
    super.key,
    required this.actionLines,
    required this.limitationLines,
    this.limitationGaps = 0,
    this.decidedLines = 0,
    this.hasValue = false,
    this.live = false,
  });

  final int actionLines;
  final int limitationLines;
  final int limitationGaps;
  final int decidedLines;
  final bool hasValue;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(safetyCardInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
              child: const Row(
                children: [
                  SkeletonBox(width: 22, height: 22, radius: 11),
                  SizedBox(width: PitchySpace.sm),
                  SkeletonBox(width: 90, height: 16),
                  Spacer(),
                  SkeletonBox(width: 96, height: 24, radius: 12),
                ],
              ),
            ),
            const _SectionSkeleton(lines: 0, pill: true),
            if (live)
              Padding(
                padding: const EdgeInsets.only(top: SafetySection.gap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SkeletonLine(style: text.labelMedium, width: 130),
                    const SizedBox(height: SafetySection.labelGap),
                    const LightningLiveSkeleton(),
                  ],
                ),
              ),
            if (actionLines > 0) _SectionSkeleton(lines: actionLines),
            if (decidedLines > 0) _SectionSkeleton(lines: decidedLines),
            if (hasValue)
              Padding(
                padding: const EdgeInsets.only(top: SafetySection.gap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SkeletonLine(style: text.labelMedium, width: 120),
                    const SizedBox(height: SafetySection.labelGap),
                    SkeletonLine(style: text.titleLarge, width: 90),
                  ],
                ),
              ),
            _SectionSkeleton(lines: limitationLines, gaps: limitationGaps),
            const SizedBox(height: SafetyExpander.gap + 1),
            const SizedBox(height: AppTheme.minTarget),
          ],
        ),
      ),
    );
  }
}

class NoticesSkeleton extends StatelessWidget {
  const NoticesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(safetyCardInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SkeletonLine(style: text.titleMedium, width: 130),
            const SizedBox(height: PitchySpace.xxs),
            SkeletonLine(style: text.bodyMedium, widthFactor: 0.7),
            const SizedBox(height: PitchySpace.md),
            SkeletonLine(style: text.bodyLarge, widthFactor: 0.9),
            SkeletonLine(style: text.bodyMedium, widthFactor: 0.4),
          ],
        ),
      ),
    );
  }
}
