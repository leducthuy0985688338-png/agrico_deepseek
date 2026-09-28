import 'dart:collection';

import 'spatial_coordinate.dart';
import 'spatial_geometry.dart';
import 'spatial_geometry_type.dart';

/// Polygon geometry in canonical WGS84 coordinates.
///
/// The outer ring and optional interior rings are closed and immutable.
class SpatialPolygon implements SpatialGeometry {
  SpatialPolygon._(List<SpatialCoordinate> outerRing,
      List<List<SpatialCoordinate>> innerRings)
    : outerRing = UnmodifiableListView(outerRing),
      innerRings = UnmodifiableListView(innerRings.map(
        (ring) => UnmodifiableListView<SpatialCoordinate>(ring)).toList());

  factory SpatialPolygon.fromOuterRing(Iterable<SpatialCoordinate> input, {
    Iterable<Iterable<SpatialCoordinate>> innerRings = const [],
  }) {
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

    final holes = <List<SpatialCoordinate>>[];
    for (final rawHole in innerRings) {
      final hole = SpatialPolygon.fromOuterRing(rawHole).outerRing.toList();
      if (hole.take(hole.length - 1).any((point) =>
          !_strictlyInside(ring, point)) || _ringsMeet(ring, hole)) {
        throw const FormatException('Spatial Polygon hole must be inside the exterior ring.');
      }
      for (final other in holes) {
        if (_ringsMeet(other, hole) ||
            _strictlyInside(other, hole.first) ||
            _strictlyInside(hole, other.first)) {
          throw const FormatException('Spatial Polygon holes cannot overlap.');
        }
      }
      holes.add(hole);
    }
    return SpatialPolygon._(ring, holes);
  }

  final UnmodifiableListView<SpatialCoordinate> outerRing;
  final UnmodifiableListView<UnmodifiableListView<SpatialCoordinate>> innerRings;

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
    SpatialPolygon.fromOuterRing(outerRing, innerRings: innerRings);
  }

  static bool _strictlyInside(List<SpatialCoordinate> ring,
      SpatialCoordinate point) {
    var inside = false;
    for (var i = 0; i < ring.length - 1; i++) {
      final a = ring[i];
      final b = ring[i + 1];
      if (_orientation(a, b, point).abs() < 1e-12 &&
          _onSegment(a, point, b)) return false;
      if ((a.latitude > point.latitude) != (b.latitude > point.latitude) &&
          point.longitude < (b.longitude - a.longitude) *
              (point.latitude - a.latitude) / (b.latitude - a.latitude) +
              a.longitude) inside = !inside;
    }
    return inside;
  }

  static bool _ringsMeet(List<SpatialCoordinate> first,
      List<SpatialCoordinate> second) {
    for (var i = 0; i < first.length - 1; i++) {
      for (var j = 0; j < second.length - 1; j++) {
        if (_segmentsIntersect(first[i], first[i + 1],
            second[j], second[j + 1])) return true;
      }
    }
    return false;
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
