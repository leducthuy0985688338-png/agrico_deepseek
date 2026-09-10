import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpatialCoordinate', () {
    test('stores canonical WGS84 latitude longitude and optional altitude', () {
      const coordinate = SpatialCoordinate(
        latitude: 16.556,
        longitude: 104.751,
        altitudeM: 145.5,
      );

      coordinate.validate();

      expect(coordinate.latitude, 16.556);
      expect(coordinate.longitude, 104.751);
      expect(coordinate.altitudeM, 145.5);
    });

    test('accepts valid WGS84 boundary values', () {
      const coordinates = [
        SpatialCoordinate(latitude: -90, longitude: -180),
        SpatialCoordinate(latitude: 90, longitude: 180),
      ];

      for (final coordinate in coordinates) {
        coordinate.validate();
      }
    });

    test('rejects latitude outside WGS84 range', () {
      const coordinate = SpatialCoordinate(latitude: 90.0001, longitude: 104.7);

      expect(coordinate.validate, throwsFormatException);
    });

    test('rejects longitude outside WGS84 range', () {
      const coordinate = SpatialCoordinate(latitude: 16.5, longitude: 180.0001);

      expect(coordinate.validate, throwsFormatException);
    });

    test('rejects non-finite coordinate values', () {
      const coordinate = SpatialCoordinate(
        latitude: double.nan,
        longitude: 104.7,
      );

      expect(coordinate.validate, throwsFormatException);
    });

    test('uses latitude longitude in domain while exposing KML order', () {
      const coordinate = SpatialCoordinate(
        latitude: 16.5,
        longitude: 104.7,
        altitudeM: 120,
      );

      expect(coordinate.kmlLongitude, 104.7);
      expect(coordinate.kmlLatitude, 16.5);
      expect(coordinate.kmlAltitudeM, 120);
    });
  });
}
