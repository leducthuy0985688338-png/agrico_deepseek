import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpatialPoint', () {
    test('owns one valid WGS84 coordinate', () {
      const point = SpatialPoint(
        coordinate: SpatialCoordinate(
          latitude: 16.5,
          longitude: 104.7,
          altitudeM: 120,
        ),
      );

      point.validate();

      expect(point.geometryType, SpatialGeometryType.point);
      expect(point.coordinate.latitude, 16.5);
      expect(point.coordinate.longitude, 104.7);
    });

    test('rejects an invalid coordinate', () {
      const point = SpatialPoint(
        coordinate: SpatialCoordinate(latitude: 91, longitude: 104.7),
      );

      expect(point.validate, throwsFormatException);
    });
  });

  group('SpatialLineString', () {
    test('stores at least two coordinates as immutable geometry', () {
      final source = <SpatialCoordinate>[
        const SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        const SpatialCoordinate(latitude: 16.6, longitude: 104.8),
      ];

      final line = SpatialLineString.fromCoordinates(source);

      source.add(const SpatialCoordinate(latitude: 16.7, longitude: 104.9));

      line.validate();

      expect(line.geometryType, SpatialGeometryType.lineString);
      expect(line.coordinates, hasLength(2));
      expect(
        () => line.coordinates.add(
          const SpatialCoordinate(latitude: 16.8, longitude: 105),
        ),
        throwsUnsupportedError,
      );
    });

    test('rejects fewer than two coordinates', () {
      expect(
        () => SpatialLineString.fromCoordinates(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        ]),
        throwsFormatException,
      );
    });

    test('rejects invalid member coordinates', () {
      expect(
        () => SpatialLineString.fromCoordinates(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.6, longitude: 181),
        ]),
        throwsFormatException,
      );
    });
  });
}
