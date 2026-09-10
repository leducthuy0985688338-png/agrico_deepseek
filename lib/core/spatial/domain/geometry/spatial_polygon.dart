import 'dart:collection';

import 'spatial_coordinate.dart';
import 'spatial_geometry_type.dart';

/// Polygon geometry in canonical WGS84 coordinates.
///
/// Foundation v1 supports one outer ring without interior holes. The ring is
/// automatically closed when necessary and is exposed as immutable data.
class SpatialPolygon {
  SpatialPolygon._(List<SpatialCoordinate> outerRing)
    : outerRing = UnmodifiableListView(outerRing);

  factory SpatialPolygon.fromOuterRing(Iterable<SpatialCoordinate> input) {
    final source = List<SpatialCoordinate>.of(input);

    for (final coordinate in source) {
      coordinate.validate();
    }

    final distinctVertices = source.toSet();

    if (distinctVertices.length < 3) {
      throw const FormatException(
        'Spatial Polygon must contain at least three distinct vertices.',
      );
    }

    final ring = List<SpatialCoordinate>.of(source);

    if (ring.first != ring.last) {
      ring.add(ring.first);
    }

    if (_hasZeroPlanarArea(ring)) {
      throw const FormatException(
        'Spatial Polygon outer ring must enclose a non-zero area.',
      );
    }

    if (_hasSelfIntersection(ring)) {
      throw const FormatException(
        'Spatial Polygon outer ring must not self-intersect.',
      );
    }

    return SpatialPolygon._(ring);
  }

  final UnmodifiableListView<SpatialCoordinate> outerRing;

  SpatialGeometryType get geometryType => SpatialGeometryType.polygon;

  void validate() {
    if (outerRing.length < 4 || outerRing.first != outerRing.last) {
      throw const FormatException(
        'Spatial Polygon outer ring must be closed with at least three vertices.',
      );
    }

    for (final coordinate in outerRing) {
      coordinate.validate();
    }

    final distinctVertices = outerRing.take(outerRing.length - 1).toSet();

    if (distinctVertices.length < 3) {
      throw const FormatException(
        'Spatial Polygon must contain at least three distinct vertices.',
      );
    }

    if (_hasZeroPlanarArea(outerRing)) {
      throw const FormatException(
        'Spatial Polygon outer ring must enclose a non-zero area.',
      );
    }

    if (_hasSelfIntersection(outerRing)) {
      throw const FormatException(
        'Spatial Polygon outer ring must not self-intersect.',
      );
    }
  }

  static bool _hasZeroPlanarArea(List<SpatialCoordinate> ring) {
    var twiceArea = 0.0;

    for (var index = 0; index < ring.length - 1; index++) {
      final current = ring[index];
      final next = ring[index + 1];

      twiceArea +=
          current.longitude * next.latitude - next.longitude * current.latitude;
    }

    return twiceArea.abs() <= 1e-12;
  }

  static bool _hasSelfIntersection(List<SpatialCoordinate> ring) {
    final segmentCount = ring.length - 1;

    for (var firstIndex = 0; firstIndex < segmentCount; firstIndex++) {
      final firstStart = ring[firstIndex];
      final firstEnd = ring[firstIndex + 1];

      for (
        var secondIndex = firstIndex + 1;
        secondIndex < segmentCount;
        secondIndex++
      ) {
        if (_segmentsAreAdjacent(firstIndex, secondIndex, segmentCount)) {
          continue;
        }

        final secondStart = ring[secondIndex];
        final secondEnd = ring[secondIndex + 1];

        if (_segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd)) {
          return true;
        }
      }
    }

    return false;
  }

  static bool _segmentsAreAdjacent(
    int firstIndex,
    int secondIndex,
    int segmentCount,
  ) {
    if ((firstIndex - secondIndex).abs() == 1) {
      return true;
    }

    return firstIndex == 0 && secondIndex == segmentCount - 1;
  }

  static bool _segmentsIntersect(
    SpatialCoordinate a,
    SpatialCoordinate b,
    SpatialCoordinate c,
    SpatialCoordinate d,
  ) {
    final o1 = _orientation(a, b, c);
    final o2 = _orientation(a, b, d);
    final o3 = _orientation(c, d, a);
    final o4 = _orientation(c, d, b);

    if (_differentSigns(o1, o2) && _differentSigns(o3, o4)) {
      return true;
    }

    if (o1 == 0 && _onSegment(a, c, b)) {
      return true;
    }
    if (o2 == 0 && _onSegment(a, d, b)) {
      return true;
    }
    if (o3 == 0 && _onSegment(c, a, d)) {
      return true;
    }
    if (o4 == 0 && _onSegment(c, b, d)) {
      return true;
    }

    return false;
  }

  static bool _differentSigns(double first, double second) =>
      (first > 0 && second < 0) || (first < 0 && second > 0);

  static double _orientation(
    SpatialCoordinate a,
    SpatialCoordinate b,
    SpatialCoordinate c,
  ) =>
      (b.longitude - a.longitude) * (c.latitude - a.latitude) -
      (b.latitude - a.latitude) * (c.longitude - a.longitude);

  static bool _onSegment(
    SpatialCoordinate a,
    SpatialCoordinate point,
    SpatialCoordinate b,
  ) =>
      point.longitude >= _min(a.longitude, b.longitude) &&
      point.longitude <= _max(a.longitude, b.longitude) &&
      point.latitude >= _min(a.latitude, b.latitude) &&
      point.latitude <= _max(a.latitude, b.latitude);

  static double _min(double first, double second) =>
      first < second ? first : second;

  static double _max(double first, double second) =>
      first > second ? first : second;
}
