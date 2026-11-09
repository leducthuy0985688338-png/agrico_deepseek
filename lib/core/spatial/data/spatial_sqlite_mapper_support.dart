import 'dart:convert';

/// Strict parsing and consistency checks shared by Spatial SQLite row mappers.
abstract final class SpatialSqliteMapperSupport {
  static Object? requiredValue(Map<String, Object?> row, String key) {
    if (!row.containsKey(key)) {
      throw FormatException('Spatial SQLite row is missing "$key".');
    }
    return row[key];
  }

  static String requiredString(Map<String, Object?> row, String key) {
    final value = requiredValue(row, key);
    if (value is! String) {
      throw FormatException('Spatial SQLite "$key" must be TEXT.');
    }
    return value;
  }

  static String? nullableString(Map<String, Object?> row, String key) {
    final value = requiredValue(row, key);
    if (value != null && value is! String) {
      throw FormatException('Spatial SQLite "$key" must be TEXT or NULL.');
    }
    return value as String?;
  }

  static int requiredInt(Map<String, Object?> row, String key) {
    final value = requiredValue(row, key);
    if (value is! int) {
      throw FormatException('Spatial SQLite "$key" must be INTEGER.');
    }
    return value;
  }

  static double? nullableDouble(Map<String, Object?> row, String key) {
    final value = requiredValue(row, key);
    if (value != null && value is! num) {
      throw FormatException('Spatial SQLite "$key" must be REAL or NULL.');
    }
    return (value as num?)?.toDouble();
  }

  static DateTime requiredDateTime(Map<String, Object?> row, String key) {
    final source = requiredString(row, key);
    final value = DateTime.tryParse(source);
    if (value == null) {
      throw FormatException('Spatial SQLite "$key" must be an ISO-8601 TEXT.');
    }
    return value.toUtc();
  }

  static DateTime? nullableDateTime(Map<String, Object?> row, String key) {
    final source = nullableString(row, key);
    if (source == null) return null;
    final value = DateTime.tryParse(source);
    if (value == null) {
      throw FormatException('Spatial SQLite "$key" must be ISO-8601 TEXT or NULL.');
    }
    return value.toUtc();
  }

  static Map<String, Object?> requiredJsonObject(
    Map<String, Object?> row,
    String key,
  ) => _decodeObject(requiredString(row, key), key);

  static Map<String, Object?>? nullableJsonObject(
    Map<String, Object?> row,
    String key,
  ) {
    final source = nullableString(row, key);
    return source == null ? null : _decodeObject(source, key);
  }

  static Map<String, Object?> _decodeObject(String source, String key) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Spatial SQLite "$key" contains invalid JSON: $error');
    }
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw FormatException('Spatial SQLite "$key" must contain a JSON object.');
    }
    return Map<String, Object?>.from(decoded);
  }

  static void expectValue(Object? actual, Object? expected, String key) {
    if (actual != expected) {
      throw FormatException(
        'Spatial SQLite "$key" contradicts canonical payload.',
      );
    }
  }

  static void expectDateTime(
    DateTime actual,
    DateTime expected,
    String key,
  ) => expectValue(actual, expected.toUtc(), key);

  static void expectNullableDateTime(
    DateTime? actual,
    DateTime? expected,
    String key,
  ) => expectValue(actual, expected?.toUtc(), key);
}
