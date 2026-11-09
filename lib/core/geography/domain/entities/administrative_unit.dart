enum AdministrativeLevel {
  country,
  region,
  state,
  province,
  municipality,
  district,
  commune,
  ward,
  village,
  other,
}

class AdministrativeUnit {
  const AdministrativeUnit({
    required this.id,
    required this.level,
    required this.name,
    required this.createdAt,
    required this.createdBy,
    this.code,
    this.parentId,
    this.countryCode,
    this.alternateName,
    this.spatialFeatureId,
    this.active = true,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;

  /// Stable identity of the administrative unit.
  final String id;

  /// Administrative hierarchy level.
  final AdministrativeLevel level;

  /// Official or commonly accepted display name.
  final String name;

  /// Optional official/local administrative code.
  final String? code;

  /// Parent administrative unit.
  ///
  /// Examples:
  /// province -> country
  /// district -> province
  /// village -> district
  final String? parentId;

  /// ISO-style country code when known, for example LA or VN.
  ///
  /// This is metadata only and does not replace the country unit relation.
  final String? countryCode;

  /// Optional alternate/localized name.
  final String? alternateName;

  /// Stable SpatialFeature identity for this administrative unit's boundary.
  ///
  /// Boundary geometry and its historical revisions are owned by Spatial Core.
  /// This reference may be null when no GIS boundary has been recorded yet.
  final String? spatialFeatureId;

  final bool active;

  final DateTime createdAt;
  final String createdBy;

  final int schemaVersion;

  void validate() {
    _requireText(id, 'id');
    _requireText(name, 'name');
    _requireText(createdBy, 'createdBy');

    _validateOptionalText(code, 'code');
    _validateOptionalText(parentId, 'parentId');
    _validateOptionalText(countryCode, 'countryCode');
    _validateOptionalText(alternateName, 'alternateName');
    _validateOptionalText(spatialFeatureId, 'spatialFeatureId');

    if (level == AdministrativeLevel.country && parentId != null) {
      throw const FormatException(
        'Country administrative unit cannot have a parent.',
      );
    }

    if (level != AdministrativeLevel.country && parentId == null) {
      throw const FormatException(
        'Non-country administrative unit must have a parent.',
      );
    }

    if (parentId == id) {
      throw const FormatException(
        'Administrative unit cannot be its own parent.',
      );
    }

    if (schemaVersion <= 0) {
      throw const FormatException(
        'Administrative unit schemaVersion must be greater than zero.',
      );
    }
  }

  static void _requireText(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException('Administrative unit $fieldName cannot be blank.');
    }
  }

  static void _validateOptionalText(String? value, String fieldName) {
    if (value != null && value.trim().isEmpty) {
      throw FormatException(
        'Administrative unit $fieldName cannot be blank when provided.',
      );
    }
  }
}
