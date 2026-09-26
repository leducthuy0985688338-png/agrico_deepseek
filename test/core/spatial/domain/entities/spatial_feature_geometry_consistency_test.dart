import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);

  SpatialFeature buildFeature({
    required SpatialGeometryType geometryType,
    SpatialGeometry? geometry,
    SpatialFeatureLifecycleStatus lifecycleStatus =
        SpatialFeatureLifecycleStatus.existing,
  }) {
    return SpatialFeature(
      id: 'feature-geometry-consistency-1',
      featureType: SpatialFeatureTypes.landParcel,
      geometryType: geometryType,
      geometry: geometry,
      lifecycleStatus: lifecycleStatus,
      createdAt: createdAt,
      createdBy: 'user-1',
      updatedAt: createdAt,
      updatedBy: 'user-1',
    );
  }

  group('SpatialFeature geometry consistency', () {
    test('accepts point geometry with point geometryType', () {
      final feature = buildFeature(
        geometryType: SpatialGeometryType.point,
        geometry: const SpatialPoint(
          coordinate: SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        ),
      );

      expect(feature.validate, returnsNormally);
    });

    test('accepts lineString geometry with lineString geometryType', () {
      final feature = buildFeature(
        geometryType: SpatialGeometryType.lineString,
        geometry: SpatialLineString.fromCoordinates(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.6, longitude: 104.8),
        ]),
      );

      expect(feature.validate, returnsNormally);
    });

    test('accepts polygon geometry with polygon geometryType', () {
      final feature = buildFeature(
        geometryType: SpatialGeometryType.polygon,
        geometry: SpatialPolygon.fromOuterRing(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.5, longitude: 104.8),
          SpatialCoordinate(latitude: 16.6, longitude: 104.8),
          SpatialCoordinate(latitude: 16.6, longitude: 104.7),
        ]),
      );

      expect(feature.validate, returnsNormally);
    });

    test('rejects point geometry declared as lineString', () {
      final feature = buildFeature(
        geometryType: SpatialGeometryType.lineString,
        geometry: const SpatialPoint(
          coordinate: SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        ),
      );

      expect(feature.validate, throwsFormatException);
    });

    test('rejects lineString geometry declared as polygon', () {
      final feature = buildFeature(
        geometryType: SpatialGeometryType.polygon,
        geometry: SpatialLineString.fromCoordinates(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.6, longitude: 104.8),
        ]),
      );

      expect(feature.validate, throwsFormatException);
    });

    test('rejects polygon geometry declared as point', () {
      final feature = buildFeature(
        geometryType: SpatialGeometryType.point,
        geometry: SpatialPolygon.fromOuterRing(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.5, longitude: 104.8),
          SpatialCoordinate(latitude: 16.6, longitude: 104.8),
          SpatialCoordinate(latitude: 16.6, longitude: 104.7),
        ]),
      );

      expect(feature.validate, throwsFormatException);
    });

    test('delegates validation to concrete geometry', () {
      final feature = buildFeature(
        geometryType: SpatialGeometryType.point,
        geometry: const SpatialPoint(
          coordinate: SpatialCoordinate(latitude: 91, longitude: 104.7),
        ),
      );

      expect(feature.validate, throwsFormatException);
    });

    test('allows metadata-only legacy feature', () {
      final feature = buildFeature(geometryType: SpatialGeometryType.polygon);

      expect(feature.geometry, isNull);
      expect(feature.validate, returnsNormally);
    });

    test('allows planned feature without geometry during migration', () {
      final feature = buildFeature(
        geometryType: SpatialGeometryType.polygon,
        lifecycleStatus: SpatialFeatureLifecycleStatus.planned,
      );

      expect(feature.geometry, isNull);
      expect(feature.validate, returnsNormally);
    });
  });
}
