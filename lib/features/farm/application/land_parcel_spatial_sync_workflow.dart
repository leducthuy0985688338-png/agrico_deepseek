import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/identity/spatial_identity_generator.dart';
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
/// Spatial identities are generated internally while revision numbers are
/// are derived from persisted Spatial Core state.
class LandParcelSpatialSyncWorkflow {
  const LandParcelSpatialSyncWorkflow({
    required this.transaction,
    required this.projection,
    required this.identityGenerator,
  });

  final LandParcelSpatialTransaction transaction;
  final LandParcelSpatialProjection projection;
  final SpatialIdentityGenerator identityGenerator;

  Future<void> create({
    required LandParcel parcel,
    required SpatialTemporalState temporalState,
  }) {
    final spatialLinkId = identityGenerator.newId('spatial-link');
    final spatialFeatureId = identityGenerator.newId('spatial-feature');
    final spatialRevisionId = identityGenerator.newId('spatial-revision');

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

  /// Adopts an already-persisted legacy LandParcel into Spatial Core without
  /// recreating or mutating the LandParcel itself.
  Future<void> bootstrapExisting({
    required String farmId,
    required String landParcelId,
    required SpatialTemporalState temporalState,
  }) {
    return transaction.run<void>((parcels, links, spatial) async {
      final parcel = await parcels.getById(farmId: farmId, id: landParcelId);

      if (parcel == null) {
        throw StateError(
          'Land parcel $landParcelId does not exist in farm $farmId.',
        );
      }

      final existingLink = await links.findByLandParcelId(landParcelId);

      if (existingLink != null) {
        throw StateError(
          'Land parcel $landParcelId already has a persisted SpatialFeature link.',
        );
      }

      final spatialLinkId = identityGenerator.newId('spatial-link');
      final spatialFeatureId = identityGenerator.newId('spatial-feature');
      final spatialRevisionId = identityGenerator.newId('spatial-revision');

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

      await spatial.createFeature.execute(
        feature: projected.feature,
        initialRevision: projected.revision,
      );

      await links.create(link);
    });
  }

  Future<void> update({
    required LandParcel parcel,
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

      if (existingFeature.featureType != SpatialFeatureTypes.landParcel) {
        throw StateError(
          'Linked Spatial feature $spatialFeatureId must be a LandParcel feature, '
          'but was ${existingFeature.featureType}.',
        );
      }

      final latestRevision = await spatial.revisionRepository
          .findLatestByFeatureId(spatialFeatureId);

      if (latestRevision == null) {
        throw StateError(
          'Linked Spatial feature $spatialFeatureId has no persisted revision.',
        );
      }

      final spatialRevisionId = identityGenerator.newId('spatial-revision');

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
