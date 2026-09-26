import '../../../../core/spatial/domain/entities/spatial_feature.dart';
import '../../../../core/spatial/domain/geometry/spatial_geometry_type.dart';

class CultivationArea {
  const CultivationArea({
    required this.id,
    required this.farmId,
    required this.areaCode,
    required this.name,
    required this.spatialFeatureId,
    required this.active,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.projectId,
    this.description,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;

  final String id;
  final String farmId;

  /// Human-readable business identifier of the overall cultivation area.
  final String areaCode;
  final String name;

  /// Stable Spatial Core identity. Geometry and its revisions are managed
  /// separately so one cultivation area can be represented by a MultiPolygon.
  final String spatialFeatureId;

  final String? projectId;
  final String? description;

  final bool active;
  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final String updatedBy;
  final int schemaVersion;

  SpatialFeature toSpatialFeature({
    required SpatialFeatureLifecycleStatus lifecycleStatus,
  }) {
    final feature = SpatialFeature(
      id: spatialFeatureId,
      featureType: SpatialFeatureTypes.cultivationArea,
      geometryType: SpatialGeometryType.multiPolygon,
      lifecycleStatus: lifecycleStatus,
      projectId: projectId,
      code: areaCode,
      name: name,
      createdAt: createdAt,
      createdBy: createdBy,
      updatedAt: updatedAt,
      updatedBy: updatedBy,
    );

    feature.validate();
    return feature;
  }

  void validate() {
    _requireText(id, 'id');
    _requireText(farmId, 'farmId');
    _requireText(areaCode, 'areaCode');
    _requireText(name, 'name');
    _requireText(spatialFeatureId, 'spatialFeatureId');
    _requireText(createdBy, 'createdBy');
    _requireText(updatedBy, 'updatedBy');

    if (updatedAt.isBefore(createdAt)) {
      throw const FormatException(
        'Cultivation area updatedAt cannot precede createdAt.',
      );
    }

    if (schemaVersion <= 0) {
      throw const FormatException(
        'Cultivation area schemaVersion must be greater than zero.',
      );
    }

    _validateOptionalText(projectId, 'projectId');
    _validateOptionalText(description, 'description');
  }

  static void _requireText(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException('Cultivation area $fieldName cannot be blank.');
    }
  }

  static void _validateOptionalText(String? value, String fieldName) {
    if (value != null && value.trim().isEmpty) {
      throw FormatException(
        'Cultivation area $fieldName cannot be blank when provided.',
      );
    }
  }
}
