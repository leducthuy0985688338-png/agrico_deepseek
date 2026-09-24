import '../../../core/spatial/domain/entities/spatial_feature.dart';
import '../../../core/spatial/domain/geometry/spatial_polygon.dart';
import '../../../core/spatial/domain/repositories/spatial_feature_repository.dart';
import '../../../core/spatial/domain/repositories/spatial_feature_revision_repository.dart';
import '../data/adapters/wgs84_spatial_geometry_adapter.dart';
import '../domain/entities/land_parcel.dart';
import '../domain/repositories/land_parcel_spatial_link_repository.dart';

/// A read-only diagnosis. The parcel remains the source for display and KML.
enum LandParcelBoundaryConsistency {
  unlinked,
  consistent,
  repairableLegacyIdentity,
  needsReconciliation,
}

class LandParcelBoundaryConsistencyQueries {
  const LandParcelBoundaryConsistencyQueries({
    required this.links,
    required this.features,
    required this.revisions,
  });

  final LandParcelSpatialLinkRepository links;
  final SpatialFeatureRepository features;
  final SpatialFeatureRevisionRepository revisions;

  Future<LandParcelBoundaryConsistency> check(LandParcel parcel) async {
    final link = await links.findByLandParcelId(parcel.id);
    if (link == null && parcel.spatialFeatureId == null) {
      return LandParcelBoundaryConsistency.unlinked;
    }
    if (link == null ||
        (parcel.spatialFeatureId != null &&
            link.spatialFeatureId != parcel.spatialFeatureId)) {
      return LandParcelBoundaryConsistency.needsReconciliation;
    }
    final feature = await features.findById(link.spatialFeatureId);
    final revision = await revisions.findLatestByFeatureId(link.spatialFeatureId);
    if (feature == null ||
        revision == null ||
        feature.featureType != SpatialFeatureTypes.landParcel ||
        revision.featureId != feature.id ||
        feature.geometry is! SpatialPolygon ||
        revision.geometry is! SpatialPolygon) {
      return LandParcelBoundaryConsistency.needsReconciliation;
    }
    final adapter = const Wgs84SpatialGeometryAdapter();
    final boundaryVersion = parcel.boundaryHistory.where(
      (version) => version.version == parcel.boundaryVersion,
    );
    if (boundaryVersion.length != 1 ||
        revision.geometryReference != boundaryVersion.single.id ||
        adapter.toWgs84Polygon(feature.geometry! as SpatialPolygon) !=
            parcel.boundary ||
        adapter.toWgs84Polygon(revision.geometry! as SpatialPolygon) !=
            parcel.boundary) {
      return LandParcelBoundaryConsistency.needsReconciliation;
    }
    return parcel.spatialFeatureId == null
        ? LandParcelBoundaryConsistency.repairableLegacyIdentity
        : LandParcelBoundaryConsistency.consistent;
  }
}
