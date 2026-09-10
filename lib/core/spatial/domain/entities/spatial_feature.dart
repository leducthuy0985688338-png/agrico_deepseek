import '../geometry/spatial_geometry_type.dart';

abstract final class SpatialFeatureTypes {
  static const administrativeBoundary = 'administrativeBoundary';

  static const cultivationArea = 'cultivationArea';
  static const preCompensationParcel = 'preCompensationParcel';
  static const landParcel = 'landParcel';

  static const river = 'river';
  static const stream = 'stream';
  static const spring = 'spring';
  static const waterBody = 'waterBody';
  static const terrainFeature = 'terrainFeature';

  static const road = 'road';
  static const canal = 'canal';
  static const pipeline = 'pipeline';
  static const reservoir = 'reservoir';
  static const borehole = 'borehole';
  static const pumpStation = 'pumpStation';
  static const waterTank = 'waterTank';

  static const processingPlant = 'processingPlant';
  static const livestockFarm = 'livestockFarm';
  static const industrialSite = 'industrialSite';
  static const quarry = 'quarry';
  static const miningZone = 'miningZone';
}

enum SpatialFeatureLifecycleStatus {
  planned,
  existing,
  active,
  inactive,
  decommissioned,
  historical,
}

class SpatialFeature {
  const SpatialFeature({
    required this.id,
    required this.featureType,
    required this.geometryType,
    required this.lifecycleStatus,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.projectId,
    this.businessUnitId,
    this.name,
    this.code,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;

  /// Stable identity. Revisions must reference this id.
  final String id;

  /// Extensible controlled type identifier.
  final String featureType;

  /// Expected geometry family for this feature.
  final SpatialGeometryType geometryType;

  final SpatialFeatureLifecycleStatus lifecycleStatus;

  /// Optional organizational scope.
  final String? projectId;
  final String? businessUnitId;

  final String? code;
  final String? name;

  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final String updatedBy;
  final int schemaVersion;

  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('Spatial feature id cannot be blank.');
    }

    if (featureType.trim().isEmpty) {
      throw const FormatException('Spatial feature type cannot be blank.');
    }

    if (createdBy.trim().isEmpty || updatedBy.trim().isEmpty) {
      throw const FormatException(
        'Spatial feature audit identities cannot be blank.',
      );
    }

    if (updatedAt.isBefore(createdAt)) {
      throw const FormatException(
        'Spatial feature updatedAt cannot precede createdAt.',
      );
    }

    if (schemaVersion <= 0) {
      throw const FormatException(
        'Spatial feature schemaVersion must be greater than zero.',
      );
    }

    _validateOptionalText(projectId, 'projectId');
    _validateOptionalText(businessUnitId, 'businessUnitId');
    _validateOptionalText(code, 'code');
    _validateOptionalText(name, 'name');
  }

  static void _validateOptionalText(String? value, String fieldName) {
    if (value != null && value.trim().isEmpty) {
      throw FormatException(
        'Spatial feature $fieldName cannot be blank when provided.',
      );
    }
  }
}
