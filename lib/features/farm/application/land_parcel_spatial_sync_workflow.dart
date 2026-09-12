import '../../../core/spatial/domain/entities/spatial_temporal.dart';
import '../data/adapters/land_parcel_spatial_projection.dart';
import '../data/adapters/land_parcel_spatial_transaction.dart';
import '../domain/entities/land_parcel.dart';
import '../domain/entities/land_parcel_spatial_link.dart';

/// Atomically synchronizes one LandParcel state with its stable Spatial Core
/// projection.
///
/// Creation establishes the persistent LandParcel-to-SpatialFeature identity.
/// Updates resolve SpatialFeature identity from that persisted association
/// rather than trusting a caller-supplied SpatialFeature id.
///
/// Spatial revision identities remain caller supplied while revision numbers
/// are derived from persisted Spatial Core state.
class LandParcelSpatialSyncWorkflow {
  const LandParcelSpatialSyncWorkflow({
    required this.transaction,
    required this.projection,
  });

  final LandParcelSpatialTransaction transaction;
  final LandParcelSpatialProjection projection;

  Future<void> create({
    required LandParcel parcel,
    required String spatialLinkId,
    required String spatialFeatureId,
    required String spatialRevisionId,
    required SpatialTemporalState temporalState,
  }) {
    return transaction.run<void>((parcels, links, spatial) async {
      final projected = projection.project(
        parcel: parcel,
        spatialFeatureId: spatialFeatureId,
        spatialRevisionId: spatialRevisionId,
        spatialRevision: 1,
        temporalState: temporalState,
      );

      final link = LandParcelSpatialLink(
        id: spatialLinkId,
        landParcelId: parcel.id,
        spatialFeatureId: spatialFeatureId,
        createdAt: parcel.createdAt,
        createdBy: parcel.createdBy,
      );

      await parcels.create(parcel);

      await spatial.createFeature.execute(
        feature: projected.feature,
        initialRevision: projected.revision,
      );

      await links.create(link);
    });
  }

  Future<void> update({
    required LandParcel parcel,
    required String spatialRevisionId,
    required SpatialTemporalState temporalState,
  }) {
    return transaction.run<void>((parcels, links, spatial) async {
      final link = await links.findByLandParcelId(parcel.id);

      if (link == null) {
        throw StateError(
          'Land parcel ${parcel.id} has no persisted SpatialFeature link.',
        );
      }

      final spatialFeatureId = link.spatialFeatureId;

      final existingFeature = await spatial.featureRepository.findById(
        spatialFeatureId,
      );

      if (existingFeature == null) {
        throw StateError(
          'Linked Spatial feature $spatialFeatureId does not exist.',
        );
      }

      final latestRevision = await spatial.revisionRepository
          .findLatestByFeatureId(spatialFeatureId);

      if (latestRevision == null) {
        throw StateError(
          'Linked Spatial feature $spatialFeatureId has no persisted revision.',
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
