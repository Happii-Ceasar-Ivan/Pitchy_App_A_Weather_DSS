import '../../core/utils/pht_time.dart';
import '../models/weather.dart';

/// A time in PHT, with the day named when it isn't [now]'s PHT day.
String phtTimeNear(DateTime t, {required DateTime now}) {
  final a = toPhtWallClock(t), b = toPhtWallClock(now);
  final sameDay = a.year == b.year && a.month == b.month && a.day == b.day;
  return sameDay ? formatPhtTime(t) : formatPhtDateTime(t);
}

/// Why and when a source that needs data will be asked again (P-27 A4), in
/// words, from the backend's `next_request_at` and `wait_reason` only. The app
/// never works the time out itself, and doesn't repeat the backend's interval
/// lengths, which are settings that can change.
String waitLine(WaitReason? reason, DateTime at, {required DateTime now}) {
  final time = phtTimeNear(at, now: now);
  return switch (reason) {
    WaitReason.minInterval => 'Next check $time: asked recently, and Pitchy limits how often',
    WaitReason.sourceRefused => 'Next check $time: the source refused the last request',
    WaitReason.failureCooldown => 'Next try $time: the last try failed',
    WaitReason.other || null => 'Next check $time',
  };
}

/// The wait line for [source], or null when it can be asked now.
String? sourceWaitLine(SourceStatus source, {required DateTime now}) {
  final at = source.nextRequestAt;
  return at == null ? null : waitLine(source.waitReason, at, now: now);
}
