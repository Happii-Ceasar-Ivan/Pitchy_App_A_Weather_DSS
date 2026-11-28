import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/pht_time.dart';
import '../models/weather.dart';
import 'dashed_border.dart';
import 'data_state_badge.dart';
import 'press_scale.dart';
import 'skeletons.dart';
import 'weather_icons.dart';

/// A source name without its trailing domain, for tight spaces:
/// "PAGASA ATMO (panahon.gov.ph)" -> "PAGASA ATMO". The full name stays in the
/// expanded view and in screen-reader labels. "OpenWeather One Call 3.0"
/// (P-30) -> "OpenWeather": the API product name doesn't fit a rail row.
String shortSourceName(String name) => name.startsWith('OpenWeather ')
    ? 'OpenWeather'
    : name.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '');

/// The state to show for a slot. Uses the slot's own state; if the backend left
/// it out, falls back to the used source's state. Never assumes Current.
WeatherDataState slotState(ConsolidatedSlot? slot, List<SourceStatus> sources) {
  if (slot == null || slot.value == null) return WeatherDataState.unavailable;
  if (slot.state != null) return slot.state!;
  for (final s in sources) {
    if (s.sourceId == slot.sourceId) return s.state;
  }
  return WeatherDataState.unavailable;
}

/// A dashboard weather card (P-13). Collapsed: the data only, plus its state
/// whenever it isn't Current, so stale or unavailable data never looks current.
/// Expanded: source, timestamps and uncertainty (spread across sources).
class WeatherValueCard extends StatelessWidget {
  const WeatherValueCard({
    super.key,
    required this.quantity,
    required this.slot,
    required this.sources,
    required this.expanded,
    required this.onToggle,
  });

  final ConsolidatedQuantity quantity;

  /// The slot to show (normally the one containing kickoff). Null: no slot.
  final ConsolidatedSlot? slot;

  /// Per-source status, for names, line colours and fetch times.
  final List<SourceStatus> sources;
  final bool expanded;
  final VoidCallback onToggle;

  /// Height of the footer row (state pill or expand arrow, whichever is taller).
  static double footerHeight(BuildContext context) {
    final pill = DataStateBadge.denseHeight(context);
    return pill > 20 ? pill : 20;
  }

  static String number(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  static String _hourRange(ConsolidatedSlot s) {
    String h(DateTime t) => formatPhtTime(t).replaceAll(' $phtLabel', '').replaceAll(':00', '');
    return '${h(s.validFrom)}–${formatPhtTime(s.validUntil).replaceAll(':00', '')}';
  }

  SourceStatus? _source(String? id) {
    for (final s in sources) {
      if (s.sourceId == id) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final value = slot?.value;
    final state = slotState(slot, sources);
    final savedLive = claimsLiveInSavedCopy(context, state);
    final notCurrent = state != WeatherDataState.current || savedLive;
    final unit = quantity.unit;
    final used = _source(slot?.sourceId);
    final stateLabel = spokenStateWord(context, state);

    final valueText = value == null ? 'No value' : number(value);
    final semantic = value == null
        ? '${quantity.label}: no value. $stateLabel.'
        : '${quantity.label}: $valueText $unit'
              '${used == null ? '' : ', from ${used.sourceName}'}'
              '${notCurrent ? ', $stateLabel' : ''}.';

    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(PitchySpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // One line: the label without its bracketed source (the full
              // label is in the details and the screen-reader text).
              // Screen readers hear the full label once, in the value's text.
              // The icon has its own row (P-27 B), so the label keeps its full
              // width on narrow phones. The row is there even without an icon,
              // so every card in a row has the same shape.
              SizedBox(
                height: WeatherQuantityIcon.sizeFor(context, text.labelLarge),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: WeatherQuantityIcon(
                    quantity: quantity.quantity,
                    style: text.labelLarge,
                    color: palette.inkMuted,
                  ),
                ),
              ),
              const SizedBox(height: PitchySpace.xs),
              ExcludeSemantics(
                child: Text(
                  shortSourceName(quantity.label),
                  style: text.labelLarge?.copyWith(color: palette.inkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: PitchySpace.sm),
              Semantics(
                label: semantic,
                excludeSemantics: true,
                child: SizedBox(
                  height: SkeletonLine.lineHeight(context, text.headlineMedium),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: valueText,
                            style: (value == null ? text.titleLarge : text.headlineMedium)
                                ?.copyWith(color: notCurrent ? palette.inkMuted : palette.ink),
                          ),
                          // The unit sits apart from the value: smaller and muted, on the
                          // same baseline, so values scan faster.
                          if (value != null)
                            TextSpan(
                              text: ' $unit',
                              style: text.titleSmall?.copyWith(color: palette.inkMuted),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: PitchySpace.xs),
              SizedBox(
                height: SkeletonLine.lineHeight(context, text.bodySmall),
                child: slot == null
                    ? null
                    : Row(
                        children: [
                          if (used != null) ...[
                            _LineDot(color: palette.lineFor(used.sourceId)),
                            const SizedBox(width: PitchySpace.sm),
                          ],
                          // Scales down a little on a narrow phone rather than
                          // cutting "PHT" (large text uses one card per row).
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(_hourRange(slot!), style: text.bodySmall, maxLines: 1),
                            ),
                          ),
                        ],
                      ),
              ),
              // Footer: the state pill (when not Current) and the expand arrow.
              // Always present, so cards keep one height and a state change
              // never moves the layout.
              const SizedBox(height: PitchySpace.sm),
              SizedBox(
                height: WeatherValueCard.footerHeight(context),
                child: Row(
                  children: [
                    Expanded(
                      child: notCurrent
                          ? Align(
                              alignment: Alignment.centerLeft,
                              // Said once already, in the value's text.
                              child: ExcludeSemantics(
                                child: DataStateBadge(state: state, dense: true),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Semantics(
                      label: expanded ? 'Hide details' : 'Show source and times',
                      excludeSemantics: true,
                      child: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: palette.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                // Reduced motion: a zero-length animation can't run on a kept
                // render object, so the size is simply rebuilt (instant).
                key: PitchyMotion.of(context).reduced ? ValueKey(expanded) : null,
                duration: PitchyMotion.of(context).expand,
                reverseDuration: PitchyMotion.of(context).collapse,
                curve: PitchyMotion.enter,
                alignment: Alignment.topCenter,
                child: expanded && slot != null
                    ? _FadeIn(
                        duration: PitchyMotion.of(context).fade,
                        child: _Details(quantity: quantity, slot: slot!, used: used),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );

    // Stale cards keep their stamp on the whole card, not only the pill.
    return state == WeatherDataState.stale
        ? DashedBorder(
            color: context.stateColors.of(state).foreground,
            radius: AppTheme.radiusCard,
            child: card,
          )
        : card;
  }
}

class _LineDot extends StatelessWidget {
  const _LineDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Fades its child in once, when it first appears (the card's revealed
/// detail). Opacity only; the size change is the card's own AnimatedSize.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.duration, required this.child});

  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: duration,
    curve: PitchyMotion.enter,
    builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
    child: child,
  );
}

class _Details extends StatelessWidget {
  const _Details({required this.quantity, required this.slot, required this.used});

  final ConsolidatedQuantity quantity;
  final ConsolidatedSlot slot;
  final SourceStatus? used;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    final used = this.used;
    final retrieved = used?.provenance?.retrievedAt;
    final range = slot.range;
    final rows = <(String, String, Color?)>[
      if (shortSourceName(quantity.label) != quantity.label) ('Measure', quantity.label, null),
      (
        'Source',
        used?.sourceName ?? slot.sourceId ?? 'None',
        used == null ? null : palette.lineFor(used.sourceId),
      ),
      if (retrieved != null) ('Fetched', formatPhtDateTime(retrieved), null),
      ('Valid', '${formatPhtTime(slot.validFrom)} – ${formatPhtTime(slot.validUntil)}', null),
      if (range != null)
        (
          'Spread',
          '${WeatherValueCard.number(range.min)}–${WeatherValueCard.number(range.max)} '
              '${quantity.unit} across ${range.count} sources',
          null,
        )
      else
        ('Spread', 'Only one source for this value', null),
      if (slot.fallbackLabel != null) ('Fallback', slot.fallbackLabel!, null),
      for (final n in slot.notes) ('Note', n, null),
    ];

    Widget value(String v, Color? dot) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dot != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: PitchySpace.xs),
            child: _LineDot(color: dot),
          ),
          const SizedBox(width: PitchySpace.sm),
        ],
        Expanded(child: Text(v, style: text.bodyMedium)),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(top: PitchySpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(color: palette.hairline),
          const SizedBox(height: PitchySpace.sm),
          // Side by side when there's room; label above value in narrow cards.
          LayoutBuilder(
            builder: (context, c) {
              final stacked = c.maxWidth < 280;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (k, v, dot) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: PitchySpace.xs),
                      child: stacked
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(k, style: text.bodySmall),
                                value(v, dot),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 72, child: Text(k, style: text.bodySmall)),
                                Expanded(child: value(v, dot)),
                              ],
                            ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The dashboard card area (P-13): at most [maxVisible] cards until the user
/// asks for more. One card is expanded at a time; on compact widths the
/// expanded card spans the full row so its details have room.
class WeatherCardGrid extends StatefulWidget {
  const WeatherCardGrid({
    super.key,
    required this.weather,
    required this.kickoff,
    this.maxVisible = 4,
  });

  final ConsolidatedWeather weather;
  final DateTime kickoff;
  final int maxVisible;

  /// Columns for [maxWidth]: 4 on wide windows, else 2. At large text one
  /// card per row on phones (two on wide windows), so labels, values and
  /// state pills fit whole. The skeleton uses the same rule.
  static int columns(BuildContext context, double maxWidth) {
    final wide = maxWidth >= 720;
    if (AppTheme.isLargeText(context)) return wide ? 2 : 1;
    return wide ? 4 : 2;
  }

  /// The slot containing kickoff, or the first slot.
  static ConsolidatedSlot? kickoffSlot(ConsolidatedQuantity q, DateTime kickoff) {
    for (final s in q.slots) {
      if (!s.validFrom.isAfter(kickoff) && s.validUntil.isAfter(kickoff)) return s;
    }
    return q.slots.isEmpty ? null : q.slots.first;
  }

  @override
  State<WeatherCardGrid> createState() => _WeatherCardGridState();
}

class _WeatherCardGridState extends State<WeatherCardGrid> {
  String? _expanded;
  bool _showAll = false;

  static const _gap = 8.0;

  /// One key per metric, so a card keeps its element (and its AnimatedSize)
  /// when it moves into the full-width row, and the reveal animates in place.
  final _keys = <String, GlobalKey>{};

  Widget _card(ConsolidatedQuantity q) => WeatherValueCard(
    key: _keys.putIfAbsent(q.quantity, () => GlobalKey(debugLabel: 'card ${q.quantity}')),
    quantity: q,
    slot: WeatherCardGrid.kickoffSlot(q, widget.kickoff),
    sources: widget.weather.sources,
    expanded: _expanded == q.quantity,
    onToggle: () => setState(() => _expanded = _expanded == q.quantity ? null : q.quantity),
  );

  /// One row of collapsed cards, all stretched to the tallest card's height.
  Widget _row(List<ConsolidatedQuantity> cards, int cols) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cols; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          Expanded(child: i < cards.length ? _card(cards[i]) : const SizedBox.shrink()),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final all = widget.weather.quantities;
    final shown = _showAll ? all : all.take(widget.maxVisible).toList();
    final hidden = all.length - shown.length;
    return LayoutBuilder(
      builder: (context, c) {
        final cols = WeatherCardGrid.columns(context, c.maxWidth);
        // The expanded card takes its own full-width row, placed after the row
        // it came from; the other cards close up so no row has a hole.
        final expandedAt = shown.indexWhere((q) => q.quantity == _expanded);
        final collapsed = [
          for (final q in shown)
            if (q.quantity != _expanded) q,
        ];
        final insertAfterRow = expandedAt < 0 ? -1 : expandedAt ~/ cols;
        final rows = <Widget>[];
        for (var r = 0; r * cols < collapsed.length || r <= insertAfterRow; r++) {
          final start = r * cols;
          if (start < collapsed.length) {
            rows.add(
              _row(collapsed.sublist(start, (start + cols).clamp(0, collapsed.length)), cols),
            );
          }
          if (r == insertAfterRow) rows.add(_card(shown[expandedAt]));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: _gap),
              rows[i],
            ],
            if (all.length > widget.maxVisible)
              Padding(
                padding: const EdgeInsets.only(top: PitchySpace.xs),
                child: PitchyPressScale(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    icon: Icon(_showAll ? Icons.expand_less : Icons.expand_more),
                    label: Text(_showAll ? 'Show fewer' : 'Show $hidden more'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The card grid while loading: same columns, gaps, card padding and line
/// heights as [WeatherCardGrid] (P-17). Reserves the "Show N more" row too,
/// since the backend reports more quantities than fit.
class WeatherCardGridSkeleton extends StatelessWidget {
  const WeatherCardGridSkeleton({super.key, this.cards = 4});

  final int cards;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget card() => Card(
      child: Padding(
        padding: const EdgeInsets.all(PitchySpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The icon's row, then the label, as on the loaded card.
            Align(
              alignment: Alignment.centerLeft,
              child: SkeletonBox(
                width: WeatherQuantityIcon.sizeFor(context, text.labelLarge),
                height: WeatherQuantityIcon.sizeFor(context, text.labelLarge),
                radius: 4,
              ),
            ),
            const SizedBox(height: PitchySpace.xs),
            SkeletonLine(style: text.labelLarge, widthFactor: 0.7),
            const SizedBox(height: PitchySpace.sm),
            SkeletonLine(style: text.headlineMedium, widthFactor: 0.45),
            const SizedBox(height: PitchySpace.xs),
            SkeletonLine(style: text.bodySmall, widthFactor: 0.6),
            const SizedBox(height: PitchySpace.sm),
            SizedBox(height: WeatherValueCard.footerHeight(context)),
          ],
        ),
      ),
    );
    return SkeletonPulse(
      label: 'Loading weather',
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = WeatherCardGrid.columns(context, c.maxWidth);
          const gap = 8.0;
          final rows = (cards / cols).ceil();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) const SizedBox(height: gap),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < cols; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        Expanded(child: r * cols + i < cards ? card() : const SizedBox.shrink()),
                      ],
                    ],
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.only(top: PitchySpace.xs),
                child: SizedBox(height: AppTheme.minTarget),
              ),
            ],
          );
        },
      ),
    );
  }
}
