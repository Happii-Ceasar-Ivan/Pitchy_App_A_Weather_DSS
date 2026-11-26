// P-27 live check against the deployed backend (not part of the normal run):
//   flutter test test_live/live_p27_test.dart
// Creates one throwaway match context (like live_backend_test) and only reads:
// no update request is sent, so no PAGASA limit is touched.

import 'package:flutter_test/flutter_test.dart';
import 'package:pitchy/core/config/app_config.dart';
import 'package:pitchy/core/network/http_pitchy_api.dart';
import 'package:pitchy/features/dashboard/trend/trend_series.dart';
import 'package:pitchy/shared/models/match.dart';

void main() {
  final api = HttpPitchyApi(baseUrl: Uri.parse(AppConfig.defaultApiBaseUrl));

  test('the trend window and wait fields come back as the app reads them', () async {
    final now = DateTime.now().toUtc();
    final kickoff = DateTime.utc(now.year, now.month, now.day, now.hour).add(
      const Duration(hours: 4),
    );
    final match = await api.createMatchContext(
      MatchContextCreate(venueScopeKey: 'rizal_memorial', kickoffAt: kickoff),
    );
    final trend = await api.getWeather(match.id, hours: trendHours, hoursBefore: trendHoursBefore);
    final tiles = await api.getWeather(match.id);
    final status = await api.getWeatherStatus(match.id);

    // ignore: avoid_print
    print(
      'trend: kickoff_at=${trend.kickoffAt} coverage=${trend.coverage?.start}..${trend.coverage?.end} '
      'window=${trend.window.start}..${trend.window.end} checked_at=${trend.checkedAt}\n'
      'ranges: ${availableRanges(trend, match.kickoffAt).map((r) => r.name).join(', ')}\n'
      'chartable: ${chartableQuantities(trend).map((q) => q.quantity).join(', ')}\n'
      '${trend.quantities.map((q) => '  ${q.quantity}: ${q.slots.length} slots, '
          '${q.slots.where((s) => s.value == null).length} null, '
          'sources ${q.slots.map((s) => s.sourceId ?? '-').toSet().join('/')}').join('\n')}\n'
      'sources: ${status.sources.map((s) => '${s.sourceId}:${s.state.wire}'
          ' next=${s.nextRequestAt} reason=${s.waitReason?.wire}').join('; ')}\n'
      'tiles: kickoff_at=${tiles.kickoffAt} window=${tiles.window.start}..${tiles.window.end}',
    );

    expect(trend.kickoffAt, isNotNull, reason: 'backend without P-27 fields');
    expect(trend.coverage, isNotNull);
    expect(trend.window.start, kickoff.subtract(const Duration(hours: 6)));
    for (final q in trend.quantities) {
      expect(q.slots, hasLength(11), reason: q.quantity);
      for (var i = 1; i < q.slots.length; i++) {
        expect(q.slots[i].validFrom, q.slots[i - 1].validUntil, reason: '${q.quantity} contiguous');
      }
    }
    expect(availableRanges(trend, match.kickoffAt), TrendRange.values);
  });
}
