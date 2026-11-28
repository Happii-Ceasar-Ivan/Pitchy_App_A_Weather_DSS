import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/app_scope.dart';
import '../../../core/state/loadable.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/motion.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/pht_time.dart';
import '../../../shared/models/weather.dart';
import '../../../shared/widgets/data_state_badge.dart';
import '../../../shared/widgets/link_text.dart';
import '../../../shared/widgets/pitchy_crossfade.dart';
import '../../../shared/widgets/press_scale.dart';
import '../../../shared/widgets/request_states.dart';
import '../../../shared/widgets/skeletons.dart';
import '../../../shared/widgets/weather_icons.dart';
import '../../../shared/widgets/weather_value_card.dart' show WeatherValueCard, shortSourceName;
import 'trend_painter.dart';
import 'trend_series.dart';

/// The hourly trend (P-27) in each request state: a skeleton the card's own
/// shape while loading, the card, the labelled saved copy, or its own error
/// (a failed trend never hides the tiles, and the other way round).
class TrendBlock extends StatelessWidget {
  const TrendBlock({
    super.key,
    required this.trend,
    required this.matchKickoff,
    required this.now,
    this.onRetry,
    this.onNeedHours,
  });

  /// Called with the `hours` to request when a longer range is chosen than
  /// the loaded reply holds. The owner fetches and passes the new reply.
  final ValueChanged<int>? onNeedHours;

  final Loadable<ConsolidatedWeather> trend;
  final DateTime matchKickoff;
  final DateTime now;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => switch (trend) {
    Loading() => const TrendCardSkeleton(),
    Loaded(:final value) => TrendCard(
      weather: value,
      matchKickoff: matchKickoff,
      now: now,
      onNeedHours: onNeedHours,
    ),
    Failed(saved: SavedCopy(:final value, :final savedAt)) => SavedCopyScope(
      savedAt: savedAt,
      child: TrendCard(
        weather: value,
        matchKickoff: matchKickoff,
        now: now,
        onNeedHours: onNeedHours,
      ),
    ),
    Failed(:final failure) => Card(
      child: Padding(
        padding: const EdgeInsets.all(PitchySpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Title(),
            SizedBox(
              height: 280,
              child: ErrorState(failure: failure, onRetry: onRetry),
            ),
          ],
        ),
      ),
    ),
  };
}

class _Title extends StatelessWidget {
  const _Title({this.trailing});

  final Widget? trailing;

  /// Title row height: the taller of the title and the dense state pill.
  static double height(BuildContext context) {
    final title = SkeletonLine.lineHeight(context, Theme.of(context).textTheme.titleSmall);
    final pill = DataStateBadge.denseHeight(context);
    return title > pill ? title : pill;
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: height(context)),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text('Hourly trend', style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// The chart card: which value, which range, the selected hour, the chart,
/// where the data came from and when, and the full table on request.
class TrendCard extends StatefulWidget {
  const TrendCard({
    super.key,
    required this.weather,
    required this.matchKickoff,
    required this.now,
    this.onNeedHours,
  });

  final ValueChanged<int>? onNeedHours;
  final ConsolidatedWeather weather;
  final DateTime matchKickoff;

  /// The device clock, only to name the day in times ("Mon 23 Nov").
  final DateTime now;

  /// Remembers the chosen value on this device (local, non-authoritative).
  static const quantityPref = 'trend.quantity';

  @override
  State<TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<TrendCard> {
  String? _quantity;
  TrendRange _range = TrendRange.fallback;
  int? _selected;
  bool _table = false;
  bool _restored = false;
  final _focus = FocusNode(debugLabel: 'trend chart');

  AppScope? get _scope => context.dependOnInheritedWidgetOfExactType<AppScope>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    _restored = true;
    _quantity = _scope?.preferences.getString(TrendCard.quantityPref);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  ConsolidatedQuantity? _pick(List<ConsolidatedQuantity> options) {
    for (final q in options) {
      if (q.quantity == _quantity) return q;
    }
    return options.isEmpty ? null : options.first;
  }

  /// Default hour: the one holding kickoff when it's in range, else the last
  /// hour with a value.
  int? _defaultIndex(TrendSeries s) {
    for (var i = 0; i < s.points.length; i++) {
      final p = s.points[i];
      if (!p.from.isAfter(s.kickoff) && p.until.isAfter(s.kickoff) && p.hasValue) return i;
    }
    for (var i = s.points.length - 1; i >= 0; i--) {
      if (s.points[i].hasValue) return i;
    }
    return s.points.isEmpty ? null : 0;
  }

  void _setQuantity(String q) {
    setState(() {
      _quantity = q;
      _selected = null;
    });
    _scope?.preferences.setString(TrendCard.quantityPref, q);
  }

  void _setRange(TrendRange r) {
    setState(() {
      _range = r;
      _selected = null;
    });
    // Ask only when the loaded reply doesn't already cover the range.
    if (!r.coveredBy(widget.weather, widget.matchKickoff)) widget.onNeedHours?.call(r.requestHours);
  }

  void _move(TrendSeries s, int by) {
    if (s.points.isEmpty) return;
    final from = _selected ?? _defaultIndex(s) ?? 0;
    setState(() => _selected = (from + by).clamp(0, s.points.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.weather;
    final options = chartableQuantities(w);
    final ranges = offeredRanges(w, widget.matchKickoff);
    final range = ranges.contains(_range) ? _range : TrendRange.fallback;
    final quantity = _pick(options);
    final series = quantity == null
        ? null
        : TrendSeries.build(w, quantity, range, matchKickoff: widget.matchKickoff);
    final selected = series == null
        ? null
        : (_selected != null && _selected! < series.points.length)
        ? _selected
        : _defaultIndex(series);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(PitchySpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Title(
              trailing: DataStateBadge(
                state: series?.overallState ?? WeatherDataState.missing,
                dense: true,
              ),
            ),
            const SizedBox(height: PitchySpace.md),
            _Menus(
              quantity: _LabelledMenu<String>(
                label: 'Value',
                value: quantity?.quantity,
                valueLabel: quantity?.label ?? 'None',
                entries: [
                  for (final q in options) (q.quantity, q.label, weatherIconFor(q.quantity)),
                ],
                onSelected: _setQuantity,
              ),
              range: _LabelledMenu<TrendRange>(
                label: 'Range',
                value: range,
                valueLabel: range.label,
                entries: [for (final r in ranges) (r, r.label, null)],
                onSelected: _setRange,
              ),
            ),
            const SizedBox(height: PitchySpace.md),
            if (series == null)
              const _Empty(text: 'No value has an hourly forecast for this match yet.')
            else ...[
              _Readout(series: series, index: selected, now: widget.now),
              const SizedBox(height: PitchySpace.sm),
              _Chart(
                series: series,
                selected: selected,
                focus: _focus,
                now: widget.now,
                onSelect: (i) => setState(() => _selected = i),
                onMove: (by) => _move(series, by),
              ),
              const SizedBox(height: PitchySpace.sm),
              _Footer(series: series, index: selected, weather: w, now: widget.now),
              Align(
                alignment: Alignment.centerLeft,
                child: PitchyPressScale(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _table = !_table),
                    icon: Icon(_table ? Icons.expand_less : Icons.table_rows_outlined),
                    label: Text(_table ? 'Hide table' : 'Show as table'),
                  ),
                ),
              ),
              if (_table) _Table(series: series, now: widget.now),
            ],
          ],
        ),
      ),
    );
  }
}

/// Two menus side by side; stacked on narrow cards and at large text.
class _Menus extends StatelessWidget {
  const _Menus({required this.quantity, required this.range});

  final Widget quantity;
  final Widget range;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => c.maxWidth < 480 || AppTheme.isLargeText(context)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              quantity,
              const SizedBox(height: PitchySpace.md),
              range,
            ],
          )
        : Row(
            children: [
              Expanded(child: quantity),
              const SizedBox(width: PitchySpace.sm),
              Expanded(child: range),
            ],
          ),
  );
}

/// A [DropdownMenu] whose semantics carry its label, value and a tap that
/// opens it (the plain menu gave TalkBack no name and no action; see the chat
/// role menu).
class _LabelledMenu<T extends Object> extends StatefulWidget {
  const _LabelledMenu({
    super.key,
    required this.label,
    required this.value,
    required this.valueLabel,
    required this.entries,
    required this.onSelected,
  });

  final String label;
  final T? value;
  final String valueLabel;
  final List<(T, String, IconData?)> entries;
  final ValueChanged<T> onSelected;

  @override
  State<_LabelledMenu<T>> createState() => _LabelledMenuState<T>();
}

class _LabelledMenuState<T extends Object> extends State<_LabelledMenu<T>> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.inkMuted;
    return Semantics(
      container: true,
      button: true,
      label: widget.label,
      value: widget.valueLabel,
      onTap: () => _menu.isOpen ? _menu.close() : _menu.open(),
      excludeSemantics: true,
      child: DropdownMenu<T>(
        // A new selection from outside (e.g. a range no longer offered)
        // rebuilds the field with it.
        key: ValueKey(widget.value),
        menuController: _menu,
        expandedInsets: EdgeInsets.zero,
        label: Text(widget.label),
        initialSelection: widget.value,
        requestFocusOnTap: false,
        onSelected: (v) {
          if (v != null) widget.onSelected(v);
        },
        dropdownMenuEntries: [
          for (final (v, label, icon) in widget.entries)
            DropdownMenuEntry(
              value: v,
              label: label,
              leadingIcon: icon == null ? null : Icon(icon, color: muted),
            ),
        ],
      ),
    );
  }
}

String _stateText(BuildContext context, TrendPoint p) =>
    p.hasValue ? stateWord(context, p.state) : 'No value';

/// The selected hour in words: time, value, source and state.
class _Readout extends StatelessWidget {
  const _Readout({required this.series, required this.index, required this.now});

  static double height(BuildContext context) =>
      SkeletonLine.lineHeight(context, Theme.of(context).textTheme.bodyMedium) * 2;

  final TrendSeries series;
  final int? index;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final i = index;
    if (i == null || series.points.isEmpty) return SizedBox(height: _Readout.height(context));
    final p = series.points[i];
    final parts = !p.hasValue
        ? [TrendSeries.hourRange(p, now: now), 'No source has a value for this hour']
        : [
            TrendSeries.hourRange(p, now: now),
            series.valueText(p),
            if (p.hasValue) _stateText(context, p),
            ?series.directionText(p),
            if (p.sourceName != null) shortSourceName(p.sourceName!),
            if (p.past && p.hasValue) 'forecast for a past hour',
          ];
    // Read out by the chart's own semantics (its value), not twice. Two lines
    // are always reserved, so moving between hours never shifts the chart.
    return ExcludeSemantics(
      child: SizedBox(
        height: _Readout.height(context),
        child: Builder(
          builder: (context) {
            final style = text.bodyMedium?.copyWith(
              color: p.hasValue && p.current && !SavedCopyScope.isActive(context)
                  ? context.palette.ink
                  : context.palette.inkMuted,
            );
            // The hour range ("3–4 PM") is a Line Board figure: mono.
            final hours = parts.first;
            final run = RegExp(r'\d{1,2}(?: [AP]M)?–\d{1,2} [AP]M').firstMatch(hours);
            final rest = parts.skip(1).map((e) => ' · $e').join();
            return Text.rich(
              TextSpan(
                style: style,
                children: [
                  if (run == null)
                    TextSpan(text: hours)
                  else ...[
                    TextSpan(text: hours.substring(0, run.start)),
                    PitchyFigures.figureSpans(run.group(0)!, style ?? const TextStyle()),
                    TextSpan(text: hours.substring(run.end)),
                  ],
                  TextSpan(text: rest),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
      ),
    );
  }
}

class _Chart extends StatefulWidget {
  const _Chart({
    required this.series,
    required this.selected,
    required this.focus,
    required this.now,
    required this.onSelect,
    required this.onMove,
  });

  final TrendSeries series;
  final int? selected;
  final FocusNode focus;
  final DateTime now;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onMove;

  @override
  State<_Chart> createState() => _ChartState();
}

class _ChartState extends State<_Chart> with SingleTickerProviderStateMixin {
  /// The selected-hour line's position between hours (an index, fractional
  /// while it glides). Only the line moves; everything else is instant.
  late final AnimationController _glide = AnimationController.unbounded(
    vsync: this,
    value: (widget.selected ?? 0).toDouble(),
  );

  /// True while a finger drags across the chart: the line follows it directly.
  bool _scrubbing = false;

  /// The hour the scrub last landed on, so an edge buzzes once per arrival.
  int? _lastScrub;

  @override
  void didUpdateWidget(_Chart old) {
    super.didUpdateWidget(old);
    final to = widget.selected;
    if (to == null) return;
    // Another value or range is a different chart: no glide across it.
    final sameChart =
        old.series.quantity == widget.series.quantity &&
        old.series.start == widget.series.start &&
        old.series.end == widget.series.end;
    if (old.selected == to && sameChart) return;
    final from = _glide.value;
    if (_scrubbing || !sameChart || !PitchyMotion.of(context).spring) {
      _glide
        ..stop()
        ..value = to.toDouble();
      return;
    }
    _glide.animateWith(SpringSimulation(PitchyMotion.spring, from, to.toDouble(), _glide.velocity));
  }

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  /// A finger moved to [hit] while dragging: the line follows at once, and
  /// the first and last hour give one tick each time the finger arrives.
  void _scrubTo(int hit) {
    final last = widget.series.points.length - 1;
    if ((hit == 0 || hit == last) && hit != _lastScrub) HapticFeedback.selectionClick();
    _lastScrub = hit;
  }

  void _endScrub() {
    _scrubbing = false;
    _lastScrub = null;
  }

  @override
  Widget build(BuildContext context) {
    final TrendSeries series = widget.series;
    final int? selected = widget.selected;
    final FocusNode focus = widget.focus;
    final DateTime now = widget.now;
    final ValueChanged<int> onSelect = widget.onSelect;
    final ValueChanged<int> onMove = widget.onMove;
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    // A saved copy never draws its hours in the live line colour.
    final saved = SavedCopyScope.isActive(context);
    final style = TrendChartStyle(
      line: saved ? palette.inkMuted : palette.accent,
      muted: palette.inkMuted,
      grid: palette.hairline,
      // Visible on the card surface in every theme, still lighter than a line.
      pastBand: palette.hairline.withValues(alpha: 0.8),
      surface: palette.surface,
      marker: palette.inkMuted,
      label: (text.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
        color: palette.inkMuted,
        fontWeight: FontWeight.w400,
      ),
      textScaler: scaler,
      sourceColor: palette.lineFor,
    );
    final height = TrendLayout.heightFor(style.label, scaler, arrows: series.hasDirections);
    final i = selected;
    String spoken(int at) {
      final p = series.points[at];
      return [
        TrendSeries.hourRange(p, now: now),
        series.valueText(p),
        ?series.directionText(p),
        if (p.sourceName != null) p.sourceName!,
        if (p.hasValue) _stateText(context, p),
        if (p.past && p.hasValue) 'forecast for a past hour',
      ].join(', ');
    }

    final adjustable = i != null && series.points.isNotEmpty;
    final last = series.points.length - 1;

    return Semantics(
      container: true,
      label: series.summary(now: now),
      value: adjustable ? spoken(i) : null,
      increasedValue: adjustable && i < last ? spoken(i + 1) : null,
      decreasedValue: adjustable && i > 0 ? spoken(i - 1) : null,
      hint: adjustable ? 'Swipe up or down, or use the arrow keys, to move between hours.' : null,
      onIncrease: adjustable && i < last ? () => onMove(1) : null,
      onDecrease: adjustable && i > 0 ? () => onMove(-1) : null,
      excludeSemantics: true,
      child: Focus(
        focusNode: focus,
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
          if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
            onMove(1);
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
            onMove(-1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ListenableBuilder(
          listenable: focus,
          builder: (context, child) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: focus.hasFocus ? palette.accent : Colors.transparent,
                width: 2,
              ),
            ),
            child: child,
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final size = Size(c.maxWidth, height);
              void pick(Offset local, {bool scrub = false}) {
                final hit = TrendLayout(series, size, style).indexAt(local.dx);
                if (hit != null) {
                  _scrubbing = scrub;
                  if (scrub) _scrubTo(hit);
                  onSelect(hit);
                }
                focus.requestFocus();
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => pick(d.localPosition),
                onHorizontalDragStart: (d) => pick(d.localPosition, scrub: true),
                onHorizontalDragUpdate: (d) => pick(d.localPosition, scrub: true),
                onHorizontalDragEnd: (_) => _endScrub(),
                onHorizontalDragCancel: _endScrub,
                child: SizedBox(
                  height: height,
                  // Only the drawing crossfades when the Value changes; the
                  // readout, semantics and range text are outside this.
                  child: PitchyCrossfade(
                    child: SizedBox.expand(
                      key: ValueKey(series.quantity),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: TrendPainter(
                                series: series,
                                style: style,
                                selected: i,
                                marker: _glide,
                              ),
                            ),
                          ),
                          if (series.isEmpty)
                            const Positioned.fill(
                              child: Center(
                                child: _Empty(text: 'No source has a value for this range.'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(PitchySpace.md),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const DataStateBadge(state: WeatherDataState.missing, dense: true),
        const SizedBox(width: PitchySpace.sm),
        Flexible(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    ),
  );
}

/// A time, with the PHT day named when it isn't [now]'s day.
String _near(DateTime t, DateTime now) {
  final a = toPhtWallClock(t), b = toPhtWallClock(now);
  final sameDay = a.year == b.year && a.month == b.month && a.day == b.day;
  return sameDay ? formatPhtTime(t) : formatPhtDateTime(t);
}

/// What the chart's marks mean. Always the same text, so the card keeps its
/// shape whatever the data (the skeleton draws it too, invisibly). The
/// past-hours rule comes first: it is the one that matters for safety.
const trendLegend =
    'Shaded: past hours, still forecasts, not measurements. '
    'Dashed or hollow: not current. Gap: no value.';

/// The source and issue time of the selected hour, then when it was fetched:
/// two short lines that wrap whole, never cut (the times are the point).
(String, String?) _sourceLines(TrendPoint? p, ConsolidatedWeather weather, DateTime now) {
  if (p == null || p.sourceId == null) return ('No source has a value for this hour', null);
  SourceStatus? source;
  for (final s in weather.sources) {
    if (s.sourceId == p.sourceId) source = s;
  }
  final prov = source?.provenance;
  final first = [
    shortSourceName(source?.sourceName ?? p.sourceName ?? p.sourceId!),
    if (prov?.sourceIssuedAt != null) 'issued ${_near(prov!.sourceIssuedAt!, now)}',
  ].join(' · ');
  final fetched = prov?.retrievedAt == null ? null : 'Fetched ${_near(prov!.retrievedAt!, now)}';
  return (first, fetched);
}

/// Where the selected hour came from and when, which colour in the strip is
/// which source (named, not colour alone), the key to the marks, and the
/// Open-Meteo credit (its data is in this reply).
class _Footer extends StatelessWidget {
  const _Footer({
    required this.series,
    required this.index,
    required this.weather,
    required this.now,
  });

  final TrendSeries series;
  final int? index;
  final ConsolidatedWeather weather;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final palette = context.palette;
    final i = index;
    final p = i == null || series.points.isEmpty ? null : series.points[i];
    final (first, fetched) = _sourceLines(p, weather, now);
    Attribution? credit;
    for (final a in weather.attributions) {
      if (a.sourceId == 'open_meteo') credit = a;
    }
    final used = <String, String>{
      for (final q in series.withValues) q.sourceId!: shortSourceName(q.sourceName ?? q.sourceId!),
    };
    final swatch = MediaQuery.textScalerOf(context).scale(10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(first, style: small),
        Text(fetched ?? ' ', style: small),
        const SizedBox(height: PitchySpace.sm),
        // The strip's key: each colour with its source's name.
        Semantics(
          label: 'Strip colours: ${used.values.join(', ')}',
          excludeSemantics: true,
          child: Wrap(
            spacing: PitchySpace.md,
            runSpacing: PitchySpace.xxs,
            children: [
              for (final MapEntry(:key, :value) in used.entries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: swatch * 1.6,
                      height: swatch * 0.6,
                      color: palette.lineFor(key),
                    ),
                    const SizedBox(width: PitchySpace.sm),
                    Text(value, style: small),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: PitchySpace.xs),
        Text(trendLegend, style: small),
        if (credit != null) LinkText(credit.url, label: credit.text),
      ],
    );
  }
}

/// The spread across sources for an hour (uncertainty), or null with one source.
String? _spread(TrendPoint p, String unit) {
  final r = p.range;
  if (r == null) return null;
  String n(double v) => WeatherValueCard.number(v);
  return 'sources range ${n(r.min)}–${n(r.max)} $unit (${r.count} sources)';
}

/// Every hour as a row: the accessible, large-text-friendly view of the chart.
class _Table extends StatelessWidget {
  const _Table({required this.series, required this.now});

  final TrendSeries series;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: palette.hairline),
        for (final p in series.points)
          Semantics(
            container: true,
            label: [
              TrendSeries.hourRange(p, now: now),
              series.valueText(p),
              ?series.directionText(p),
              if (p.sourceName != null) p.sourceName!,
              if (p.hasValue) _stateText(context, p),
              if (p.past && p.hasValue) 'forecast for a past hour',
              ?p.fallbackLabel,
              ?_spread(p, series.unit),
            ].join(', '),
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: PitchySpace.sm),
              child: Wrap(
                spacing: PitchySpace.md,
                runSpacing: PitchySpace.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(TrendSeries.hourRange(p, now: now), style: text.bodySmall),
                  ),
                  Text(
                    series.valueText(p),
                    style: text.titleSmall?.copyWith(
                      color: p.hasValue && p.current ? palette.ink : palette.inkMuted,
                    ),
                  ),
                  if (p.sourceName != null)
                    Text(shortSourceName(p.sourceName!), style: text.bodySmall),
                  if (series.directionText(p) case final dir?) Text(dir, style: text.bodySmall),
                  if (p.hasValue) DataStateBadge(state: p.state, dense: true),
                  if (p.past && p.hasValue) Text('past hour', style: text.bodySmall),
                  if (p.fallbackLabel != null) Text(p.fallbackLabel!, style: text.bodySmall),
                  if (_spread(p, series.unit) case final spread?)
                    Text(spread, style: text.bodySmall),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The card's shape while it loads: title, both menus, readout, the chart at
/// its real height and the footer lines, so the card lands where this was.
class TrendCardSkeleton extends StatelessWidget {
  const TrendCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final label = (text.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
      fontWeight: FontWeight.w400,
    );
    Widget menu() => const SkeletonBox(height: 56, radius: 4);
    return SkeletonPulse(
      label: 'Loading hourly trend',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(PitchySpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _Title.height(context),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SkeletonLine(style: text.titleSmall, widthFactor: 0.35),
                ),
              ),
              const SizedBox(height: PitchySpace.md),
              _Menus(quantity: menu(), range: menu()),
              const SizedBox(height: PitchySpace.md),
              SizedBox(
                height: _Readout.height(context),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SkeletonLine(style: text.bodyMedium, widthFactor: 0.7),
                ),
              ),
              const SizedBox(height: PitchySpace.sm),
              SkeletonBox(height: TrendLayout.heightFor(label, scaler), radius: 8),
              const SizedBox(height: PitchySpace.sm),
              SkeletonLine(style: text.bodySmall, widthFactor: 0.8),
              SkeletonLine(style: text.bodySmall, widthFactor: 0.4),
              const SizedBox(height: PitchySpace.sm),
              SkeletonLine(style: text.bodySmall, widthFactor: 0.3),
              const SizedBox(height: PitchySpace.xs),
              // The key is fixed text: laid out invisibly so it takes the same lines.
              Text(trendLegend, style: text.bodySmall?.copyWith(color: Colors.transparent)),
              const SizedBox(height: AppTheme.minTarget), // credit
              const SizedBox(height: AppTheme.minTarget), // table button
            ],
          ),
        ),
      ),
    );
  }
}
