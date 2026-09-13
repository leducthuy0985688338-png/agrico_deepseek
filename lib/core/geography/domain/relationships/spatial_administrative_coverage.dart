import '../../../spatial/domain/entities/spatial_temporal.dart';

enum AdministrativeCoverageType { contains, intersects, centroidWithin }

class SpatialAdministrativeCoverage {
  const SpatialAdministrativeCoverage({
    required this.id,
    required this.spatialFeatureId,
    required this.administrativeUnitId,
    required this.coverageType,
    required this.createdAt,
    required this.createdBy,
    this.coverageShare,
    this.effectivePeriod,
    this.notes,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;

  /// Stable identity of this coverage relationship.
  final String id;

  /// Stable SpatialFeature identity.
  final String spatialFeatureId;

  /// AdministrativeUnit intersected or containing the spatial feature.
  final String administrativeUnitId;

  final AdministrativeCoverageType coverageType;

  /// Optional fraction of the spatial feature covered by this administrative
  /// unit, in the range (0, 1].
  ///
  /// This value is optional because it may not be known until a spatial
  /// intersection calculation has been performed.
  final double? coverageShare;

  /// Optional period during which this administrative coverage is valid.
  ///
  /// Historical coverage remains queryable when administrative boundaries
  /// change. Null means the effective period has not been established.
  final SpatialEffectivePeriod? effectivePeriod;

  final String? notes;

  final DateTime createdAt;
  final String createdBy;

  final int schemaVersion;

  void validate() {
    _requireText(id, 'id');
    _requireText(spatialFeatureId, 'spatialFeatureId');
    _requireText(administrativeUnitId, 'administrativeUnitId');
    _requireText(createdBy, 'createdBy');

    if (spatialFeatureId == administrativeUnitId) {
      throw const FormatException(
        'Spatial feature and administrative unit cannot have the same id.',
      );
    }

    if (coverageShare != null &&
        (!coverageShare!.isFinite ||
            coverageShare! <= 0 ||
            coverageShare! > 1)) {
      throw const FormatException(
        'Administrative coverageShare must be greater than zero and at most one.',
      );
    }

    effectivePeriod?.validate();
    _validateOptionalText(notes, 'notes');

    if (schemaVersion <= 0) {
      throw const FormatException(
        'Administrative coverage schemaVersion must be greater than zero.',
      );
    }
  }

  static void _requireText(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException(
        'Administrative coverage $fieldName cannot be blank.',
      );
    }
  }

  static void _validateOptionalText(String? value, String fieldName) {
    if (value != null && value.trim().isEmpty) {
      throw FormatException(
        'Administrative coverage $fieldName cannot be blank when provided.',
      );
    }
  }
}
