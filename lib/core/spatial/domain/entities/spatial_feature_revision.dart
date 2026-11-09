import '../geometry/spatial_geometry.dart';
import 'spatial_feature.dart';
import '../geometry/spatial_geometry_type.dart';
import 'spatial_source.dart';
import 'spatial_temporal.dart';

class SpatialFeatureRevision {
  const SpatialFeatureRevision({
    required this.id,
    required this.featureId,
    required this.revision,
    required this.geometryType,
    required this.temporalState,
    required this.effectivePeriod,
    required this.source,
    required this.createdAt,
    required this.createdBy,
    this.geometry,
    this.geometryReference,
    this.changeReason,
    this.notes,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;

  final String id;

  /// Stable identity of the spatial feature across all revisions.
  final String featureId;

  /// Monotonically increasing revision number within the feature.
  final int revision;

  /// Geometry type metadata retained for persistence and migration
  /// compatibility.
  final SpatialGeometryType geometryType;

  /// Concrete Spatial Core geometry payload when available.
  ///
  /// During migration, older records may contain only [geometryReference].
  final SpatialGeometry? geometry;

  final SpatialTemporalState temporalState;
  final SpatialEffectivePeriod effectivePeriod;
  final SpatialSource source;

  /// Reference to persisted geometry during the migration phase.
  ///
  /// This remains optional for backward compatibility while concrete geometry
  /// payloads are progressively adopted by Spatial Core.
  final String? geometryReference;

  final String? changeReason;
  final String? notes;

  final DateTime createdAt;
  final String createdBy;
  final int schemaVersion;

  SpatialRevisionIdentity get identity =>
      SpatialRevisionIdentity(featureId: featureId, revision: revision);

  /// Validates this revision against its stable parent feature.
  ///
  /// Revision geometry remains optional for legacy migration records, but
  /// whenever concrete geometry is present its type must agree with both the
  /// revision metadata and the parent feature.
  void validateAgainstFeature(SpatialFeature feature) {
    feature.validate();
    validate();

    if (featureId != feature.id) {
      throw const FormatException(
        'Spatial feature revision featureId must match the parent feature id.',
      );
    }

    if (geometryType != feature.geometryType) {
      throw const FormatException(
        'Spatial feature revision geometryType must match the parent feature.',
      );
    }
  }

  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'Spatial feature revision id cannot be blank.',
      );
    }

    identity.validate();
    effectivePeriod.validate();
    source.validate();

    if (createdBy.trim().isEmpty) {
      throw const FormatException(
        'Spatial feature revision createdBy cannot be blank.',
      );
    }

    if (schemaVersion <= 0) {
      throw const FormatException(
        'Spatial feature revision schemaVersion must be greater than zero.',
      );
    }

    if (geometryReference != null && geometryReference!.trim().isEmpty) {
      throw const FormatException(
        'Spatial feature revision geometryReference cannot be blank.',
      );
    }

    if (geometry != null) {
      geometry!.validate();

      if (geometry!.geometryType != geometryType) {
        throw const FormatException(
          'Spatial feature revision geometryType must match its geometry payload.',
        );
      }
    }

    if (changeReason != null && changeReason!.trim().isEmpty) {
      throw const FormatException(
        'Spatial feature revision changeReason cannot be blank.',
      );
    }
  }
}
