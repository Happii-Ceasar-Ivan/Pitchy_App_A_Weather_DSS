import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/pht_time.dart';
import '../models/weather.dart';
import 'data_state_badge.dart';
import 'skeletons.dart';
import 'weather_value_card.dart' show shortSourceName;

/// The Line Board's signature: every weather source is a line on the board with
/// its fixed colour, a state stop and its "current until" time, joined by a
/// rail. Under each line, its forecast validity is drawn to true time scale
/// against the match coverage window, with kickoff marked.
///
/// Shows only what the backend reports (states, times, limitations); it never
/// decides freshness itself.
///
/// Collapsed by default (team request 2026-11-24): one row with each source's
/// line dot, short name and state pill side by side, so the weather values get
/// the space. Opening it shows the full lines with times and validity bars.
class SourceRail extends StatefulWidget {
  const SourceRail({
    super.key,
    required this.sources,
    required this.checkedAt,
    required this.coverage,
    required this.kickoff,
    required this.now,
    this.action,
    this.notice,
    this.initiallyExpanded = false,
  });

  final List<SourceStatus> sources;
  final DateTime checkedAt;
  final CoverageWindow coverage;
  final DateTime kickoff;

  /// Only used to word ages ("9 h ago"), never to judge freshness.
  final DateTime now;

  /// Header slot (48 px row, always present): the update button or progress.
  final Widget? action;

  /// Shown under the header after an update attempt (wait, failure).
  final Widget? notice;

  /// Starts with the full lines open (used by tests and reviews).
  final bool initiallyExpanded;

  @override
  State<SourceRail> createState() => _SourceRailState();
}

class _SourceRailState extends State<SourceRail> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final SourceRail(:sources, :checkedAt, :coverage, :kickoff, :now, :action, :notice) = widget;
    final toggle = Semantics(
      button: true,
      expanded: _expanded,
      label: _expanded ? 'Hide source details' : 'Show source details',
      excludeSemantics: true,
      child: IconButton(
        onPressed: _toggle,
        tooltip: _expanded ? 'Hide source details' : 'Show source details',
        icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // At least 48 px in every state, so the update button or progress
            // appearing never moves the board. Grows (two lines) only at large
            // text sizes, so the "checked ... PHT" time is never cut.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Sources · checked ${formatPhtTime(checkedAt)}',
                        style: text.labelLarge?.copyWith(color: context.palette.inkMuted),
                        // Wraps as far as it needs at large text, beside the update
                        // button and the details toggle, so the PHT time is never cut.
                      ),
                    ),
                  ),
                  if (action != null) ...[const SizedBox(width: 8), action],
                  if (sources.isNotEmpty) toggle,
                ],
              ),
            ),
            if (notice != null) ...[const SizedBox(height: 4), notice, const SizedBox(height: 4)],
            if (sources.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No weather sources reported.', style: text.bodyMedium),
              )
            else if (!_expanded)
              InkWell(
                onTap: _toggle,
                borderRadius: BorderRadius.circular(8),
                child: SourceSummaryRow(sources: sources),
              )
            else
              for (var i = 0; i < sources.length; i++)
                _SourceLine(
                  source: sources[i],
                  isFirst: i == 0,
                  isLast: i == sources.length - 1,
                  coverage: coverage,
                  kickoff: kickoff,
                  now: now,
                ),
          ],
        ),
      ),
    );
  }
}

/// The collapsed rail: one equal column per source with its line dot (filled
/// only when Current), short name and state pill (icon and word). One shape
/// for every state, so the skeleton matches it.
class SourceSummaryRow extends StatelessWidget {
  const SourceSummaryRow({super.key, required this.sources});

  final List<SourceStatus> sources;

  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < sources.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            Expanded(
              child: Semantics(
                container: true,
                label:
                    '${sources[i].sourceName}: ${context.stateColors.of(sources[i].state).label}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Dot(
                          color: palette.lineFor(sources[i].sourceId),
                          filled: sources[i].state == WeatherDataState.current,
                          surface: palette.surface,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            shortSourceName(sources[i].sourceName),
                            // No extra tracking, so "PAGASA ECMWF" fits a phone column.
                            style: text.labelMedium?.copyWith(letterSpacing: 0),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    DataStateBadge(state: sources[i].state, dense: true),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.filled, required this.surface});

  final Color color;
  final bool filled;
  final Color surface;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: filled ? color : surface,
      border: Border.all(color: color, width: 2),
    ),
  );
}

class _SourceLine extends StatelessWidget {
  const _SourceLine({
    required this.source,
    required this.isFirst,
    required this.isLast,
    required this.coverage,
    required this.kickoff,
    required this.now,
  });

  final SourceStatus source;
  final bool isFirst;
  final bool isLast;
  final CoverageWindow coverage;
  final DateTime kickoff;
  final DateTime now;

  /// A fetch from another PHT day names the day, so "4:22 PM" can't be read as today.
  String _fetched(DateTime t) {
    final a = toPhtWallClock(t), b = toPhtWallClock(now);
    final sameDay = a.year == b.year && a.month == b.month && a.day == b.day;
    return sameDay ? formatPhtTime(t) : formatPhtDateTime(t);
  }

  String _detail() {
    final p = source.provenance;
    final base = switch (source.state) {
      WeatherDataState.current =>
        source.currentUntil == null
            ? 'Current'
            : 'Current until ${formatPhtTime(source.currentUntil!)}',
      WeatherDataState.stale =>
        p?.retrievedAt == null
            ? 'Not current'
            : 'Fetched ${_fetched(p!.retrievedAt!)} · ${formatAge(p.retrievedAt!, now: now)}',
      WeatherDataState.updating => 'Updating now',
      WeatherDataState.missing => 'No forecast stored for this match yet',
      WeatherDataState.unavailable =>
        source.limitations.isNotEmpty ? source.limitations.first.message : 'Source unavailable',
    };
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final line = palette.lineFor(source.sourceId);
    final text = Theme.of(context).textTheme;
    final filled = source.state == WeatherDataState.current;
    final p = source.provenance;

    return Semantics(
      container: true,
      label:
          '${source.sourceName}: ${context.stateColors.of(source.state).label}. ${_detail()}'
          '${p != null && !source.coversMatchTime ? '. Doesn’t cover the whole match.' : ''}',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 24,
              child: CustomPaint(
                painter: _RailPainter(
                  color: line,
                  rail: palette.hairline,
                  filled: filled,
                  isFirst: isFirst,
                  isLast: isLast,
                  surface: palette.surface,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            shortSourceName(source.sourceName),
                            style: text.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        DataStateBadge(state: source.state, dense: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // One line, so every row keeps the skeleton's shape; the
                    // full text is in the tooltip and the screen-reader label.
                    Tooltip(
                      message: _detail(),
                      child: Text(
                        _detail(),
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ValidityBar(
                      window: coverage,
                      validFrom: p?.forecastValidFrom,
                      validUntil: p?.forecastValidUntil,
                      kickoff: kickoff,
                      color: line,
                      current: filled,
                      coversMatch: source.coversMatchTime,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  _RailPainter({
    required this.color,
    required this.rail,
    required this.filled,
    required this.isFirst,
    required this.isLast,
    required this.surface,
  });

  final Color color;
  final Color rail;
  final bool filled;
  final bool isFirst;
  final bool isLast;
  final Color surface;

  static const _dotY = 21.0;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final railPaint = Paint()
      ..color = rail
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(x, isFirst ? _dotY : 0),
      Offset(x, isLast ? _dotY : size.height),
      railPaint,
    );
    canvas.drawCircle(Offset(x, _dotY), 8, Paint()..color = filled ? color : surface);
    canvas.drawCircle(
      Offset(x, _dotY),
      8,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.color != color || old.filled != filled || old.isFirst != isFirst || old.isLast != isLast;
}

/// A source's forecast validity drawn to true time scale against the match
/// coverage window. Kickoff is the tick. Display only.
class ValidityBar extends StatelessWidget {
  const ValidityBar({
    super.key,
    required this.window,
    required this.validFrom,
    required this.validUntil,
    required this.kickoff,
    required this.color,
    this.current = true,
    this.coversMatch = true,
  });

  final CoverageWindow window;

  /// Null when the source has no forecast for this match: the track is drawn
  /// empty, so every rail row keeps one shape.
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime kickoff;
  final Color color;

  /// Non-current data is drawn dashed, never as a solid current line.
  final bool current;

  /// From the backend (`covers_match_time`); when false the end label says
  /// where the forecast stops.
  final bool coversMatch;

  double _fraction(DateTime t) {
    final total = window.end.difference(window.start).inSeconds;
    if (total <= 0) return 0;
    return (t.difference(window.start).inSeconds / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme.labelSmall?.copyWith(color: palette.inkMuted);
    final from = validFrom, until = validUntil;
    final endLabel = from == null || until == null
        ? 'No forecast for this match'
        : coversMatch
        ? 'to ${formatPhtTime(window.end)}'
        : 'ends ${formatPhtTime(until)}';
    return Semantics(
      label: from == null || until == null
          ? 'No forecast for this match window.'
          : 'Forecast valid ${formatPhtTime(from)} to ${formatPhtTime(until)}'
                '${coversMatch ? '' : ', not the whole match'}. '
                'Match window ${formatPhtTime(window.start)} to ${formatPhtTime(window.end)}.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 10,
            child: CustomPaint(
              painter: _ValidityPainter(
                window: window,
                validFrom: validFrom,
                validUntil: validUntil,
                kickoff: kickoff,
                color: color,
                dashed: !current,
                track: palette.hairline,
                tick: palette.ink,
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Kickoff label sits under its tick; the window ends are shown only
          // where they can't collide with it.
          Stack(
            children: [
              if (_fraction(kickoff) > 0.4)
                Text(formatPhtTime(window.start).replaceAll(' $phtLabel', ''), style: text),
              if (_fraction(kickoff) < 0.6)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(endLabel, style: text),
                ),
              Align(
                alignment: FractionalOffset(_fraction(kickoff), 0),
                child: Text(
                  'Kickoff ${formatPhtTime(kickoff).replaceAll(' $phtLabel', '')}',
                  style: text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValidityPainter extends CustomPainter {
  _ValidityPainter({
    required this.window,
    required this.validFrom,
    required this.validUntil,
    required this.kickoff,
    required this.color,
    required this.dashed,
    required this.track,
    required this.tick,
  });

  final CoverageWindow window;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime kickoff;
  final Color color;
  final bool dashed;
  final Color track;
  final Color tick;

  double _x(DateTime t, double width) {
    final total = window.end.difference(window.start).inSeconds;
    if (total <= 0) return 0;
    final f = t.difference(window.start).inSeconds / total;
    return (f.clamp(0.0, 1.0)) * width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, y - 2, size.width, 4), r),
      Paint()..color = track,
    );
    final from = validFrom, until = validUntil;
    if (from != null && until != null) {
      final a = _x(from, size.width);
      final b = _x(until, size.width);
      if (b > a && !dashed) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(a, y - 3, b, y + 3), r),
          Paint()..color = color,
        );
      } else if (b > a) {
        // Non-current data: dashes in the full line colour (readable, and the
        // same "stamped" language as the dashed STALE pill).
        final paint = Paint()..color = color;
        for (var x = a; x < b; x += 9) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTRB(x, y - 3, (x + 5).clamp(a, b), y + 3), r),
            paint,
          );
        }
      }
    }
    final k = _x(kickoff, size.width);
    canvas.drawLine(
      Offset(k, 0),
      Offset(k, size.height),
      Paint()
        ..color = tick
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ValidityPainter old) =>
      old.validFrom != validFrom ||
      old.validUntil != validUntil ||
      old.color != color ||
      old.dashed != dashed;
}

/// The source rail while loading: the same card, paddings and line heights as
/// [SourceRail], so the real rows land where the skeleton rows were (P-17).
class SourceRailSkeleton extends StatelessWidget {
  const SourceRailSkeleton({super.key, this.lines = 3});

  /// Three sources are enabled on the backend today (Open-Meteo, PAGASA ATMO,
  /// PAGASA ECMWF).
  final int lines;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SkeletonPulse(
      label: 'Loading weather sources',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: AppTheme.minTarget,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SkeletonLine(style: text.labelLarge, width: 190),
                ),
              ),
              // The collapsed summary row: one column per source.
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < lines; i++) ...[
                      if (i > 0) const SizedBox(width: SourceSummaryRow._gap),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const SkeletonBox(width: 10, height: 10, radius: 5),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: SkeletonLine(style: text.labelMedium, widthFactor: 0.8),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            SkeletonBox(
                              width: 76,
                              height: DataStateBadge.denseHeight(context),
                              radius: AppTheme.radiusPill,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
