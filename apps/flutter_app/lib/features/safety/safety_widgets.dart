import 'package:material_ui/material_ui.dart';

import '../../core/errors/api_failure.dart';
import '../../core/errors/failure_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/pht_time.dart';
import '../../shared/models/assessment.dart';
import '../../shared/models/match.dart';
import '../../shared/models/weather.dart';
import '../../shared/widgets/dashed_border.dart';
import 'safety_level.dart';

/// A PHT time. A time from another PHT day names the day, so "4:22 PM" can't be
/// read as today.
String phtStamp(DateTime t, DateTime now) {
  final a = toPhtWallClock(t), b = toPhtWallClock(now);
  final sameDay = a.year == b.year && a.month == b.month && a.day == b.day;
  return sameDay ? formatPhtTime(t) : formatPhtDateTime(t);
}

/// "40", "8.2": one decimal, none when it is a whole number.
String shortNumber(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Friendly names for the forecast inputs. The raw id stays visible next to the
/// name; an id not in the map is shown as sent.
const _inputNames = {
  'temperature_2m': 'Air temperature',
  'relative_humidity_2m': 'Relative humidity',
  'wind_speed_10m': 'Wind speed',
  'surface_pressure': 'Surface pressure',
  'shortwave_radiation': 'Solar radiation',
};

/// "Air temperature (temperature_2m)", or the raw id when it has no friendly name.
String inputLabel(String id) => _inputNames.containsKey(id) ? '${_inputNames[id]} ($id)' : id;

/// Vertical gap between the cards on the screen.
const safetyCardGap = 12.0;

/// Inner padding of every card on the screen.
const safetyCardInset = 16.0;

/// A labelled block inside a card: a small header, then its content. The label
/// is a screen-reader header.
class SafetySection extends StatelessWidget {
  const SafetySection({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  static const gap = 12.0;
  static const labelGap = 4.0;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: gap),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: context.palette.inkMuted),
          ),
        ),
        const SizedBox(height: labelGap),
        child,
      ],
    ),
  );
}

/// One backend limitation message, verbatim, with an info icon.
class LimitationLine extends StatelessWidget {
  const LimitationLine(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: PitchySpace.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: PitchySpace.xxs),
          child: Icon(Icons.error_outline, size: 18, color: context.palette.ink),
        ),
        const SizedBox(width: PitchySpace.sm),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.palette.ink),
          ),
        ),
      ],
    ),
  );
}

/// The header card: when the assessment was made, when inputs were checked, which
/// heat level set applies, and the top-level limitations (always visible).
class SafetyHeaderCard extends StatelessWidget {
  const SafetyHeaderCard({
    super.key,
    required this.assessment,
    required this.now,
    required this.refreshing,
  });

  final SafetyAssessment assessment;
  final DateTime now;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.inkMuted);
    final a = assessment;
    final heatSet = a.ageGroup == AgeGroup.youthU20 ? 'Under-20 or younger' : 'Senior';
    final limitations = [
      for (final l in a.limitations)
        if (a.rulesApproved || l.code != rulesNotApprovedCode) l,
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(safetyCardInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Assessed ${phtStamp(a.assessedAt, now)}', style: text.titleSmall),
                ),
                if (refreshing) ...[
                  const SizedBox(width: PitchySpace.sm),
                  Text(
                    'Refreshing',
                    style: text.bodySmall?.copyWith(color: context.palette.inkMuted),
                  ),
                  const SizedBox(width: PitchySpace.sm),
                  SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: 'Refreshing',
                      color: context.palette.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: PitchySpace.xxs),
            Text('Inputs checked ${phtStamp(a.checkedAt, now)}', style: muted),
            const SizedBox(height: PitchySpace.xxs),
            Row(
              children: [
                Icon(Icons.groups, size: 18, color: context.palette.ink),
                const SizedBox(width: PitchySpace.sm),
                Expanded(child: Text('Heat levels: $heatSet', style: text.titleSmall)),
              ],
            ),
            if (limitations.isNotEmpty) ...[
              const SizedBox(height: PitchySpace.md),
              for (final l in limitations) LimitationLine(l.message),
            ],
          ],
        ),
      ),
    );
  }
}

/// The backend's limitation code for a draft rule set.
const rulesNotApprovedCode = 'RULES_NOT_APPROVED';

/// "Rules not approved yet", in the stale colours, above the cards.
class RulesBanner extends StatelessWidget {
  const RulesBanner({super.key, required this.message});

  /// The backend's `RULES_NOT_APPROVED` message, when it sent one.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final s = context.stateColors.of(WeatherDataState.stale);
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(safetyCardInset),
        decoration: BoxDecoration(
          color: s.background,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.rule, size: 20, color: s.foreground),
            const SizedBox(width: PitchySpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rules not approved yet',
                    style: text.titleSmall?.copyWith(color: s.foreground),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: PitchySpace.xs),
                    Text(message!, style: text.bodyMedium?.copyWith(color: s.foreground)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Official notices, as issued. Text from the issuer is plain text only.
class OfficialNoticesCard extends StatelessWidget {
  const OfficialNoticesCard({super.key, required this.notices, required this.now});

  final List<OfficialNotice> notices;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.inkMuted);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(safetyCardInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text('Official notices', style: text.titleMedium)),
            const SizedBox(height: PitchySpace.xxs),
            Text('Official information, shown as issued.', style: muted),
            for (var k = 0; k < notices.length; k++) ...[
              if (k > 0) ...[
                const SizedBox(height: PitchySpace.md),
                Divider(height: AppTheme.hairline, color: context.palette.hairline),
              ],
              const SizedBox(height: PitchySpace.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(Icons.campaign_outlined, size: 20, color: context.palette.ink),
                  ),
                  const SizedBox(width: PitchySpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notices[k].issuer,
                          style: text.labelMedium?.copyWith(color: context.palette.inkMuted),
                        ),
                        Text(
                          notices[k].title,
                          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (notices[k].issuedAt != null)
                          Text('Issued ${phtStamp(notices[k].issuedAt!, now)}', style: muted),
                        if (notices[k].validUntil != null)
                          Text(
                            'Valid until ${phtStamp(notices[k].validUntil!, now)}',
                            style: muted,
                          ),
                        Text(notices[k].provenance.sourceName, style: muted),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rule version and the fixed decision line.
class SafetyFooter extends StatelessWidget {
  const SafetyFooter({super.key, this.ruleVersion});

  final String? ruleVersion;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ruleVersion != null)
          Text(
            'Rules: $ruleVersion',
            style: text.bodySmall?.copyWith(color: context.palette.inkMuted),
          ),
        const SizedBox(height: PitchySpace.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.gavel, size: 18, color: context.palette.ink),
            const SizedBox(width: PitchySpace.sm),
            Expanded(
              child: Text(
                'Pitchy supports the decision. Match officials make it.',
                style: text.bodyMedium?.copyWith(color: context.palette.ink),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Title row of a card: icon, name (a screen-reader header) and an optional pill.
class SafetyTitleRow extends StatelessWidget {
  const SafetyTitleRow({super.key, required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
    child: Row(
      children: [
        Icon(icon, size: 22, color: context.palette.ink),
        const SizedBox(width: PitchySpace.sm),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: PitchySpace.sm), trailing!],
      ],
    ),
  );
}

/// Data available / Data limited / No data, with icon and word. Available is a
/// neutral outline (not a success colour); limited uses the stale colours with
/// the dashed stamp; no data uses the unavailable colours. [notCurrent] shows the
/// stale state instead, for a last assessment that could not be refreshed.
class IndicatorStatusPill extends StatelessWidget {
  const IndicatorStatusPill({super.key, required this.status, this.notCurrent = false});

  final IndicatorStatus status;
  final bool notCurrent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (state, word, icon) = notCurrent
        ? (WeatherDataState.stale, 'Not current', Icons.history)
        : switch (status) {
            IndicatorStatus.available => (null, 'Data available', Icons.check_circle_outline),
            IndicatorStatus.limited => (WeatherDataState.stale, 'Data limited', Icons.history),
            IndicatorStatus.unavailable => (
              WeatherDataState.unavailable,
              'No data',
              Icons.cloud_off,
            ),
          };
    final s = state == null ? null : context.stateColors.of(state);
    final fg = s?.foreground ?? palette.ink;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: PitchySpace.sm, vertical: PitchySpace.xs),
      decoration: BoxDecoration(
        color: s?.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: s == null ? Border.all(color: palette.hairline) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: PitchySpace.xs),
          Flexible(
            child: Text(
              word.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: 'Status: $word',
      excludeSemantics: true,
      child: s != null && s.dashed
          ? DashedBorder(color: s.foreground, radius: AppTheme.radiusPill, child: pill)
          : pill,
    );
  }
}

/// "Draft rules" marker shown beside a level while the rule set is not approved.
class DraftRulesMarker extends StatelessWidget {
  const DraftRulesMarker({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.stateColors.of(WeatherDataState.stale);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.rule, size: 16, color: s.foreground),
        const SizedBox(width: PitchySpace.xs),
        Text(
          'Draft rules',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: s.foreground),
        ),
      ],
    );
  }
}

/// The level: the backend's pill, or "No level" as a neutral pill.
class LevelRow extends StatelessWidget {
  const LevelRow({super.key, required this.level, this.draft = false});

  final AssessmentLevel? level;

  /// True while the rule set is a draft: adds the "Draft rules" marker.
  final bool draft;

  /// Height of a badge-sized pill (state badge), for skeletons.
  static double badgeHeight(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    final line =
        MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 12) * (style?.height ?? 1.2);
    return (line > 16 ? line : 16) + 8;
  }

  @override
  Widget build(BuildContext context) {
    final l = level;
    return Wrap(
      spacing: PitchySpace.sm,
      runSpacing: PitchySpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        l == null
            ? const SafetyLevelPill(levelId: null, label: 'No level', icon: Icons.help_outline)
            : SafetyLevelPill(levelId: l.id, severity: l.severity, label: l.label),
        if (draft) const DraftRulesMarker(),
      ],
    );
  }
}

/// A collapsible "How this was worked out" row: 48 px target, hairline above.
class SafetyExpander extends StatelessWidget {
  const SafetyExpander({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.child,
    required this.hazardName,
  });

  /// "Heat", "Lightning", ...: names the expander for screen readers.
  final String hazardName;

  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  /// Gap above the hairline.
  static const gap = 12.0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: gap),
      Divider(height: AppTheme.hairline, color: context.palette.hairline),
      Semantics(
        button: true,
        expanded: expanded,
        label: 'How this was worked out, $hazardName',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          onTap: onToggle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'How this was worked out',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 24,
                  color: context.palette.inkMuted,
                ),
              ],
            ),
          ),
        ),
      ),
      AnimatedSize(
        duration: PitchyMotion.of(context).expand,
        reverseDuration: PitchyMotion.of(context).collapse,
        curve: PitchyMotion.enter,
        alignment: Alignment.topCenter,
        child: expanded ? child : const SizedBox(width: double.infinity),
      ),
    ],
  );
}

/// What is inside the expander, in the spec's order.
class HazardDetails extends StatelessWidget {
  const HazardDetails({super.key, required this.indicator, required this.now});

  final HazardIndicator indicator;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final i = indicator;
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.inkMuted);
    final used = context.stateColors.of(WeatherDataState.current);

    String value(IndicatorPoint p) => p.value == null
        ? 'No value${p.missing.isEmpty ? '' : ' (missing: ${p.missing.map(inputLabel).join(', ')})'}'
        : '${p.value!.toStringAsFixed(1)} ${i.indicatorUnit ?? ''}'.trim();

    final sources = <GuidanceReference>[];
    void addSource(GuidanceReference? r) {
      if (r == null) return;
      if (sources.any((s) => s.documentId == r.documentId && s.section == r.section)) return;
      sources.add(r);
    }

    addSource(i.level?.source);
    i.level?.alsoSupportedBy.forEach(addSource);
    i.guidance.forEach(addSource);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (i.basis != null)
          SafetySection(
            label: 'Basis',
            child: Text(i.basis!, style: text.bodyMedium),
          ),
        if (i.points.isNotEmpty)
          SafetySection(
            label: 'Measurement times',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in i.points)
                  Padding(
                    padding: const EdgeInsets.only(bottom: PitchySpace.xs),
                    child: Wrap(
                      spacing: PitchySpace.sm,
                      runSpacing: PitchySpace.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(phtStamp(p.at, now), style: text.bodyMedium),
                        Text(value(p), style: text.bodyMedium),
                        if (p.usedForLevel)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline, size: 16, color: used.foreground),
                              const SizedBox(width: PitchySpace.xs),
                              Text(
                                'Used for the level',
                                style: text.labelMedium?.copyWith(color: used.foreground),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (i.hourly.isNotEmpty)
          SafetySection(
            label: 'During the match',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in i.hourly)
                  Text('${phtStamp(p.at, now)}: ${value(p)}', style: text.bodyMedium),
              ],
            ),
          ),
        if (i.inputs.isNotEmpty)
          SafetySection(
            label: 'Inputs',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final inp in i.inputs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: PitchySpace.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${inputLabel(inp.parameter)}: '
                          '${inp.value == null ? 'No value' : shortNumber(inp.value!)}'
                          '${inp.unit == null || inp.value == null ? '' : ' ${inp.unit}'}',
                          style: text.bodyMedium,
                        ),
                        Text(_provenanceLine(inp.provenance, now), style: muted),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (i.notices.isNotEmpty)
          SafetySection(
            label: 'Rule notes',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final n in i.notices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: PitchySpace.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.text, style: text.bodyMedium),
                        Text(n.source.title, style: muted),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (sources.isNotEmpty)
          SafetySection(
            label: 'Sources',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final r in sources) _SourceLine(r)],
            ),
          ),
        const SizedBox(height: PitchySpace.sm),
      ],
    );
  }
}

/// "Open-Meteo · retrieved 11:20 AM PHT · valid 2:00–3:00 PM PHT". It wraps
/// naturally at large text sizes.
String _provenanceLine(Provenance p, DateTime now) {
  final parts = <String>[
    p.sourceName,
    if (p.retrievedAt != null) 'retrieved ${phtStamp(p.retrievedAt!, now)}',
    if (p.forecastValidFrom != null && p.forecastValidUntil != null)
      'valid ${_range(p.forecastValidFrom!, p.forecastValidUntil!, now)}',
  ];
  return parts.join(' · ');
}

String _range(DateTime from, DateTime until, DateTime now) {
  final a = toPhtWallClock(from), b = toPhtWallClock(until);
  if (a.year != b.year || a.month != b.month || a.day != b.day) {
    return '${phtStamp(from, now)}–${phtStamp(until, now)}';
  }
  var start = formatPhtTime(from).replaceAll(' $phtLabel', '');
  final end = formatPhtTime(until);
  if (start.split(' ').last == end.replaceAll(' $phtLabel', '').split(' ').last) {
    start = start.split(' ').first;
  }
  final day = phtStamp(from, now) == formatPhtTime(from)
      ? ''
      : '${formatPhtDateTime(from).split(',').first}, ';
  return '$day$start–$end';
}

class _SourceLine extends StatelessWidget {
  const _SourceLine(this.ref);

  final GuidanceReference ref;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.inkMuted);
    return Padding(
      padding: const EdgeInsets.only(bottom: PitchySpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ref.title, style: text.bodyMedium),
          Text('${ref.authority}, ${ref.version}', style: muted),
          if (ref.section != null) Text(ref.section!, style: muted),
        ],
      ),
    );
  }
}

/// "Not current. Assessed 11:20 AM PHT." in the stale colours, above the last
/// assessment that could not be refreshed.
class NotCurrentLine extends StatelessWidget {
  const NotCurrentLine({super.key, required this.assessedAt, required this.now});

  final DateTime assessedAt;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = context.stateColors.of(WeatherDataState.stale);
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: safetyCardInset, vertical: PitchySpace.sm),
        decoration: BoxDecoration(
          color: s.background,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.history, size: 20, color: s.foreground),
            const SizedBox(width: PitchySpace.sm),
            Expanded(
              child: Text(
                'Not current. Assessed ${phtStamp(assessedAt, now)}.',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: s.foreground, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The assessment failed to refresh: what went wrong, with Try again when it helps.
class AssessmentFailureBanner extends StatelessWidget {
  const AssessmentFailureBanner({super.key, required this.failure, required this.onRetry});

  final ApiFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final m = describeFailure(failure);
    final colours = context.safetyColors;
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(safetyCardInset),
        decoration: BoxDecoration(
          color: colours.requestError,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 20, color: colours.onRequestError),
            const SizedBox(width: PitchySpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Couldn’t refresh the assessment: ${m.title}',
                    style: text.titleSmall?.copyWith(color: colours.onRequestError),
                  ),
                  const SizedBox(height: PitchySpace.xxs),
                  Text(m.detail, style: text.bodyMedium?.copyWith(color: colours.onRequestError)),
                  if (m.canRetry)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: colours.onRequestError),
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
