import 'package:flutter_test/flutter_test.dart';
import 'package:pitchy/core/utils/pht_time.dart';

void main() {
  test('UTC is shown as PHT (UTC+8) with the label', () {
    final utc = DateTime.utc(2026, 11, 23, 7, 5);
    expect(formatPhtTime(utc), '3:05 PM PHT');
    expect(formatPhtDateTime(utc), 'Mon 23 Nov, 3:05 PM PHT');
  });

  test('PHT crosses midnight correctly', () {
    expect(formatPhtDateTime(DateTime.utc(2026, 11, 23, 16, 30)), 'Tue 24 Nov, 12:30 AM PHT');
  });

  test('device time zone does not matter: a local DateTime is converted from its instant', () {
    final instant = DateTime.utc(2026, 11, 23, 0);
    expect(formatPhtTime(instant.toLocal()), '8:00 AM PHT');
  });

  test('PHT entry converts to the right UTC instant', () {
    final utc = fromPhtWallClock(2026, 11, 23, 15, 0);
    expect(utc, DateTime.utc(2026, 11, 23, 7, 0));
    expect(utc.isUtc, isTrue);
  });

  test('age labels', () {
    final now = DateTime.utc(2026, 11, 23, 12);
    expect(formatAge(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
    expect(formatAge(now.subtract(const Duration(minutes: 40)), now: now), '40 min ago');
    expect(formatAge(now.subtract(const Duration(hours: 9)), now: now), '9 h ago');
    expect(formatAge(now.subtract(const Duration(days: 3)), now: now), '3 d ago');
  });
}
