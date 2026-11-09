import '../../../../core/spatial/domain/entities/spatial_feature.dart';
import '../../../../core/spatial/domain/geometry/spatial_geometry_type.dart';

enum CompensationParcelStatus {
  recorded,
  verified,
  compensationPending,
  partiallyCompensated,
  compensated,
  disputed,
  cancelled,
}

class PreCompensationParcel {
  const PreCompensationParcel({
    required this.id,
    required this.farmId,
    required this.parcelCode,
    required this.spatialFeatureId,
    required this.householdId,
    required this.ownerDisplayName,
    required this.status,
    required this.recordedAt,
    required this.createdAt,
    required this.createdBy,
    this.cultivationAreaId,
    this.projectId,
    this.compensationReference,
    this.notes,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;

  final String id;
  final String farmId;
  final String parcelCode;

  /// Stable Spatial Core identity of the historical parcel.
  final String spatialFeatureId;

  /// Household is a separate business entity. Historical ownership is also
  /// snapshotted in ownerDisplayName so later household edits do not erase
  /// what was recorded at compensation time.
  final String householdId;
  final String ownerDisplayName;

  /// Optional membership in an overall cultivation area.
  final String? cultivationAreaId;

  final String? projectId;
  final CompensationParcelStatus status;

  /// Date at which this pre-compensation parcel record became part of the
  /// historical baseline.
  final DateTime recordedAt;

  /// External compensation/GPMB dossier, decision, contract, or survey
  /// reference when available.
  final String? compensationReference;

  final String? notes;

  final DateTime createdAt;
  final String createdBy;
  final int schemaVersion;

  SpatialFeature toSpatialFeature() {
    final feature = SpatialFeature(
      id: spatialFeatureId,
      featureType: SpatialFeatureTypes.preCompensationParcel,
      geometryType: SpatialGeometryType.polygon,
      lifecycleStatus: SpatialFeatureLifecycleStatus.historical,
      projectId: projectId,
      code: parcelCode,
      name: ownerDisplayName,
      createdAt: createdAt,
      createdBy: createdBy,
      updatedAt: createdAt,
      updatedBy: createdBy,
    );

    feature.validate();
    return feature;
  }

  void validate() {
    _requireText(id, 'id');
    _requireText(farmId, 'farmId');
    _requireText(parcelCode, 'parcelCode');
    _requireText(spatialFeatureId, 'spatialFeatureId');
    _requireText(householdId, 'householdId');
    _requireText(ownerDisplayName, 'ownerDisplayName');
    _requireText(createdBy, 'createdBy');

    if (createdAt.isBefore(recordedAt)) {
      throw const FormatException(
        'Pre-compensation parcel creation cannot precede its recorded date.',
      );
    }

    if (schemaVersion <= 0) {
      throw const FormatException(
        'Pre-compensation parcel schemaVersion must be greater than zero.',
      );
    }

    _validateOptionalText(cultivationAreaId, 'cultivationAreaId');
    _validateOptionalText(projectId, 'projectId');
    _validateOptionalText(compensationReference, 'compensationReference');
    _validateOptionalText(notes, 'notes');
  }

  static void _requireText(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException(
        'Pre-compensation parcel $fieldName cannot be blank.',
      );
    }
  }

  static void _validateOptionalText(String? value, String fieldName) {
    if (value != null && value.trim().isEmpty) {
      throw FormatException(
        'Pre-compensation parcel $fieldName cannot be blank when provided.',
      );
    }
  }
}
