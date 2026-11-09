import '../entities/land_parcel_spatial_link.dart';

abstract interface class LandParcelSpatialLinkRepository {
  Future<LandParcelSpatialLink?> findById(String id);

  Future<LandParcelSpatialLink?> findByLandParcelId(String landParcelId);

  Future<LandParcelSpatialLink?> findBySpatialFeatureId(
    String spatialFeatureId,
  );

  /// Creates a stable primary LandParcel-to-SpatialFeature association.
  ///
  /// Implementations must reject duplicate link ids, duplicate LandParcel
  /// associations, and duplicate SpatialFeature associations.
  Future<void> create(LandParcelSpatialLink link);
}
