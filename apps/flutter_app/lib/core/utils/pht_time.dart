/// Philippine Time (P-14): every time in the app is shown in `Asia/Manila`,
/// UTC+8, labelled PHT, whatever the device's own time zone is. The Philippines
/// has no daylight saving, so a fixed offset is exact.
///
/// Display only. Freshness and coverage decisions stay with the backend.
library;

const phtOffset = Duration(hours: 8);
const phtLabel = 'PHT';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Wall-clock fields of [utc] in PHT. The returned value is marked UTC only so
/// that its fields read as PHT; never compare it with a real instant.
DateTime toPhtWallClock(DateTime utc) => utc.toUtc().add(phtOffset);

/// Converts a PHT wall-clock date and time (as entered by the user) to a UTC instant.
DateTime fromPhtWallClock(int year, int month, int day, int hour, int minute) =>
    DateTime.utc(year, month, day, hour, minute).subtract(phtOffset);

String _two(int n) => n.toString().padLeft(2, '0');

/// `3:05 PM PHT`
String formatPhtTime(DateTime utc) {
  final t = toPhtWallClock(utc);
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final suffix = t.hour < 12 ? 'AM' : 'PM';
  return '$hour12:${_two(t.minute)} $suffix $phtLabel';
}

/// `Sat 23 Nov, 3:05 PM PHT`
String formatPhtDateTime(DateTime utc) {
  final t = toPhtWallClock(utc);
  return '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}, ${formatPhtTime(utc)}';
}

/// Plain-language age such as `40 min ago`, for labels like "Saved copy from ...".
/// Uses the device clock only to describe age; it never decides freshness.
String formatAge(DateTime utc, {required DateTime now}) {
  final age = now.toUtc().difference(utc.toUtc());
  if (age.isNegative || age.inMinutes < 1) return 'just now';
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  if (age.inHours < 24) return '${age.inHours} h ago';
  return '${age.inDays} d ago';
}
