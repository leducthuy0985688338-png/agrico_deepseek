import '../../../../core/spatial/domain/entities/spatial_feature.dart';
import '../../../../core/spatial/domain/entities/spatial_feature_revision.dart';
import '../../../../core/spatial/domain/entities/spatial_temporal.dart';
import '../../domain/entities/land_parcel.dart';

/// Result of projecting one LandParcel state into Spatial Core.
///
/// LandParcel and SpatialFeature retain separate identities. The caller owns
/// the SpatialFeature identity and revision sequence.
class LandParcelSpatialProjectionResult {
  const LandParcelSpatialProjectionResult({
    required this.feature,
    required this.revision,
  });

  final SpatialFeature feature;
  final SpatialFeatureRevision revision;
}

/// Projects the current state of a LandParcel into Spatial Core.
///
/// This adapter performs data translation only. It does not persist data,
/// allocate identities, or determine the next Spatial Core revision number.
abstract interface class LandParcelSpatialProjection {
  LandParcelSpatialProjectionResult project({
    required LandParcel parcel,
    required String spatialFeatureId,
    required String spatialRevisionId,
    required int spatialRevision,
    required SpatialTemporalState temporalState,
    required DateTime effectiveFrom,
    String? changeReason,
  });
}
