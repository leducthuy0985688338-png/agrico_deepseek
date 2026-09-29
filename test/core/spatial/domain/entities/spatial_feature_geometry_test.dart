import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);

  SpatialFeature buildFeature({
    required SpatialGeometryType geometryType,
    dynamic geometry,
  }) {
    return SpatialFeature(
      id: 'feature-1',
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

  group('SpatialFeature geometry', () {
    test('accepts a point geometry matching geometryType', () {
      final feature = buildFeature(
        geometryType: SpatialGeometryType.point,
        geometry: const SpatialPoint(
          coordinate: SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        ),
      );

      expect(feature.geometry, isA<SpatialPoint>());
      expect(feature.validate, returnsNormally);
    });

    test('accepts a line geometry matching geometryType', () {
      final feature = buildFeature(
        geometryType: SpatialGeometryType.lineString,
        geometry: SpatialLineString.fromCoordinates(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.6, longitude: 104.8),
        ]),
      );

      expect(feature.geometry, isA<SpatialLineString>());
      expect(feature.validate, returnsNormally);
    });

    test('accepts a polygon geometry matching geometryType', () {
      final feature = buildFeature(
        geometryType: SpatialGeometryType.polygon,
        geometry: SpatialPolygon.fromOuterRing(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.5, longitude: 104.8),
          SpatialCoordinate(latitude: 16.6, longitude: 104.8),
          SpatialCoordinate(latitude: 16.6, longitude: 104.7),
        ]),
      );

      expect(feature.geometry, isA<SpatialPolygon>());
      expect(feature.validate, returnsNormally);
    });

    test('rejects geometry whose type does not match geometryType', () {
      final feature = buildFeature(
        geometryType: SpatialGeometryType.lineString,
        geometry: const SpatialPoint(
          coordinate: SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        ),
      );

      expect(feature.validate, throwsFormatException);
    });

    test('rejects invalid concrete geometry', () {
      final feature = buildFeature(
        geometryType: SpatialGeometryType.point,
        geometry: const SpatialPoint(
          coordinate: SpatialCoordinate(latitude: 91, longitude: 104.7),
        ),
      );

      expect(feature.validate, throwsFormatException);
    });

    test('keeps legacy metadata-only feature compatible', () {
      final feature = buildFeature(geometryType: SpatialGeometryType.polygon);

      expect(feature.geometry, isNull);
      expect(feature.validate, returnsNormally);
    });
  });
}
