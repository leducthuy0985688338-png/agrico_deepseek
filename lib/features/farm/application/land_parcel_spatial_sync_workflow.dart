import '../../../core/spatial/domain/entities/spatial_temporal.dart';
import '../data/adapters/land_parcel_spatial_projection.dart';
import '../data/adapters/land_parcel_spatial_transaction.dart';
import '../domain/entities/land_parcel.dart';

/// Atomically synchronizes one LandParcel state with its Spatial Core
/// projection.
///
/// The caller supplies the stable SpatialFeature identity and unique revision
/// identity. Spatial revision numbers are derived from persisted Spatial Core
/// state rather than from LandParcel boundary versions.
class LandParcelSpatialSyncWorkflow {
  const LandParcelSpatialSyncWorkflow({
    required this.transaction,
    required this.projection,
  });

  final LandParcelSpatialTransaction transaction;
  final LandParcelSpatialProjection projection;

  Future<void> create({
    required LandParcel parcel,
    required String spatialFeatureId,
    required String spatialRevisionId,
    required SpatialTemporalState temporalState,
  }) {
    return transaction.run<void>((parcels, spatial) async {
      final projected = projection.project(
        parcel: parcel,
        spatialFeatureId: spatialFeatureId,
        spatialRevisionId: spatialRevisionId,
        spatialRevision: 1,
        temporalState: temporalState,
      );

      await parcels.create(parcel);

      await spatial.createFeature.execute(
        feature: projected.feature,
        initialRevision: projected.revision,
      );
    });
  }

  Future<void> update({
    required LandParcel parcel,
    required String spatialFeatureId,
    required String spatialRevisionId,
    required SpatialTemporalState temporalState,
  }) {
    return transaction.run<void>((parcels, spatial) async {
      final existingFeature = await spatial.featureRepository.findById(
        spatialFeatureId,
      );

      if (existingFeature == null) {
        throw StateError('Spatial feature $spatialFeatureId does not exist.');
      }

      final latestRevision = await spatial.revisionRepository
          .findLatestByFeatureId(spatialFeatureId);

      if (latestRevision == null) {
        throw StateError(
          'Spatial feature $spatialFeatureId has no persisted revision.',
        );
      }

      final projected = projection.project(
        parcel: parcel,
        spatialFeatureId: spatialFeatureId,
        spatialRevisionId: spatialRevisionId,
        spatialRevision: latestRevision.revision + 1,
        temporalState: temporalState,
      );

      await parcels.update(parcel);

      await spatial.updateFeature.execute(
        feature: projected.feature,
        revision: projected.revision,
      );
    });
  }
}
