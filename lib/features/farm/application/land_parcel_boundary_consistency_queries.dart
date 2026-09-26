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

enum LandParcelBoundaryIssue {
  missingLink,
  identityMismatch,
  missingFeature,
  wrongFeatureType,
  missingRevision,
  invalidGeometry,
  missingBoundaryVersion,
  boundaryReferenceMismatch,
  boundaryGeometryMismatch,
}

class LandParcelBoundaryDiagnosis {
  const LandParcelBoundaryDiagnosis(this.consistency, [this.issue]);

  final LandParcelBoundaryConsistency consistency;
  final LandParcelBoundaryIssue? issue;
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

  Future<LandParcelBoundaryConsistency> check(LandParcel parcel) async =>
      (await diagnose(parcel)).consistency;

  Future<LandParcelBoundaryDiagnosis> diagnose(LandParcel parcel) async {
    final link = await links.findByLandParcelId(parcel.id);
    if (link == null && parcel.spatialFeatureId == null) {
      return const LandParcelBoundaryDiagnosis(
        LandParcelBoundaryConsistency.unlinked,
      );
    }
    if (link == null) {
      return const LandParcelBoundaryDiagnosis(
        LandParcelBoundaryConsistency.needsReconciliation,
        LandParcelBoundaryIssue.missingLink,
      );
    }
    if (parcel.spatialFeatureId != null &&
        link.spatialFeatureId != parcel.spatialFeatureId) {
      return const LandParcelBoundaryDiagnosis(
        LandParcelBoundaryConsistency.needsReconciliation,
        LandParcelBoundaryIssue.identityMismatch,
      );
    }
    final feature = await features.findById(link.spatialFeatureId);
    if (feature == null) {
      return const LandParcelBoundaryDiagnosis(
        LandParcelBoundaryConsistency.needsReconciliation,
        LandParcelBoundaryIssue.missingFeature,
      );
    }
    if (feature.featureType != SpatialFeatureTypes.landParcel) {
      return const LandParcelBoundaryDiagnosis(
        LandParcelBoundaryConsistency.needsReconciliation,
        LandParcelBoundaryIssue.wrongFeatureType,
      );
    }
    final revision = await revisions.findLatestByFeatureId(link.spatialFeatureId);
    if (revision == null || revision.featureId != feature.id) {
      return const LandParcelBoundaryDiagnosis(
        LandParcelBoundaryConsistency.needsReconciliation,
        LandParcelBoundaryIssue.missingRevision,
      );
    }
    if (feature.geometry is! SpatialPolygon ||
        revision.geometry is! SpatialPolygon) {
      return const LandParcelBoundaryDiagnosis(
        LandParcelBoundaryConsistency.needsReconciliation,
        LandParcelBoundaryIssue.invalidGeometry,
      );
    }
    final adapter = const Wgs84SpatialGeometryAdapter();
    final boundaryVersion = parcel.boundaryHistory.where(
      (version) => version.version == parcel.boundaryVersion,
    );
    if (boundaryVersion.length != 1) {
      return const LandParcelBoundaryDiagnosis(
        LandParcelBoundaryConsistency.needsReconciliation,
        LandParcelBoundaryIssue.missingBoundaryVersion,
      );
    }
    if (revision.geometryReference != boundaryVersion.single.id) {
      return const LandParcelBoundaryDiagnosis(
        LandParcelBoundaryConsistency.needsReconciliation,
        LandParcelBoundaryIssue.boundaryReferenceMismatch,
      );
    }
    if (adapter.toWgs84Polygon(feature.geometry! as SpatialPolygon) !=
            parcel.boundary ||
        adapter.toWgs84Polygon(revision.geometry! as SpatialPolygon) !=
            parcel.boundary) {
      return const LandParcelBoundaryDiagnosis(
        LandParcelBoundaryConsistency.needsReconciliation,
        LandParcelBoundaryIssue.boundaryGeometryMismatch,
      );
    }
    return LandParcelBoundaryDiagnosis(
      parcel.spatialFeatureId == null
          ? LandParcelBoundaryConsistency.repairableLegacyIdentity
          : LandParcelBoundaryConsistency.consistent,
    );
  }
}
