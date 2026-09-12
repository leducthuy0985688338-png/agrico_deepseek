import 'package:sqflite/sqflite.dart';

import '../../../../core/spatial/data/spatial_persistence_composition.dart';
import '../../domain/repositories/land_parcel_repository.dart';
import '../../domain/repositories/land_parcel_spatial_link_repository.dart';
import '../local/sqlite_land_parcel_repository.dart';
import '../local/sqlite_land_parcel_spatial_link_repository.dart';

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
    action,
  ) {
    return database.transaction((transaction) {
      final parcels = SqliteLandParcelRepository(transaction);
      final links = SqliteLandParcelSpatialLinkRepository(transaction);
      final spatial = SpatialPersistenceComposition(transaction);

      return action(parcels, links, spatial);
    });
  }
}
