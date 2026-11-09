import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_multi_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpatialMultiPoint', () {
    test('stores immutable points', () {
      final source = <SpatialPoint>[
        const SpatialPoint(
          coordinate: SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        ),
        const SpatialPoint(
          coordinate: SpatialCoordinate(latitude: 16.6, longitude: 104.8),
        ),
      ];

      final geometry = SpatialMultiPoint.fromPoints(source);

      source.add(
        const SpatialPoint(
          coordinate: SpatialCoordinate(latitude: 16.7, longitude: 104.9),
        ),
      );

      geometry.validate();

      expect(geometry.geometryType, SpatialGeometryType.multiPoint);
      expect(geometry.points, hasLength(2));
      expect(
        () => geometry.points.add(
          const SpatialPoint(
            coordinate: SpatialCoordinate(latitude: 17, longitude: 105),
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('rejects an empty collection', () {
      expect(
        () => SpatialMultiPoint.fromPoints(const []),
        throwsFormatException,
      );
    });
  });

  group('SpatialMultiLineString', () {
    test('stores multiple immutable line strings', () {
      final first = SpatialLineString.fromCoordinates(const [
        SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        SpatialCoordinate(latitude: 16.6, longitude: 104.8),
      ]);

      final second = SpatialLineString.fromCoordinates(const [
        SpatialCoordinate(latitude: 16.7, longitude: 104.9),
        SpatialCoordinate(latitude: 16.8, longitude: 105),
      ]);

      final source = [first, second];
      final geometry = SpatialMultiLineString.fromLineStrings(source);

      source.clear();

      geometry.validate();

      expect(geometry.geometryType, SpatialGeometryType.multiLineString);
      expect(geometry.lineStrings, hasLength(2));
      expect(() => geometry.lineStrings.add(first), throwsUnsupportedError);
    });

    test('rejects an empty collection', () {
      expect(
        () => SpatialMultiLineString.fromLineStrings(const []),
        throwsFormatException,
      );
    });
  });

  group('SpatialMultiPolygon', () {
    test('stores disjoint polygons under one geometry identity', () {
      final first = SpatialPolygon.fromOuterRing(const [
        SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        SpatialCoordinate(latitude: 16.5, longitude: 104.701),
        SpatialCoordinate(latitude: 16.501, longitude: 104.701),
        SpatialCoordinate(latitude: 16.501, longitude: 104.7),
      ]);

      final second = SpatialPolygon.fromOuterRing(const [
        SpatialCoordinate(latitude: 17.0, longitude: 105.0),
        SpatialCoordinate(latitude: 17.0, longitude: 105.001),
        SpatialCoordinate(latitude: 17.001, longitude: 105.001),
        SpatialCoordinate(latitude: 17.001, longitude: 105.0),
      ]);

      final source = [first, second];
      final geometry = SpatialMultiPolygon.fromPolygons(source);

      source.clear();

      geometry.validate();

      expect(geometry.geometryType, SpatialGeometryType.multiPolygon);
      expect(geometry.polygons, hasLength(2));
      expect(() => geometry.polygons.add(first), throwsUnsupportedError);
    });

    test('rejects an empty collection', () {
      expect(
        () => SpatialMultiPolygon.fromPolygons(const []),
        throwsFormatException,
      );
    });
  });
}
