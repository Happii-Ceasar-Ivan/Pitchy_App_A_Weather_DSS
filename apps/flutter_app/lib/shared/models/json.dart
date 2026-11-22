/// Small, strict JSON readers for contract models.
///
/// Every reader throws [FormatException] naming the field when the backend sends
/// something the contract does not allow, so a contract drift fails loudly in tests
/// instead of silently showing wrong data.
library;

typedef Json = Map<String, Object?>;

Json asJson(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('Expected an object for "$field"', value);
}

String readString(Json json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Expected a string for "$key"', value);
}

String? readStringOrNull(Json json, String key) {
  final value = json[key];
  if (value == null || value is String) return value as String?;
  throw FormatException('Expected a string or null for "$key"', value);
}

bool readBool(Json json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Expected a boolean for "$key"', value);
}

int readInt(Json json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('Expected an integer for "$key"', value);
}

int? readIntOrNull(Json json, String key) {
  final value = json[key];
  if (value == null || value is int) return value as int?;
  throw FormatException('Expected an integer or null for "$key"', value);
}

double readDouble(Json json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  throw FormatException('Expected a number for "$key"', value);
}

double? readDoubleOrNull(Json json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw FormatException('Expected a number or null for "$key"', value);
}

/// Contract times are ISO 8601 with an explicit offset; they are kept in UTC.
DateTime readTime(Json json, String key) {
  final value = readString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !_hasOffset(value)) {
    throw FormatException('Expected an ISO 8601 time with offset for "$key"', value);
  }
  return parsed.toUtc();
}

DateTime? readTimeOrNull(Json json, String key) => json[key] == null ? null : readTime(json, key);

bool _hasOffset(String value) =>
    value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);

List<T> readList<T>(Json json, String key, T Function(Json) parse, {bool optional = false}) {
  final value = json[key];
  if (value == null && optional) return const [];
  if (value is! List) throw FormatException('Expected a list for "$key"', value);
  return [for (final item in value) parse(asJson(item, key))];
}

List<String> readStringList(Json json, String key, {bool optional = false}) {
  final value = json[key];
  if (value == null && optional) return const [];
  if (value is! List) throw FormatException('Expected a list for "$key"', value);
  return [
    for (final item in value)
      if (item is String) item else throw FormatException('Expected strings in "$key"', item),
  ];
}

T readEnum<T extends Enum>(Json json, String key, List<T> values, String Function(T) wire) {
  final value = readString(json, key);
  for (final v in values) {
    if (wire(v) == value) return v;
  }
  throw FormatException('Unknown value for "$key"', value);
}

T? readEnumOrNull<T extends Enum>(Json json, String key, List<T> values, String Function(T) wire) =>
    json[key] == null ? null : readEnum(json, key, values, wire);

/// UTC ISO 8601 with a `Z` offset, as the backend expects.
String writeTime(DateTime time) => time.toUtc().toIso8601String();
