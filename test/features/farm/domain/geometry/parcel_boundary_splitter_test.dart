import 'package:agrico_deepseek/features/farm/domain/geometry/parcel_boundary_splitter.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const splitter = ParcelBoundarySplitter();
  const measure = Wgs84GeometryService();
  Wgs84Vertex p(double latitude, double longitude) =>
      Wgs84Vertex(latitude: latitude, longitude: longitude);

  test('cuts a parcel into two valid retained WGS84 boundaries', () {
    final source = Wgs84Polygon.fromVertices([
      p(16, 106), p(16, 106.002), p(16.001, 106.002), p(16.001, 106),
    ]);
    final children = splitter.split(
      source, p(16, 106.001), p(16.001, 106.001));
    expect(children, hasLength(2));
    expect(children.every((child) => child.isClosed), isTrue);
    expect(children.every((child) => measure.measure(child).areaM2 > 0), isTrue);
    expect(measure.measure(children[0]).areaM2 +
        measure.measure(children[1]).areaM2,
        closeTo(measure.measure(source).areaM2, 0.01));
    expect(source.vertices, hasLength(5));
  });

  test('rejects a chord outside a concave parcel', () {
    final source = Wgs84Polygon.fromVertices([
      p(16, 106), p(16, 106.003), p(16.001, 106.003),
      p(16.001, 106.001), p(16.003, 106.001), p(16.003, 106),
    ]);
    expect(() => splitter.split(source,
      p(16.002, 106.001), p(16.001, 106.002)),
      throwsFormatException);
  });

  test('accepts a bent cut inside a concave parcel', () {
    final source = Wgs84Polygon.fromVertices([
      p(16, 106), p(16, 106.003), p(16.001, 106.003),
      p(16.001, 106.001), p(16.003, 106.001), p(16.003, 106),
    ]);
    final children = splitter.splitAlongPath(source, [
      p(16.002, 106.001), p(16.0005, 106.0005), p(16.001, 106.002),
    ]);
    expect(children, hasLength(2));
    expect(measure.measure(children[0]).areaM2 +
        measure.measure(children[1]).areaM2,
        closeTo(measure.measure(source).areaM2, 0.01));
    expect(children.every((part) => part.distinctVertexCount > 3), isTrue);
  });

  test('rejects a self-crossing cut', () {
    final source = Wgs84Polygon.fromVertices([
      p(16, 106), p(16, 106.004), p(16.004, 106.004), p(16.004, 106),
    ]);
    expect(() => splitter.splitAlongPath(source, [
      p(16, 106.001), p(16.003, 106.003), p(16.001, 106.003),
      p(16.003, 106.001), p(16.004, 106.002),
    ]), throwsFormatException);
  });

  test('rejects endpoints outside the source boundary', () {
    final source = Wgs84Polygon.fromVertices([
      p(16, 106), p(16, 106.002), p(16.002, 106.002), p(16.002, 106),
    ]);
    expect(() => splitter.split(source,
      p(16.001, 106.001), p(16.001, 106.002)),
      throwsFormatException);
  });
}
