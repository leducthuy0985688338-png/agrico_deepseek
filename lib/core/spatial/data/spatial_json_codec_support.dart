/// Strict readers shared by canonical Spatial Core JSON codecs.
abstract final class SpatialJsonCodecSupport {
  static Object? requiredValue(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) {
      throw FormatException('Spatial JSON is missing "$key".');
    }
    return json[key];
  }

  static String requiredString(Map<String, Object?> json, String key) {
    final value = requiredValue(json, key);
    if (value is! String) {
      throw FormatException('Spatial JSON "$key" must be a string.');
    }
    return value;
  }

  static String? nullableString(Map<String, Object?> json, String key) {
    final value = requiredValue(json, key);
    if (value != null && value is! String) {
      throw FormatException('Spatial JSON "$key" must be a string or null.');
    }
    return value as String?;
  }

  static int requiredInt(Map<String, Object?> json, String key) {
    final value = requiredValue(json, key);
    if (value is! int) {
      throw FormatException('Spatial JSON "$key" must be an integer.');
    }
    return value;
  }

  static double? nullableDouble(Map<String, Object?> json, String key) {
    final value = requiredValue(json, key);
    if (value != null && value is! num) {
      throw FormatException('Spatial JSON "$key" must be numeric or null.');
    }
    return (value as num?)?.toDouble();
  }

  static Map<String, Object?> requiredMap(
    Map<String, Object?> json,
    String key,
  ) => asMap(requiredValue(json, key), key);

  static Map<String, Object?>? nullableMap(
    Map<String, Object?> json,
    String key,
  ) {
    final value = requiredValue(json, key);
    return value == null ? null : asMap(value, key);
  }

  static Map<String, Object?> asMap(Object? value, String context) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw FormatException('Spatial JSON "$context" must be an object.');
    }
    return Map<String, Object?>.from(value);
  }

  static DateTime requiredDateTime(Map<String, Object?> json, String key) {
    final source = requiredString(json, key);
    final value = DateTime.tryParse(source);
    if (value == null) {
      throw FormatException(
        'Spatial JSON "$key" must be an ISO-8601 DateTime.',
      );
    }
    return value.toUtc();
  }

  static DateTime? nullableDateTime(Map<String, Object?> json, String key) {
    final source = nullableString(json, key);
    if (source == null) {
      return null;
    }
    final value = DateTime.tryParse(source);
    if (value == null) {
      throw FormatException(
        'Spatial JSON "$key" must be an ISO-8601 DateTime or null.',
      );
    }
    return value.toUtc();
  }

  static T requiredEnum<T extends Enum>(
    Map<String, Object?> json,
    String key,
    List<T> values,
  ) {
    final name = requiredString(json, key);
    for (final value in values) {
      if (value.name == name) {
        return value;
      }
    }
    throw FormatException('Unknown Spatial JSON "$key" value: "$name".');
  }
}
