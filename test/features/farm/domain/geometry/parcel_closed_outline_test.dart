import 'package:agrico_deepseek/features/farm/domain/geometry/parcel_boundary_splitter.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/parcel_closed_outline.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Wgs84Vertex p(double lat, double lon) =>
      Wgs84Vertex(latitude: lat, longitude: lon);
  final source = Wgs84Polygon.fromVertices([
    p(16, 106), p(16, 106.002),
    p(16.002, 106.002), p(16.002, 106),
  ]);
  const outline = ParcelClosedOutline();

  test('border-tracing then curved interior produces two closed parcels', () {
    final left = p(16.0017, 106);
    final right = p(16.0015, 106.002);
    final traced = [
      left, p(16.002, 106), p(16.002, 106.001),
      p(16.002, 106.002), right,
      p(16.00135, 106.0016), p(16.0013, 106.001),
      p(16.0014, 106.0003),
    ];
    final cut = outline.interiorCut(source, traced);
    expect(cut.first, right);
    expect(cut.last, left);
    expect(cut, hasLength(5));
    final children = const ParcelBoundarySplitter().splitAlongPath(source, cut);
    expect(children, hasLength(2));
    expect(children.every((child) => child.isClosed), isTrue);
    final geometry = const Wgs84GeometryService();
    expect(children.map((child) => geometry.measure(child).areaM2)
      .reduce((a, b) => a + b),
      closeTo(geometry.measure(source).areaM2, 0.01));
  });

  test('second boundary tap completes the screenshot trace without returning to start', () {
    final trace = [
      p(16.002, 106), p(16.002, 106.001), p(16.002, 106.002),
      p(16.0015, 106.002), p(16.00135, 106.0016),
      p(16.0013, 106.001), p(16.0014, 106.0003),
      p(16.0017, 106),
    ];
    final cut = outline.interiorCut(source, trace);
    expect(cut.first, trace[3]);
    expect(cut.last, trace.last);
    final pieces = const ParcelBoundarySplitter().splitAlongPath(source, cut);
    expect(pieces, hasLength(2));
    final drawnShape = Wgs84Polygon.fromVertices(trace);
    final geometry = const Wgs84GeometryService();
    final drawnArea = geometry.measure(drawnShape).areaM2;
    expect(pieces.map((piece) => geometry.measure(piece).areaM2)
      .any((area) => (area - drawnArea).abs() < 0.01), isTrue);
  });

  test('interior first and boundary last closes at the original start', () {
    final left = p(16.0017, 106);
    final right = p(16.0015, 106.002);
    expect(outline.interiorCut(source, [
      left, p(16.0013, 106.0005), p(16.0013, 106.0015), right,
    ]), [left, p(16.0013, 106.0005), p(16.0013, 106.0015), right]);
  });

  test('one boundary anchor cannot partition a simple polygon', () {
    expect(() => outline.interiorCut(source, [
      p(16.0017, 106), p(16.0013, 106.0005), p(16.0013, 106.0015),
    ]), throwsFormatException);
  });
}
