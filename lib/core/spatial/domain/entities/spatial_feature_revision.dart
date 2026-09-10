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

  final SpatialGeometryType geometryType;
  final SpatialTemporalState temporalState;
  final SpatialEffectivePeriod effectivePeriod;
  final SpatialSource source;

  /// Reference to persisted geometry during the migration phase.
  ///
  /// Spatial Core deliberately does not duplicate the existing Farm WGS84
  /// geometry implementation yet. Concrete persistence adapters may use this
  /// field to associate the revision with its geometry payload.
  final String? geometryReference;

  final String? changeReason;
  final String? notes;

  final DateTime createdAt;
  final String createdBy;
  final int schemaVersion;

  SpatialRevisionIdentity get identity =>
      SpatialRevisionIdentity(featureId: featureId, revision: revision);

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

    if (changeReason != null && changeReason!.trim().isEmpty) {
      throw const FormatException(
        'Spatial feature revision changeReason cannot be blank.',
      );
    }
  }
}
