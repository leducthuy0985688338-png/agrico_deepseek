import 'package:flutter_test/flutter_test.dart';

import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/default_land_parcel_spatial_projection.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';

void main() {
  const projection = DefaultLandParcelSpatialProjection();

  LandParcel parcel({
    BoundarySource source = BoundarySource.gps,
    bool active = true,
  }) {
    return LandParcel.create(
      id: 'parcel-1',
      farmId: 'farm-1',
      parcelCode: 'LP-001',
      name: 'Production parcel',
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.5000, longitude: 104.7000, altitudeM: 120),
        Wgs84Vertex(latitude: 16.5000, longitude: 104.7010, altitudeM: 121),
        Wgs84Vertex(latitude: 16.5010, longitude: 104.7010, altitudeM: 122),
        Wgs84Vertex(latitude: 16.5010, longitude: 104.7000, altitudeM: 123),
      ]),
      boundarySource: source,
      verificationStatus: BoundaryVerificationStatus.measured,
      actorMembershipId: 'member-1',
      occurredAt: DateTime.utc(2026, 9, 1, 8),
      active: active,
      horizontalAccuracyM: 1.5,
      boundaryConfidence: 0.95,
      note: 'Initial survey',
    );
  }

  test('projects LandParcel into an independent SpatialFeature identity', () {
    final result = projection.project(
      parcel: parcel(),
      spatialFeatureId: 'spatial-land-99',
      spatialRevisionId: 'spatial-land-99-r7',
      spatialRevision: 7,
      temporalState: SpatialTemporalState.operational,
    );

    expect(result.feature.id, 'spatial-land-99');
    expect(result.feature.id, isNot('parcel-1'));
    expect(result.feature.featureType, SpatialFeatureTypes.landParcel);
    expect(result.feature.geometryType, SpatialGeometryType.polygon);
    expect(result.feature.projectId, isNull);
    expect(result.feature.businessUnitId, isNull);
    expect(result.feature.code, 'LP-001');
    expect(result.feature.name, 'Production parcel');

    expect(result.revision.featureId, 'spatial-land-99');
    expect(result.revision.id, 'spatial-land-99-r7');
    expect(result.revision.revision, 7);
  });

  test('preserves polygon coordinates altitude and closed ring', () {
    final result = projection.project(
      parcel: parcel(),
      spatialFeatureId: 'spatial-1',
      spatialRevisionId: 'spatial-1-r1',
      spatialRevision: 1,
      temporalState: SpatialTemporalState.operational,
    );

    final featureGeometry = result.feature.geometry;
    final revisionGeometry = result.revision.geometry;

    expect(featureGeometry, isA<SpatialPolygon>());
    expect(revisionGeometry, isA<SpatialPolygon>());

    final polygon = featureGeometry! as SpatialPolygon;

    expect(polygon.outerRing, hasLength(5));
    expect(polygon.outerRing.first, polygon.outerRing.last);

    expect(polygon.outerRing[0].latitude, 16.5000);
    expect(polygon.outerRing[0].longitude, 104.7000);
    expect(polygon.outerRing[0].altitudeM, 120);

    expect(polygon.outerRing[1].latitude, 16.5000);
    expect(polygon.outerRing[1].longitude, 104.7010);
    expect(polygon.outerRing[1].altitudeM, 121);

    expect(polygon.outerRing[2].altitudeM, 122);
    expect(polygon.outerRing[3].altitudeM, 123);

    final revisionPolygon = revisionGeometry! as SpatialPolygon;
    expect(revisionPolygon.outerRing.length, polygon.outerRing.length);

    for (var index = 0; index < polygon.outerRing.length; index++) {
      expect(revisionPolygon.outerRing[index], polygon.outerRing[index]);
    }
  });

  test('maps active state into Spatial lifecycle', () {
    final activeResult = projection.project(
      parcel: parcel(),
      spatialFeatureId: 'spatial-active',
      spatialRevisionId: 'spatial-active-r1',
      spatialRevision: 1,
      temporalState: SpatialTemporalState.operational,
    );

    final inactiveResult = projection.project(
      parcel: parcel(active: false),
      spatialFeatureId: 'spatial-inactive',
      spatialRevisionId: 'spatial-inactive-r1',
      spatialRevision: 1,
      temporalState: SpatialTemporalState.operational,
    );

    expect(
      activeResult.feature.lifecycleStatus,
      SpatialFeatureLifecycleStatus.active,
    );
    expect(
      inactiveResult.feature.lifecycleStatus,
      SpatialFeatureLifecycleStatus.inactive,
    );
  });

  test('preserves LandParcel audit metadata on SpatialFeature', () {
    final sourceParcel = parcel();

    final result = projection.project(
      parcel: sourceParcel,
      spatialFeatureId: 'spatial-1',
      spatialRevisionId: 'spatial-1-r1',
      spatialRevision: 1,
      temporalState: SpatialTemporalState.operational,
    );

    expect(result.feature.createdAt, sourceParcel.createdAt);
    expect(result.feature.createdBy, sourceParcel.createdBy);
    expect(result.feature.updatedAt, sourceParcel.updatedAt);
    expect(result.feature.updatedBy, sourceParcel.updatedBy);
  });

  test('maps all LandParcel boundary source types explicitly', () {
    final cases = <BoundarySource, SpatialSourceType>{
      BoundarySource.gps: SpatialSourceType.gps,
      BoundarySource.googleEarth: SpatialSourceType.googleEarth,
      BoundarySource.manual: SpatialSourceType.manual,
      BoundarySource.cad: SpatialSourceType.autocad,
      BoundarySource.imported: SpatialSourceType.imported,
    };

    for (final entry in cases.entries) {
      final result = projection.project(
        parcel: parcel(source: entry.key),
        spatialFeatureId: 'spatial-${entry.key.name}',
        spatialRevisionId: 'revision-${entry.key.name}',
        spatialRevision: 1,
        temporalState: SpatialTemporalState.operational,
      );

      expect(
        result.revision.source.type,
        entry.value,
        reason: 'Boundary source ${entry.key.name}',
      );
    }
  });

  test('uses current boundary version as geometry provenance', () {
    final sourceParcel = parcel();

    final result = projection.project(
      parcel: sourceParcel,
      spatialFeatureId: 'spatial-1',
      spatialRevisionId: 'spatial-1-r1',
      spatialRevision: 1,
      temporalState: SpatialTemporalState.operational,
    );

    final boundaryVersion = sourceParcel.boundaryHistory.single;

    expect(result.revision.geometryReference, boundaryVersion.id);
    expect(result.revision.source.sourceReference, boundaryVersion.id);
    expect(result.revision.source.surveyedAt, boundaryVersion.occurredAt);
    expect(
      result.revision.source.surveyedBy,
      boundaryVersion.actorMembershipId,
    );
    expect(
      result.revision.source.horizontalAccuracyM,
      boundaryVersion.horizontalAccuracyM,
    );
    expect(result.revision.source.notes, boundaryVersion.note);
    expect(
      result.revision.effectivePeriod.validFrom,
      boundaryVersion.occurredAt,
    );
    expect(result.revision.effectivePeriod.validTo, isNull);
  });

  test('Spatial revision sequence is independent of boundary version', () {
    final sourceParcel = parcel();

    expect(sourceParcel.boundaryVersion, 1);

    final result = projection.project(
      parcel: sourceParcel,
      spatialFeatureId: 'spatial-1',
      spatialRevisionId: 'spatial-1-r9',
      spatialRevision: 9,
      temporalState: SpatialTemporalState.operational,
    );

    expect(result.revision.revision, 9);
    expect(result.revision.revision, isNot(sourceParcel.boundaryVersion));
  });

  test('passes caller-owned temporal state through unchanged', () {
    for (final state in SpatialTemporalState.values) {
      final result = projection.project(
        parcel: parcel(),
        spatialFeatureId: 'spatial-${state.name}',
        spatialRevisionId: 'revision-${state.name}',
        spatialRevision: 1,
        temporalState: state,
      );

      expect(result.revision.temporalState, state);
    }
  });

  test('rejects blank Spatial identity and invalid revision number', () {
    expect(
      () => projection.project(
        parcel: parcel(),
        spatialFeatureId: ' ',
        spatialRevisionId: 'revision-1',
        spatialRevision: 1,
        temporalState: SpatialTemporalState.operational,
      ),
      throwsFormatException,
    );

    expect(
      () => projection.project(
        parcel: parcel(),
        spatialFeatureId: 'spatial-1',
        spatialRevisionId: ' ',
        spatialRevision: 1,
        temporalState: SpatialTemporalState.operational,
      ),
      throwsFormatException,
    );

    expect(
      () => projection.project(
        parcel: parcel(),
        spatialFeatureId: 'spatial-1',
        spatialRevisionId: 'revision-1',
        spatialRevision: 0,
        temporalState: SpatialTemporalState.operational,
      ),
      throwsFormatException,
    );
  });
}
