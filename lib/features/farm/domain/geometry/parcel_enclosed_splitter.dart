import 'dart:math' as math;

import 'parcel_ring_union.dart';
import 'wgs84_geometry.dart';

/// Extracts an entirely enclosed parcel while keeping its footprint as an
/// interior ring of the remainder. No area is silently lost or overlapped.
class ParcelEnclosedSplitter {
  const ParcelEnclosedSplitter();

  List<Wgs84Polygon> split(Wgs84Polygon parent, Wgs84Polygon enclosed) {
    if (enclosed.holes.isNotEmpty) {
      throw const FormatException('The enclosed parcel cannot have holes.');
    }
    // First check the outer boundary independently. A new region may share an
    // existing child's edge, but may not spill beyond the original parcel.
    Wgs84Polygon.fromVertices(parent.vertices, holes: [enclosed.vertices]);
    final holes = parent.holes.map((ring) => ring.toList()).toList();
    var added = enclosed.vertices.toList();
    var index = 0;
    while (index < holes.length) {
      final combined = const ParcelRingUnion().merge(holes[index], added);
      if (combined == null) {
        index++;
      } else {
        added = combined;
        holes.removeAt(index);
        index = 0;
      }
    }
    final remainder = Wgs84Polygon.fromVertices(parent.vertices,
      holes: [...holes, added]);
    final geometry = const Wgs84GeometryService();
    final parentArea = geometry.measure(parent).areaM2;
    final enclosedArea = geometry.measure(enclosed).areaM2;
    final remainderArea = geometry.measure(remainder).areaM2;
    if (remainderArea <= 0 || enclosedArea <= 0 ||
        (remainderArea + enclosedArea - parentArea).abs() >
            math.max(0.01, parentArea * 1e-5)) {
      throw const FormatException('Enclosed polygon does not partition the parent.');
    }
    return [remainder, enclosed];
  }
}
