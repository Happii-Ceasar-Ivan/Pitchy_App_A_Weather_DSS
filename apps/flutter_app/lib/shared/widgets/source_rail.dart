import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/pht_time.dart';
import '../models/weather.dart';
import 'data_state_badge.dart';
import 'weather_value_card.dart' show shortSourceName;

/// The Line Board's signature: every weather source is a line on the board with
/// its fixed colour, a state stop and its "current until" time, joined by a
/// rail. Under each line, its forecast validity is drawn to true time scale
/// against the match coverage window, with kickoff marked.
///
/// Shows only what the backend reports (states, times, limitations); it never
/// decides freshness itself.
class SourceRail extends StatelessWidget {
  const SourceRail({
    super.key,
    required this.sources,
    required this.checkedAt,
    required this.coverage,
    required this.kickoff,
    required this.now,
  });

  final List<SourceStatus> sources;
  final DateTime checkedAt;
  final CoverageWindow coverage;
  final DateTime kickoff;

  /// Only used to word ages ("9 h ago"), never to judge freshness.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Sources · checked ${formatPhtTime(checkedAt)}',
                style: text.labelLarge?.copyWith(color: context.palette.inkMuted),
              ),
            ),
            const SizedBox(height: 6),
            if (sources.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No weather sources reported.', style: text.bodyMedium),
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
    final hasData = p != null;
    if (hasData && !source.coversMatchTime) return '$base · doesn’t cover the whole match';
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
      label: '${source.sourceName}: ${context.stateColors.of(source.state).label}. ${_detail()}',
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
                    Text(_detail(), style: text.bodySmall),
                    if (p?.forecastValidFrom != null && p?.forecastValidUntil != null) ...[
                      const SizedBox(height: 8),
                      ValidityBar(
                        window: coverage,
                        validFrom: p!.forecastValidFrom!,
                        validUntil: p.forecastValidUntil!,
                        kickoff: kickoff,
                        color: line,
                      ),
                    ],
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
  });

  final CoverageWindow window;
  final DateTime validFrom;
  final DateTime validUntil;
  final DateTime kickoff;
  final Color color;

  double _fraction(DateTime t) {
    final total = window.end.difference(window.start).inSeconds;
    if (total <= 0) return 0;
    return (t.difference(window.start).inSeconds / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme.labelSmall?.copyWith(color: palette.inkMuted);
    return Semantics(
      label:
          'Forecast valid ${formatPhtTime(validFrom)} to ${formatPhtTime(validUntil)}. '
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
                  child: Text('to ${formatPhtTime(window.end)}', style: text),
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
    required this.track,
    required this.tick,
  });

  final CoverageWindow window;
  final DateTime validFrom;
  final DateTime validUntil;
  final DateTime kickoff;
  final Color color;
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
    final a = _x(validFrom, size.width);
    final b = _x(validUntil, size.width);
    if (b > a) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(a, y - 3, b, y + 3), r),
        Paint()..color = color,
      );
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
      old.validFrom != validFrom || old.validUntil != validUntil || old.color != color;
}
