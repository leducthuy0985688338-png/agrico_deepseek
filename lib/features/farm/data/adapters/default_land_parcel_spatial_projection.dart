import '../../../../core/spatial/domain/entities/spatial_feature.dart';
import '../../../../core/spatial/domain/entities/spatial_feature_revision.dart';
import '../../../../core/spatial/domain/entities/spatial_source.dart';
import '../../../../core/spatial/domain/entities/spatial_temporal.dart';
import '../../../../core/spatial/domain/geometry/spatial_geometry_type.dart';
import '../../domain/entities/land_parcel.dart';
import 'land_parcel_spatial_projection.dart';
import 'wgs84_spatial_geometry_adapter.dart';

/// Default translation from the Farm LandParcel model into Spatial Core.
class DefaultLandParcelSpatialProjection
    implements LandParcelSpatialProjection {
  const DefaultLandParcelSpatialProjection({
    this.geometryAdapter = const Wgs84SpatialGeometryAdapter(),
  });

  final Wgs84SpatialGeometryAdapter geometryAdapter;

  @override
  LandParcelSpatialProjectionResult project({
    required LandParcel parcel,
    required String spatialFeatureId,
    required String spatialRevisionId,
    required int spatialRevision,
    required SpatialTemporalState temporalState,
    required DateTime effectiveFrom,
    String? changeReason,
  }) {
    if (spatialFeatureId.trim().isEmpty) {
      throw const FormatException('Spatial feature id cannot be blank.');
    }

    if (spatialRevisionId.trim().isEmpty) {
      throw const FormatException('Spatial revision id cannot be blank.');
    }

    if (spatialRevision <= 0) {
      throw const FormatException(
        'Spatial revision number must be greater than zero.',
      );
    }

    final currentBoundaryVersions = parcel.boundaryHistory.where(
      (version) => version.version == parcel.boundaryVersion,
    );

    if (currentBoundaryVersions.length != 1) {
      throw StateError(
        'Current LandParcel boundary version must exist exactly once.',
      );
    }

    final boundaryVersion = currentBoundaryVersions.single;
    final geometry = geometryAdapter.toSpatialPolygon(boundaryVersion.boundary);

    final feature = SpatialFeature(
      id: spatialFeatureId,
      featureType: SpatialFeatureTypes.landParcel,
      geometryType: SpatialGeometryType.polygon,
      geometry: geometry,
      lifecycleStatus: parcel.active
          ? SpatialFeatureLifecycleStatus.active
          : SpatialFeatureLifecycleStatus.inactive,
      code: parcel.parcelCode,
      name: parcel.name,
      createdAt: parcel.createdAt,
      createdBy: parcel.createdBy,
      updatedAt: parcel.updatedAt,
      updatedBy: parcel.updatedBy,
    );

    final revision = SpatialFeatureRevision(
      id: spatialRevisionId,
      featureId: spatialFeatureId,
      revision: spatialRevision,
      geometryType: SpatialGeometryType.polygon,
      geometry: geometry,
      temporalState: temporalState,
      effectivePeriod: SpatialEffectivePeriod(validFrom: effectiveFrom),
      source: SpatialSource(
        type: _mapSource(boundaryVersion.source),
        surveyedAt: boundaryVersion.occurredAt,
        surveyedBy: boundaryVersion.actorMembershipId,
        horizontalAccuracyM: boundaryVersion.horizontalAccuracyM,
        sourceReference: boundaryVersion.id,
        sourceFileName: boundaryVersion.sourceFileName,
        sourceFileHash: boundaryVersion.sourceFileHash,
        notes: boundaryVersion.note,
      ),
      geometryReference: boundaryVersion.id,
      changeReason: changeReason,
      createdAt: parcel.updatedAt,
      createdBy: parcel.updatedBy,
    );

    feature.validate();
    revision.validateAgainstFeature(feature);

    return LandParcelSpatialProjectionResult(
      feature: feature,
      revision: revision,
    );
  }

  SpatialSourceType _mapSource(BoundarySource source) {
    switch (source) {
      case BoundarySource.gps:
        return SpatialSourceType.gps;
      case BoundarySource.googleEarth:
        return SpatialSourceType.googleEarth;
      case BoundarySource.manual:
        return SpatialSourceType.manual;
      case BoundarySource.cad:
        return SpatialSourceType.autocad;
      case BoundarySource.imported:
        return SpatialSourceType.imported;
    }
  }
}
