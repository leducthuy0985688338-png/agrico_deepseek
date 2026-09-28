import 'package:agrico_deepseek/features/farm/domain/geometry/parcel_subdivision_plan.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = Wgs84Polygon.fromVertices(const [
    Wgs84Vertex(latitude: 16, longitude: 106),
    Wgs84Vertex(latitude: 16, longitude: 106.002),
    Wgs84Vertex(latitude: 16.001, longitude: 106.002),
    Wgs84Vertex(latitude: 16.001, longitude: 106),
  ]);
  final cuts = [
    const ParcelSubdivisionCut(fragmentIndex: 0, path: [
      Wgs84Vertex(latitude: 16, longitude: 106.001),
      Wgs84Vertex(latitude: 16.001, longitude: 106.001),
    ]),
    const ParcelSubdivisionCut(fragmentIndex: 0, path: [
      Wgs84Vertex(latitude: 16.0005, longitude: 106.001),
      Wgs84Vertex(latitude: 16.0005, longitude: 106.002),
    ]),
  ];

  test('two cuts on selected fragments make three final polygons', () {
    final fragments = const ParcelSubdivisionPlan().apply(source, cuts);
    expect(fragments, hasLength(3));
    final measure = const Wgs84GeometryService();
    expect(fragments.map((f) => measure.measure(f).areaM2).reduce((a,b) => a+b),
      closeTo(measure.measure(source).areaM2, 0.01));
  });

  test('rejects a cut targeting a missing fragment', () {
    expect(() => const ParcelSubdivisionPlan().apply(source, [
      ParcelSubdivisionCut(fragmentIndex: 1, path: cuts.first.path),
    ]), throwsFormatException);
  });
}
