import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/wgs84_spatial_geometry_adapter.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Wgs84SpatialGeometryAdapter', () {
    const adapter = Wgs84SpatialGeometryAdapter();

    test('converts Wgs84Vertex to SpatialCoordinate without data loss', () {
      const vertex = Wgs84Vertex(
        latitude: 16.5523,
        longitude: 104.7512,
        altitudeM: 145.5,
      );

      final coordinate = adapter.toSpatialCoordinate(vertex);

      expect(coordinate.latitude, vertex.latitude);
      expect(coordinate.longitude, vertex.longitude);
      expect(coordinate.altitudeM, vertex.altitudeM);
    });

    test('converts SpatialCoordinate to Wgs84Vertex without data loss', () {
      const coordinate = SpatialCoordinate(
        latitude: 16.5523,
        longitude: 104.7512,
        altitudeM: 145.5,
      );

      final vertex = adapter.toWgs84Vertex(coordinate);

      expect(vertex.latitude, coordinate.latitude);
      expect(vertex.longitude, coordinate.longitude);
      expect(vertex.altitudeM, coordinate.altitudeM);
    });

    test('round-trips Wgs84Vertex exactly', () {
      const original = Wgs84Vertex(
        latitude: 16.5523,
        longitude: 104.7512,
        altitudeM: 145.5,
      );

      final restored = adapter.toWgs84Vertex(
        adapter.toSpatialCoordinate(original),
      );

      expect(restored, original);
    });

    test('converts Wgs84Polygon to SpatialPolygon preserving ring', () {
      final polygon = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.5000, longitude: 104.7000),
        Wgs84Vertex(latitude: 16.5000, longitude: 104.7010),
        Wgs84Vertex(latitude: 16.5010, longitude: 104.7010),
        Wgs84Vertex(latitude: 16.5010, longitude: 104.7000),
      ]);

      final spatial = adapter.toSpatialPolygon(polygon);

      expect(spatial, isA<SpatialPolygon>());
      expect(spatial.outerRing.length, polygon.vertices.length);

      for (var index = 0; index < polygon.vertices.length; index++) {
        expect(
          spatial.outerRing[index].latitude,
          polygon.vertices[index].latitude,
        );
        expect(
          spatial.outerRing[index].longitude,
          polygon.vertices[index].longitude,
        );
      }
    });

    test('round-trips Wgs84Polygon without coordinate loss', () {
      final original = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.5000, longitude: 104.7000, altitudeM: 100),
        Wgs84Vertex(latitude: 16.5000, longitude: 104.7010, altitudeM: 101),
        Wgs84Vertex(latitude: 16.5010, longitude: 104.7010, altitudeM: 102),
        Wgs84Vertex(latitude: 16.5010, longitude: 104.7000, altitudeM: 103),
      ]);

      final restored = adapter.toWgs84Polygon(
        adapter.toSpatialPolygon(original),
      );

      expect(restored, original);
    });
  });
}
