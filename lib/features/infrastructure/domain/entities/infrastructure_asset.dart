import '../../../../core/spatial/domain/entities/spatial_feature.dart';
import '../../../../core/spatial/domain/geometry/spatial_geometry_type.dart';

enum InfrastructureAssetType {
  road,
  canal,
  pipeline,
  reservoir,
  borehole,
  pumpStation,
  waterTank,
  other,
}

/// Describes where an infrastructure asset originated.
///
/// Origin is intentionally separate from temporal state. For example, an
/// existing public road may later be upgraded by the company while retaining
/// the same stable asset identity.
enum InfrastructureOrigin {
  existingPublic,
  existingPrivate,
  existingCommunity,
  companyBuilt,
  thirdPartyBuilt,
  unknown,
}

class InfrastructureAsset {
  const InfrastructureAsset({
    required this.id,
    required this.spatialFeatureId,
    required this.assetType,
    required this.origin,
    required this.createdAt,
    required this.createdBy,
    this.projectId,
    this.businessUnitId,
    this.code,
    this.name,
    this.ownerName,
    this.notes,
    this.active = true,
    this.schemaVersion = currentSchemaVersion,
  });

  static const int currentSchemaVersion = 1;

  /// Stable business identity of this infrastructure asset.
  final String id;

  /// Stable SpatialFeature identity.
  ///
  /// Geometry, temporal state and geometry revisions are owned by Spatial
  /// Core rather than duplicated in this business entity.
  final String spatialFeatureId;

  final InfrastructureAssetType assetType;

  /// Origin/ownership dimension, independent from temporal state.
  final InfrastructureOrigin origin;

  final String? projectId;
  final String? businessUnitId;
  final String? code;
  final String? name;

  /// Optional descriptive owner/operator snapshot.
  ///
  /// Formal ownership relationships can be introduced later without changing
  /// the stable identity of this asset.
  final String? ownerName;

  final String? notes;
  final bool active;

  final DateTime createdAt;
  final String createdBy;

  final int schemaVersion;

  /// Canonical Spatial Core feature type for this infrastructure asset.
  String get spatialFeatureType {
    switch (assetType) {
      case InfrastructureAssetType.road:
        return SpatialFeatureTypes.road;
      case InfrastructureAssetType.canal:
        return SpatialFeatureTypes.canal;
      case InfrastructureAssetType.pipeline:
        return SpatialFeatureTypes.pipeline;
      case InfrastructureAssetType.reservoir:
        return SpatialFeatureTypes.reservoir;
      case InfrastructureAssetType.borehole:
        return SpatialFeatureTypes.borehole;
      case InfrastructureAssetType.pumpStation:
        return SpatialFeatureTypes.pumpStation;
      case InfrastructureAssetType.waterTank:
        return SpatialFeatureTypes.waterTank;
      case InfrastructureAssetType.other:
        throw StateError(
          'Infrastructure asset type other has no canonical SpatialFeature type.',
        );
    }
  }

  /// Canonical geometry family for infrastructure types whose geometry is
  /// unambiguous at this foundation layer.
  SpatialGeometryType get defaultGeometryType {
    switch (assetType) {
      case InfrastructureAssetType.road:
      case InfrastructureAssetType.canal:
      case InfrastructureAssetType.pipeline:
        return SpatialGeometryType.lineString;
      case InfrastructureAssetType.reservoir:
        return SpatialGeometryType.polygon;
      case InfrastructureAssetType.borehole:
      case InfrastructureAssetType.pumpStation:
      case InfrastructureAssetType.waterTank:
        return SpatialGeometryType.point;
      case InfrastructureAssetType.other:
        throw StateError(
          'Infrastructure asset type other has no canonical geometry type.',
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
    _validateOptionalText(ownerName, 'ownerName');
    _validateOptionalText(notes, 'notes');

    if (schemaVersion <= 0) {
      throw const FormatException(
        'Infrastructure asset schemaVersion must be positive.',
      );
    }
  }

  static void _validateRequiredText(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException(
        'Infrastructure asset $fieldName must not be blank.',
      );
    }
  }

  static void _validateOptionalText(String? value, String fieldName) {
    if (value != null && value.trim().isEmpty) {
      throw FormatException(
        'Infrastructure asset $fieldName must not be blank when provided.',
      );
    }
  }
}
