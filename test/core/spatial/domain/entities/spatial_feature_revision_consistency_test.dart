import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);

  SpatialFeature buildFeature({
    required String id,
    required SpatialGeometryType geometryType,
    SpatialGeometry? geometry,
  }) {
    return SpatialFeature(
      id: id,
      featureType: SpatialFeatureTypes.landParcel,
      geometryType: geometryType,
      geometry: geometry,
      lifecycleStatus: SpatialFeatureLifecycleStatus.existing,
      createdAt: createdAt,
      createdBy: 'user-1',
      updatedAt: createdAt,
      updatedBy: 'user-1',
    );
  }

  SpatialFeatureRevision buildRevision({
    required String featureId,
    required SpatialGeometryType geometryType,
    SpatialGeometry? geometry,
  }) {
    return SpatialFeatureRevision(
      id: '$featureId-revision-1',
      featureId: featureId,
      revision: 1,
      geometryType: geometryType,
      geometry: geometry,
      temporalState: SpatialTemporalState.baseline,
      effectivePeriod: SpatialEffectivePeriod(validFrom: createdAt),
      source: const SpatialSource(type: SpatialSourceType.manual),
      createdAt: createdAt,
      createdBy: 'user-1',
    );
  }

  group('SpatialFeatureRevision consistency', () {
    test('accepts revision matching feature identity and geometry type', () {
      final feature = buildFeature(
        id: 'parcel-1',
        geometryType: SpatialGeometryType.polygon,
        geometry: SpatialPolygon.fromOuterRing(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.5, longitude: 104.8),
          SpatialCoordinate(latitude: 16.6, longitude: 104.8),
          SpatialCoordinate(latitude: 16.6, longitude: 104.7),
        ]),
      );

      final revision = buildRevision(
        featureId: feature.id,
        geometryType: SpatialGeometryType.polygon,
        geometry: SpatialPolygon.fromOuterRing(const [
          SpatialCoordinate(latitude: 16.51, longitude: 104.71),
          SpatialCoordinate(latitude: 16.51, longitude: 104.81),
          SpatialCoordinate(latitude: 16.61, longitude: 104.81),
          SpatialCoordinate(latitude: 16.61, longitude: 104.71),
        ]),
      );

      expect(() => revision.validateAgainstFeature(feature), returnsNormally);
    });

    test('rejects revision referencing another feature', () {
      final feature = buildFeature(
        id: 'parcel-1',
        geometryType: SpatialGeometryType.polygon,
      );

      final revision = buildRevision(
        featureId: 'parcel-2',
        geometryType: SpatialGeometryType.polygon,
      );

      expect(
        () => revision.validateAgainstFeature(feature),
        throwsFormatException,
      );
    });

    test('rejects revision with geometry type different from feature', () {
      final feature = buildFeature(
        id: 'parcel-1',
        geometryType: SpatialGeometryType.polygon,
      );

      final revision = buildRevision(
        featureId: feature.id,
        geometryType: SpatialGeometryType.lineString,
        geometry: SpatialLineString.fromCoordinates(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.6, longitude: 104.8),
        ]),
      );

      expect(
        () => revision.validateAgainstFeature(feature),
        throwsFormatException,
      );
    });

    test('accepts metadata-only feature and revision during migration', () {
      final feature = buildFeature(
        id: 'parcel-legacy-1',
        geometryType: SpatialGeometryType.polygon,
      );

      final revision = buildRevision(
        featureId: feature.id,
        geometryType: SpatialGeometryType.polygon,
      );

      expect(() => revision.validateAgainstFeature(feature), returnsNormally);
    });

    test('accepts feature geometry with metadata-only revision', () {
      final feature = buildFeature(
        id: 'parcel-2',
        geometryType: SpatialGeometryType.polygon,
        geometry: SpatialPolygon.fromOuterRing(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.5, longitude: 104.8),
          SpatialCoordinate(latitude: 16.6, longitude: 104.8),
          SpatialCoordinate(latitude: 16.6, longitude: 104.7),
        ]),
      );

      final revision = buildRevision(
        featureId: feature.id,
        geometryType: SpatialGeometryType.polygon,
      );

      expect(() => revision.validateAgainstFeature(feature), returnsNormally);
    });

    test('accepts line feature and matching line revision', () {
      final feature = buildFeature(
        id: 'road-1',
        geometryType: SpatialGeometryType.lineString,
        geometry: SpatialLineString.fromCoordinates(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.6, longitude: 104.8),
        ]),
      );

      final revision = buildRevision(
        featureId: feature.id,
        geometryType: SpatialGeometryType.lineString,
        geometry: SpatialLineString.fromCoordinates(const [
          SpatialCoordinate(latitude: 16.51, longitude: 104.71),
          SpatialCoordinate(latitude: 16.61, longitude: 104.81),
        ]),
      );

      expect(() => revision.validateAgainstFeature(feature), returnsNormally);
    });
  });
}
