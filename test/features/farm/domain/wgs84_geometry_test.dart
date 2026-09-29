import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const geometry = Wgs84GeometryService();

  test('normalizes an open ring to a closed EPSG:4326 polygon', () {
    final polygon = Wgs84Polygon.fromVertices(const [
      Wgs84Vertex(latitude: 16.5, longitude: 104.7),
      Wgs84Vertex(latitude: 16.5, longitude: 104.701),
      Wgs84Vertex(latitude: 16.501, longitude: 104.701),
      Wgs84Vertex(latitude: 16.501, longitude: 104.7),
    ]);

    expect(polygon.crs, 'EPSG:4326');
    expect(polygon.vertices, hasLength(5));
    expect(polygon.vertices.first, polygon.vertices.last);
    expect(polygon.distinctVertexCount, 4);
  });

  test('rejects fewer than three distinct vertices', () {
    expect(
      () => Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.5, longitude: 104.7),
        Wgs84Vertex(latitude: 16.5, longitude: 104.701),
      ]),
      throwsA(
        isA<PolygonValidationException>().having(
          (error) => error.issue,
          'issue',
          PolygonValidationIssue.tooFewDistinctVertices,
        ),
      ),
    );
  });

  test('rejects latitude and longitude outside WGS84 bounds', () {
    expect(
      () => Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 91, longitude: 104.7),
        Wgs84Vertex(latitude: 16.5, longitude: 181),
        Wgs84Vertex(latitude: 16.6, longitude: 104.8),
      ]),
      throwsA(
        isA<PolygonValidationException>().having(
          (error) => error.issue,
          'issue',
          PolygonValidationIssue.invalidCoordinate,
        ),
      ),
    );
  });

  test('detects a self-intersecting bow-tie polygon', () {
    expect(
      () => Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.5, longitude: 104.7),
        Wgs84Vertex(latitude: 16.501, longitude: 104.701),
        Wgs84Vertex(latitude: 16.501, longitude: 104.7),
        Wgs84Vertex(latitude: 16.5, longitude: 104.701),
      ]),
      throwsA(
        isA<PolygonValidationException>().having(
          (error) => error.issue,
          'issue',
          PolygonValidationIssue.selfIntersection,
        ),
      ),
    );
  });

  test('derives real-world area, hectares, perimeter and centroid', () {
    final polygon = Wgs84Polygon.fromVertices(const [
      Wgs84Vertex(latitude: 16.5, longitude: 104.7),
      Wgs84Vertex(latitude: 16.5, longitude: 104.701),
      Wgs84Vertex(latitude: 16.501, longitude: 104.701),
      Wgs84Vertex(latitude: 16.501, longitude: 104.7),
    ]);

    final metrics = geometry.measure(polygon);

    expect(metrics.areaM2, closeTo(11850, 150));
    expect(metrics.areaHa, closeTo(1.185, 0.015));
    expect(metrics.perimeterM, closeTo(435.5, 4));
    expect(metrics.centroid.latitude, closeTo(16.5005, 0.00001));
    expect(metrics.centroid.longitude, closeTo(104.7005, 0.00001));
  });

  test('vertices and polygon rings are immutable', () {
    final source = <Wgs84Vertex>[
      const Wgs84Vertex(latitude: 0, longitude: 0),
      const Wgs84Vertex(latitude: 0, longitude: 0.001),
      const Wgs84Vertex(latitude: 0.001, longitude: 0),
    ];
    final polygon = Wgs84Polygon.fromVertices(source);
    source.clear();

    expect(polygon.vertices, hasLength(4));
    expect(
      () => polygon.vertices.add(const Wgs84Vertex(latitude: 1, longitude: 1)),
      throwsUnsupportedError,
    );
  });
}
