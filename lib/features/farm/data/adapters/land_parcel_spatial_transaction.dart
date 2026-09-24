import 'package:sqflite/sqflite.dart';

import '../../../../core/spatial/data/spatial_persistence_composition.dart';
import '../../../../core/spatial/domain/entities/spatial_feature.dart';
import '../../../../core/spatial/domain/geometry/spatial_polygon.dart';
import '../../domain/repositories/land_parcel_repository.dart';
import '../../domain/repositories/land_parcel_spatial_link_repository.dart';
import '../../domain/repositories/land_survey_repository.dart';
import '../local/sqlite_land_parcel_repository.dart';
import '../local/sqlite_land_parcel_spatial_link_repository.dart';
import '../local/sqlite_land_survey_repository.dart';
import 'wgs84_spatial_geometry_adapter.dart';

/// Coordinates Land Parcel, its stable Spatial link, and Spatial Core
/// persistence inside one SQLite transaction.
///
/// This adapter owns transaction scope only. Mapping between LandParcel and
/// SpatialFeature remains an application/domain concern.
class LandParcelSpatialTransaction {
  const LandParcelSpatialTransaction(this.database);

  final Database database;

  Future<T> run<T>(
    Future<T> Function(
      LandParcelRepository parcels,
      LandParcelSpatialLinkRepository links,
      SpatialPersistenceComposition spatial,
    )
    action, {
    Future<void> Function(LandSurveyRepository surveys)? afterCreate,
  }) {
    return database.transaction((transaction) async {
      final changed = <(String, String)>{};
      final parcels = SqliteLandParcelRepository.spatialTransactionScope(
        transaction,
        (farmId, parcelId) => changed.add((farmId, parcelId)),
      );
      final links = SqliteLandParcelSpatialLinkRepository(transaction);
      final spatial = SpatialPersistenceComposition(transaction);

      final result = await action(parcels, links, spatial);
      if (afterCreate != null) {
        await afterCreate(
          SqliteLandSurveyRepository.transactionScope(transaction),
        );
      }

      // Verify the resulting state before SQLite commits the shared write.
      for (final (farmId, parcelId) in changed) {
        final parcel = await parcels.getById(farmId: farmId, id: parcelId);
        final link = await links.findByLandParcelId(parcelId);
        if (parcel == null ||
            parcel.spatialFeatureId == null ||
            link == null ||
            parcel.spatialFeatureId != link.spatialFeatureId) {
          throw StateError('Spatial-enabled parcel $parcelId has no matching persisted link.');
        }
        final feature = await spatial.featureRepository.findById(link.spatialFeatureId);
        final revision = await spatial.revisionRepository.findLatestByFeatureId(link.spatialFeatureId);
        if (feature == null ||
            revision == null ||
            feature.featureType != SpatialFeatureTypes.landParcel ||
            feature.id != revision.featureId ||
            feature.geometry is! SpatialPolygon ||
            revision.geometry is! SpatialPolygon) {
          throw StateError('Spatial-enabled parcel $parcelId has no matching spatial geometry.');
        }
        final currentBoundary = const Wgs84SpatialGeometryAdapter()
            .toWgs84Polygon(feature.geometry! as SpatialPolygon);
        final revisionBoundary = const Wgs84SpatialGeometryAdapter()
            .toWgs84Polygon(revision.geometry! as SpatialPolygon);
        if (parcel.boundary != currentBoundary ||
            parcel.boundary != revisionBoundary ||
            revision.geometryReference !=
                parcel.boundaryHistory
                    .firstWhere((item) => item.version == parcel.boundaryVersion)
                    .id) {
          throw StateError('Spatial-enabled parcel $parcelId boundary is not synchronized.');
        }
      }
      return result;
    });
  }
}
