// The hourly trend chart's data (P-27), as plain Dart so it can be unit
// tested without widgets. Everything here only reshapes what the backend sent:
// no value is computed, filled in, smoothed or classified. A null value stays
// a gap; a stale value stays stale.

import '../../../core/utils/pht_time.dart';
import '../../../shared/models/weather.dart';
import '../../../shared/widgets/weather_value_card.dart' show WeatherValueCard, slotState;

/// The chart's time ranges, relative to kickoff (user decision 2026-11-26).
/// A range holds the hourly slots that lie inside [kickoff + from, kickoff + to].
enum TrendRange {
  sixBefore(-6, 0, '6 h before kickoff'),
  twoBefore(-2, 0, '2 h before kickoff'),
  kickoffPlus3(0, 3, 'Kickoff to +3 h'),
  kickoffPlus5(0, 5, 'Kickoff to +5 h (match and after)'),
  kickoffPlus6(0, 6, 'Kickoff to +6 h'),
  kickoffPlus12(0, 12, 'Kickoff to +12 h'),
  kickoffPlus24(0, 24, 'Kickoff to +24 h');

  const TrendRange(this.fromHours, this.toHours, this.label);

  final int fromHours;
  final int toHours;
  final String label;

  static const fallback = kickoffPlus3;

  /// Needs the backend's `hours_before` (P-27).
  bool get beforeKickoff => fromHours < 0;

  /// The backend's `hours` (1 to 24 after kickoff) this range needs: the
  /// default request already holds up to [trendHours]; longer ranges need
  /// more, never beyond the backend's [trendMaxHours].
  int get requestHours => toHours < trendHours ? trendHours : toHours.clamp(1, trendMaxHours);

  /// Longer than the default request: offered always, fetched when chosen.
  bool get isLong => toHours > trendHours;

  /// Whether [w] already holds every hour this range shows, so choosing it
  /// needs no new request.
  bool coveredBy(ConsolidatedWeather w, DateTime matchKickoff) {
    if (toHours <= trendHours) return true;
    final end = _floorHour(trendKickoff(w, matchKickoff)).add(Duration(hours: toHours));
    return !w.window.end.isBefore(end);
  }
}

/// The default request serves the first four ranges: 6 h before kickoff to 5 h
/// after. The longer ranges ask for more hours when chosen.
const trendHoursBefore = 6;
const trendHours = 5;

/// The backend's maximum for `hours` (openapi.v1.json).
const trendMaxHours = 24;

/// Lines for continuous values; bars for an amount per hour (rain).
enum TrendKind { line, bars }

/// Quantities never charted: a direction is circular, so a line would jump at
/// 0°/360° and mislead. It stays on its tile.
const _notCharted = {'wind_direction'};

/// The quantities the value list offers: in tile order, only those with at
/// least one value in the fetched window.
List<ConsolidatedQuantity> chartableQuantities(ConsolidatedWeather w) => [
  for (final q in w.quantities)
    if (!_notCharted.contains(q.quantity) && q.slots.any((s) => s.value != null)) q,
];

/// Kickoff for the chart: the backend's exact `kickoff_at`, or the match's own
/// kickoff when an older backend didn't send it.
DateTime trendKickoff(ConsolidatedWeather w, DateTime matchKickoff) => w.kickoffAt ?? matchKickoff;

DateTime _floorHour(DateTime t) {
  final u = t.toUtc();
  return DateTime.utc(u.year, u.month, u.day, u.hour);
}

/// The ranges this reply can fill. Without `kickoff_at` the backend is older
/// than P-27: it ignored `hours_before`, so the ranges before kickoff are
/// hidden instead of shown empty.
List<TrendRange> availableRanges(ConsolidatedWeather w, DateTime matchKickoff) {
  final kickoff = _floorHour(trendKickoff(w, matchKickoff));
  return [
    for (final r in TrendRange.values)
      if (!r.isLong &&
          (!r.beforeKickoff ||
              (w.kickoffAt != null &&
                  !w.window.start.isAfter(kickoff.add(Duration(hours: r.fromHours))))))
        r,
  ];
}

/// Every range the Range menu offers: those [availableRanges] says the reply
/// can fill, then the long ones (they fetch more hours when chosen).
List<TrendRange> offeredRanges(ConsolidatedWeather w, DateTime matchKickoff) => [
  ...availableRanges(w, matchKickoff),
  for (final r in TrendRange.values)
    if (r.isLong) r,
];

/// One hour on the chart.
class TrendPoint {
  const TrendPoint({
    required this.from,
    required this.until,
    required this.value,
    required this.state,
    required this.sourceId,
    required this.sourceName,
    required this.fallbackLabel,
    required this.range,
    required this.past,
    this.direction,
    this.directionState,
  });

  final DateTime from;
  final DateTime until;

  /// Null: no source has a value for this hour (a gap).
  final double? value;

  /// The backend's state for this hour; never Current unless it said so.
  final WeatherDataState state;
  final String? sourceId;
  final String? sourceName;
  final String? fallbackLabel;
  final ValueRange? range;

  /// The hour ended before the backend's `checked_at`: still a forecast, not a
  /// measurement.
  final bool past;

  /// Wind speed only: the backend's wind direction for the same hour, in
  /// degrees the wind blows FROM (meteorological). Null when it has none.
  final double? direction;
  final WeatherDataState? directionState;

  bool get hasDirection => direction != null;
  bool get directionCurrent => directionState == WeatherDataState.current;

  bool get hasValue => value != null;
  bool get current => state == WeatherDataState.current;
  DateTime get middle => from.add(until.difference(from) ~/ 2);
}

/// A drawn connection between two neighbouring hours that both have a value.
/// Hours with a gap between them are never joined.
class TrendLink {
  const TrendLink(this.from, this.to, {required this.dashed});

  final int from;
  final int to;

  /// Either end isn't Current, so the link is drawn dashed and muted.
  final bool dashed;
}

/// The y axis: [min] to [max] with a few round [ticks]. Chosen from the data
/// only (plus fixed 0–100 for percentages and 0 as the floor for rain); never
/// from a safety threshold.
class TrendAxis {
  const TrendAxis(this.min, this.max, this.ticks);

  final double min;
  final double max;
  final List<double> ticks;

  static TrendAxis forValues(List<double> values, {required String unit, required TrendKind kind}) {
    if (unit == '%') return const TrendAxis(0, 100, [0, 25, 50, 75, 100]);
    if (values.isEmpty) return const TrendAxis(0, 1, [0, 1]);
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (kind == TrendKind.bars || lo >= 0 && unit == 'mm/h') lo = 0;
    // A minimum span of 2 units, so a small drift doesn't look dramatic and a
    // flat series sits mid-chart.
    const minSpan = 2.0;
    if (hi - lo < minSpan) {
      if (kind == TrendKind.bars) {
        hi = lo + minSpan;
      } else {
        final mid = (hi + lo) / 2;
        lo = mid - minSpan / 2;
        hi = mid + minSpan / 2;
      }
    }
    final step = _niceStep((hi - lo) / 3);
    final min = kind == TrendKind.bars ? 0.0 : (lo / step).floor() * step;
    final max = (hi / step).ceil() * step;
    final ticks = <double>[for (var t = min; t <= max + step / 2; t += step) _round(t)];
    return TrendAxis(_round(min), _round(max), ticks);
  }

  static double _niceStep(double raw) {
    if (raw <= 0) return 1;
    var magnitude = 1.0;
    while (raw >= magnitude * 10) {
      magnitude *= 10;
    }
    while (raw < magnitude) {
      magnitude /= 10;
    }
    final f = raw / magnitude;
    final nice = f <= 1
        ? 1
        : f <= 2
        ? 2
        : f <= 2.5
        ? 2.5
        : f <= 5
        ? 5
        : 10;
    return nice * magnitude;
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(6));
}

/// One quantity over one range, ready to draw and to read out.
class TrendSeries {
  const TrendSeries({
    required this.quantity,
    required this.label,
    required this.unit,
    required this.kind,
    required this.range,
    required this.points,
    required this.start,
    required this.end,
    required this.kickoff,
    required this.coverageEnd,
    required this.checkedAt,
    required this.axis,
  });

  /// Builds the series for [quantity] over [range] from the backend reply [w].
  factory TrendSeries.build(
    ConsolidatedWeather w,
    ConsolidatedQuantity quantity,
    TrendRange range, {
    required DateTime matchKickoff,
  }) {
    final kickoff = trendKickoff(w, matchKickoff);
    final base = _floorHour(kickoff);
    final start = base.add(Duration(hours: range.fromHours));
    final end = base.add(Duration(hours: range.toHours));
    final names = {for (final s in w.sources) s.sourceId: s.sourceName};
    // Wind direction rides along with wind speed, hour by hour; an hour
    // without one stays without (never taken from a neighbour).
    final dirs = <DateTime, ConsolidatedSlot>{};
    if (quantity.quantity == 'wind_speed') {
      for (final q in w.quantities) {
        if (q.quantity != 'wind_direction') continue;
        for (final s in q.slots) {
          if (s.value != null) dirs[s.validFrom] = s;
        }
      }
    }
    final points = [
      for (final s in quantity.slots)
        if (!s.validFrom.isBefore(start) && !s.validUntil.isAfter(end))
          TrendPoint(
            from: s.validFrom,
            until: s.validUntil,
            value: s.value,
            state: slotState(s, w.sources),
            sourceId: s.value == null ? null : s.sourceId,
            sourceName: s.value == null ? null : names[s.sourceId] ?? s.sourceId,
            fallbackLabel: s.fallbackLabel,
            range: s.range,
            past: !s.validUntil.isAfter(w.checkedAt),
            direction: s.value == null ? null : dirs[s.validFrom]?.value,
            directionState: s.value == null || dirs[s.validFrom] == null
                ? null
                : slotState(dirs[s.validFrom]!, w.sources),
          ),
    ];
    final kind = quantity.quantity == 'rain' ? TrendKind.bars : TrendKind.line;
    return TrendSeries(
      quantity: quantity.quantity,
      label: quantity.label,
      unit: quantity.unit,
      kind: kind,
      range: range,
      points: points,
      start: start,
      end: end,
      kickoff: kickoff,
      coverageEnd: w.coverage?.end,
      checkedAt: w.checkedAt,
      axis: TrendAxis.forValues(
        [for (final p in points) ?p.value],
        unit: quantity.unit,
        kind: kind,
      ),
    );
  }

  final String quantity;
  final String label;
  final String unit;
  final TrendKind kind;
  final TrendRange range;
  final List<TrendPoint> points;
  final DateTime start;
  final DateTime end;
  final DateTime kickoff;

  /// DEC-04 coverage end (kickoff + 2 h) from the backend; null on older backends.
  final DateTime? coverageEnd;

  /// The backend's "now" for this reply. Hours before it are past forecasts.
  final DateTime checkedAt;
  final TrendAxis axis;

  List<TrendPoint> get withValues => [
    for (final p in points)
      if (p.hasValue) p,
  ];

  bool get isEmpty => withValues.isEmpty;

  /// Hours the range spans (the plot's width), whether or not all are loaded.
  int get hours => end.difference(start).inHours.clamp(1, 1000);

  /// True when any hour has a wind direction to draw.
  bool get hasDirections => points.any((p) => p.hasDirection);

  /// "from NE (45°)": the meteorological way, where the wind comes FROM.
  String? directionText(TrendPoint p) {
    final d = p.direction;
    if (d == null) return null;
    final name = compass(d);
    final deg = ((d % 360) + 360) % 360;
    final stale = p.directionCurrent ? '' : ' (direction not current)';
    return 'from $name (${deg.round() % 360}°)$stale';
  }

  static const _compass = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

  /// The eight-point compass name for [degrees].
  static String compass(double degrees) {
    final d = ((degrees % 360) + 360) % 360;
    return _compass[((d + 22.5) ~/ 45) % 8];
  }

  int get gapCount => points.where((p) => !p.hasValue).length;

  /// Links between neighbouring hours with values. A gap breaks the line.
  List<TrendLink> get links => [
    for (var i = 0; i + 1 < points.length; i++)
      if (points[i].hasValue && points[i + 1].hasValue)
        TrendLink(i, i + 1, dashed: !points[i].current || !points[i + 1].current),
  ];

  /// The state for the whole card: the least current state among the hours
  /// with a value (Stale beats Current), or Missing when no hour has one.
  WeatherDataState get overallState {
    final shown = withValues;
    if (shown.isEmpty) return WeatherDataState.missing;
    const order = [
      WeatherDataState.unavailable,
      WeatherDataState.missing,
      WeatherDataState.stale,
      WeatherDataState.updating,
      WeatherDataState.current,
    ];
    for (final s in order) {
      if (shown.any((p) => p.state == s)) return s;
    }
    return WeatherDataState.current;
  }

  /// Sources used in this range, in order of first use.
  List<String> get sourceNames => [
    ...{for (final p in withValues) ?p.sourceName},
  ];

  bool usesSource(String id) => withValues.any((p) => p.sourceId == id);

  /// "4 PM" on the axis.
  static String hourLabel(DateTime t) {
    final pht = toPhtWallClock(t);
    final h = pht.hour % 12 == 0 ? 12 : pht.hour % 12;
    return '$h ${pht.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "4–5 PM PHT", with the day when it isn't [now]'s PHT day.
  static String hourRange(TrendPoint p, {required DateTime now}) {
    final a = toPhtWallClock(p.from), b = toPhtWallClock(p.until), n = toPhtWallClock(now);
    String h(DateTime pht) => '${pht.hour % 12 == 0 ? 12 : pht.hour % 12}';
    String ap(DateTime pht) => pht.hour < 12 ? 'AM' : 'PM';
    final from = ap(a) == ap(b) ? h(a) : '${h(a)} ${ap(a)}';
    final text = '$from–${h(b)} ${ap(b)} $phtLabel';
    final sameDay = a.year == n.year && a.month == n.month && a.day == n.day;
    if (sameDay) return text;
    final day = formatPhtDateTime(p.from).split(',').first;
    return '$day, $text';
  }

  String valueText(TrendPoint p) =>
      p.value == null ? 'No value' : '${WeatherValueCard.number(p.value!)} $unit';

  /// The screen-reader summary of the whole chart (it stands in for the
  /// painting; the table has every hour).
  String summary({required DateTime now}) {
    final head = '$label, ${range.label}';
    final dirNote = hasDirections ? ' Wind direction is where the wind comes from.' : '';
    final shown = withValues;
    if (shown.isEmpty) return '$head: no source has a value for this range.';
    TrendPoint pick(bool Function(double, double) better) =>
        shown.reduce((a, b) => better(b.value!, a.value!) ? b : a);
    final hi = pick((x, y) => x > y), lo = pick((x, y) => x < y);
    final first = shown.first, last = shown.last;
    final parts = <String>[
      '${valueText(first)} at ${hourRange(first, now: now)}'
          '${identical(first, last) ? '' : ' to ${valueText(last)} at ${hourRange(last, now: now)}'}',
      if (!identical(hi, lo)) 'highest ${valueText(hi)} at ${hourRange(hi, now: now)}',
      if (!identical(hi, lo)) 'lowest ${valueText(lo)} at ${hourRange(lo, now: now)}',
    ];
    final gaps = gapCount;
    final stale = shown.where((p) => p.state == WeatherDataState.stale).length;
    final pastCount = shown.where((p) => p.past).length;
    return [
      '$head: ${parts.join(', ')}.',
      if (gaps > 0) '$gaps ${gaps == 1 ? 'hour has' : 'hours have'} no value.',
      if (stale > 0) '$stale ${stale == 1 ? 'hour is' : 'hours are'} stale.',
      if (pastCount > 0) 'Hours already past are forecasts, not measurements.',
      'Source: ${sourceNames.join(', ')}.$dirNote',
    ].join(' ');
  }
}
