import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpatialPolygon', () {
    test('closes an open valid outer ring automatically', () {
      final polygon = SpatialPolygon.fromOuterRing(const [
        SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        SpatialCoordinate(latitude: 16.5, longitude: 104.701),
        SpatialCoordinate(latitude: 16.501, longitude: 104.701),
        SpatialCoordinate(latitude: 16.501, longitude: 104.7),
      ]);

      polygon.validate();

      expect(polygon.geometryType, SpatialGeometryType.polygon);
      expect(polygon.outerRing, hasLength(5));
      expect(polygon.outerRing.first, polygon.outerRing.last);
    });

    test('does not duplicate an already closed ring', () {
      const first = SpatialCoordinate(latitude: 16.5, longitude: 104.7);

      final polygon = SpatialPolygon.fromOuterRing(const [
        first,
        SpatialCoordinate(latitude: 16.5, longitude: 104.701),
        SpatialCoordinate(latitude: 16.501, longitude: 104.701),
        SpatialCoordinate(latitude: 16.501, longitude: 104.7),
        first,
      ]);

      expect(polygon.outerRing, hasLength(5));
    });

    test('defensively copies and exposes immutable coordinates', () {
      final source = <SpatialCoordinate>[
        const SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        const SpatialCoordinate(latitude: 16.5, longitude: 104.701),
        const SpatialCoordinate(latitude: 16.501, longitude: 104.701),
        const SpatialCoordinate(latitude: 16.501, longitude: 104.7),
      ];

      final polygon = SpatialPolygon.fromOuterRing(source);

      source.add(const SpatialCoordinate(latitude: 16.502, longitude: 104.702));

      expect(polygon.outerRing, hasLength(5));
      expect(
        () => polygon.outerRing.add(
          const SpatialCoordinate(latitude: 16.6, longitude: 104.8),
        ),
        throwsUnsupportedError,
      );
    });

    test('rejects fewer than three distinct vertices', () {
      expect(
        () => SpatialPolygon.fromOuterRing(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.5, longitude: 104.701),
        ]),
        throwsFormatException,
      );
    });

    test('rejects invalid member coordinates', () {
      expect(
        () => SpatialPolygon.fromOuterRing(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.5, longitude: 104.701),
          SpatialCoordinate(latitude: 16.501, longitude: 181),
        ]),
        throwsFormatException,
      );
    });

    test('rejects a degenerate collinear outer ring', () {
      expect(
        () => SpatialPolygon.fromOuterRing(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.501, longitude: 104.701),
          SpatialCoordinate(latitude: 16.502, longitude: 104.702),
        ]),
        throwsFormatException,
      );
    });
    test('rejects self-intersecting outer ring', () {
      expect(
        () => SpatialPolygon.fromOuterRing(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.501, longitude: 104.701),
          SpatialCoordinate(latitude: 16.501, longitude: 104.7),
          SpatialCoordinate(latitude: 16.5, longitude: 104.701),
        ]),
        throwsFormatException,
      );
    });
  });
}
