import 'package:agrico_deepseek/features/farm/domain/geometry/parcel_enclosed_splitter.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Wgs84Vertex p(double lat, double lon) =>
    Wgs84Vertex(latitude: lat, longitude: lon);
  final parent = Wgs84Polygon.fromVertices([
    p(16, 106), p(16, 106.004), p(16.004, 106.004), p(16.004, 106),
  ]);
  Wgs84Polygon inner(double low, double high) => Wgs84Polygon.fromVertices([
    p(low, 106 + low - 16), p(low, 106 + high - 16),
    p(high, 106 + high - 16), p(high, 106 + low - 16),
  ]);

  test('closed interior parcel leaves one remainder with a genuine hole', () {
    final children = const ParcelEnclosedSplitter()
      .split(parent, inner(16.001, 16.002));
    expect(children, hasLength(2));
    expect(children.first.holes, hasLength(1));
    expect(children.first.holes.single, children.last.vertices);
    final geometry = const Wgs84GeometryService();
    expect(geometry.measure(children.first).areaM2 +
      geometry.measure(children.last).areaM2,
      closeTo(geometry.measure(parent).areaM2, 0.01));
    expect(children.every((polygon) => polygon.isClosed), isTrue);
  });

  test('additional enclosed parcel creates a second non-overlapping hole', () {
    final first = const ParcelEnclosedSplitter()
      .split(parent, inner(16.001, 16.0015));
    final next = const ParcelEnclosedSplitter()
      .split(first.first, inner(16.002, 16.0025));
    expect(next.first.holes, hasLength(2));
  });

  test('outside, touching and overlapping closed shapes are rejected', () {
    expect(() => const ParcelEnclosedSplitter()
      .split(parent, inner(16.003, 16.005)), throwsFormatException);
    expect(() => const ParcelEnclosedSplitter()
      .split(parent, inner(16, 16.001)), throwsFormatException);
    final remainder = const ParcelEnclosedSplitter()
      .split(parent, inner(16.001, 16.002)).first;
    expect(() => const ParcelEnclosedSplitter()
      .split(remainder, inner(16.0015, 16.0025)), throwsFormatException);
  });
}
