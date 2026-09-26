import '../../../../core/spatial/domain/entities/spatial_feature.dart';
import '../../../../core/spatial/domain/geometry/spatial_geometry_type.dart';

enum NaturalFeatureType {
  river,
  stream,
  spring,
  waterBody,
  terrainFeature,
  other,
}

/// Stable business identity for a natural geographic feature.
///
/// Geometry, survey provenance and historical revisions are owned by Spatial
/// Core. Re-surveying a river or stream therefore does not create a new
/// NaturalFeature identity.
class NaturalFeature {
  const NaturalFeature({
    required this.id,
    required this.spatialFeatureId,
    required this.featureType,
    required this.createdAt,
    required this.createdBy,
    this.projectId,
    this.businessUnitId,
    this.code,
    this.name,
    this.localName,
    this.notes,
    this.active = true,
    this.schemaVersion = currentSchemaVersion,
  });

  static const int currentSchemaVersion = 1;

  final String id;

  /// Stable SpatialFeature identity for geometry and revision history.
  final String spatialFeatureId;

  final NaturalFeatureType featureType;

  final String? projectId;
  final String? businessUnitId;
  final String? code;
  final String? name;
  final String? localName;
  final String? notes;

  final bool active;

  final DateTime createdAt;
  final String createdBy;

  final int schemaVersion;

  String get spatialFeatureType {
    switch (featureType) {
      case NaturalFeatureType.river:
        return SpatialFeatureTypes.river;
      case NaturalFeatureType.stream:
        return SpatialFeatureTypes.stream;
      case NaturalFeatureType.spring:
        return SpatialFeatureTypes.spring;
      case NaturalFeatureType.waterBody:
        return SpatialFeatureTypes.waterBody;
      case NaturalFeatureType.terrainFeature:
        return SpatialFeatureTypes.terrainFeature;
      case NaturalFeatureType.other:
        throw StateError(
          'Natural feature type other has no canonical SpatialFeature type.',
        );
    }
  }

  SpatialGeometryType get defaultGeometryType {
    switch (featureType) {
      case NaturalFeatureType.river:
      case NaturalFeatureType.stream:
        return SpatialGeometryType.lineString;
      case NaturalFeatureType.spring:
        return SpatialGeometryType.point;
      case NaturalFeatureType.waterBody:
        return SpatialGeometryType.polygon;
      case NaturalFeatureType.terrainFeature:
      case NaturalFeatureType.other:
        throw StateError(
          'Natural feature type $featureType has no single canonical geometry type.',
        );
    }
  }

  void validate() {
    _validateRequiredText(id, 'id');
    _validateRequiredText(spatialFeatureId, 'spatialFeatureId');
    _validateRequiredText(createdBy, 'createdBy');

    _validateOptionalText(projectId, 'projectId');
    _validateOptionalText(businessUnitId, 'businessUnitId');
    _validateOptionalText(code, 'code');
    _validateOptionalText(name, 'name');
    _validateOptionalText(localName, 'localName');
    _validateOptionalText(notes, 'notes');

    if (schemaVersion <= 0) {
      throw const FormatException(
        'Natural feature schemaVersion must be positive.',
      );
    }
  }

  static void _validateRequiredText(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException('Natural feature $fieldName must not be blank.');
    }
  }

  static void _validateOptionalText(String? value, String fieldName) {
    if (value != null && value.trim().isEmpty) {
      throw FormatException(
        'Natural feature $fieldName must not be blank when provided.',
      );
    }
  }
}
