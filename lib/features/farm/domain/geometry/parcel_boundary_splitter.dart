import 'dart:math' as math;

import 'wgs84_geometry.dart';

/// Splits a simple parcel along a polyline connecting two boundary points.
/// Each segment must remain inside the polygon, including concave parcels.
class ParcelBoundarySplitter {
  const ParcelBoundarySplitter();

  static const _coordinateTolerance = 1e-9;

  List<Wgs84Polygon> split(
    Wgs84Polygon parent,
    Wgs84Vertex start,
    Wgs84Vertex end,
  ) => splitAlongPath(parent, [start, end]);

  List<Wgs84Polygon> splitAlongPath(
    Wgs84Polygon parent,
    List<Wgs84Vertex> path,
  ) {
    if (path.length < 2 || path.any((point) => !point.isValid)) {
      throw const FormatException('A cut needs valid WGS84 points.');
    }
    final start = path.first;
    final end = path.last;
    if (!start.isValid || !end.isValid || _distance2(start, end) < 1e-18) {
      throw const FormatException('A cut requires two distinct WGS84 points.');
    }
    final ring = parent.vertices.sublist(0, parent.vertices.length - 1);
    final first = _boundaryPosition(ring, start);
    final last = _boundaryPosition(ring, end);
    if (first == null || last == null) {
      throw const FormatException('Both cut endpoints must lie on the parcel boundary.');
    }
    final ordered = <(_BoundaryPosition, Wgs84Vertex)>[
      (first, start), (last, end),
    ]..sort((a, b) => a.$1.position.compareTo(b.$1.position));
    if ((ordered.last.$1.position - ordered.first.$1.position).abs() <
        _coordinateTolerance) {
      throw const FormatException('Cut endpoints coincide on the boundary.');
    }

    for (var i = 1; i < path.length - 1; i++) {
      if (!_inside(ring, path[i])) {
        throw const FormatException('Cut bends must be inside the parcel.');
      }
    }
    for (var segment = 0; segment < path.length - 1; segment++) {
      final a = path[segment];
      final b = path[segment + 1];
      if (_distance2(a, b) < 1e-18 || !_inside(ring,
          Wgs84Vertex(latitude: (a.latitude + b.latitude) / 2,
            longitude: (a.longitude + b.longitude) / 2))) {
        throw const FormatException('Each cut segment must stay inside.');
      }
      for (var i = 0; i < ring.length; i++) {
        final edgeA = ring[i];
        final edgeB = ring[(i + 1) % ring.length];
        if (_properIntersection(a, b, edgeA, edgeB)) {
          throw const FormatException('The cut crosses the parcel boundary.');
        }
        for (final vertex in [edgeA, edgeB]) {
          if (_onSegment(a, vertex, b) &&
              _distance2(vertex, a) > 1e-18 &&
              _distance2(vertex, b) > 1e-18) {
            throw const FormatException('The cut touches another boundary vertex.');
          }
        }
      }
      for (var other = 0; other < segment - 1; other++) {
        if (_segmentsMeet(a, b, path[other], path[other + 1])) {
          throw const FormatException('The cut intersects itself.');
        }
      }
    }

    final augmented = <Wgs84Vertex>[];
    for (var i = 0; i < ring.length; i++) {
      augmented.add(ring[i]);
      for (final (position, point) in ordered) {
        if (position.edge == i && position.fraction > _coordinateTolerance &&
            position.fraction < 1 - _coordinateTolerance) {
          augmented.add(point);
        }
      }
    }
    final aIndex = _indexOf(augmented, start);
    final bIndex = _indexOf(augmented, end);
    final firstPart = [
      ..._walk(augmented, aIndex, bIndex),
      ...path.sublist(1, path.length - 1).reversed,
    ];
    final secondPart = [
      ..._walk(augmented, bIndex, aIndex),
      ...path.sublist(1, path.length - 1),
    ];
    final children = [
      Wgs84Polygon.fromVertices(firstPart),
      Wgs84Polygon.fromVertices(secondPart),
    ];
    final geometry = const Wgs84GeometryService();
    final parentArea = geometry.measure(parent).areaM2;
    final childAreas = children.map((polygon) => geometry.measure(polygon).areaM2)
        .toList();
    if (childAreas.any((area) => !area.isFinite || area <= 0) ||
        (childAreas[0] + childAreas[1] - parentArea).abs() >
            math.max(0.01, parentArea * 1e-5)) {
      throw const FormatException('Child polygons do not cover the source parcel.');
    }
    return children;
  }

  _BoundaryPosition? _boundaryPosition(List<Wgs84Vertex> ring,
      Wgs84Vertex point) {
    for (var i = 0; i < ring.length; i++) {
      final a = ring[i];
      final b = ring[(i + 1) % ring.length];
      final dx = b.longitude - a.longitude;
      final dy = b.latitude - a.latitude;
      final length2 = dx * dx + dy * dy;
      if (length2 <= 0) continue;
      final t = ((point.longitude - a.longitude) * dx +
          (point.latitude - a.latitude) * dy) / length2;
      if (t < -_coordinateTolerance || t > 1 + _coordinateTolerance) continue;
      final projected = Wgs84Vertex(
        latitude: a.latitude + dy * t,
        longitude: a.longitude + dx * t,
      );
      if (_distance2(point, projected) <= 1e-18) {
        return _BoundaryPosition(i, t.clamp(0.0, 1.0).toDouble());
      }
    }
    return null;
  }

  int _indexOf(List<Wgs84Vertex> ring, Wgs84Vertex point) {
    final index = ring.indexWhere((item) => _distance2(item, point) <= 1e-18);
    if (index < 0) throw const FormatException('Cut endpoint is missing.');
    return index;
  }

  List<Wgs84Vertex> _walk(List<Wgs84Vertex> ring, int from, int to) {
    final result = <Wgs84Vertex>[ring[from]];
    var index = from;
    while (index != to) {
      index = (index + 1) % ring.length;
      result.add(ring[index]);
    }
    return result;
  }

  bool _inside(List<Wgs84Vertex> ring, Wgs84Vertex point) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i];
      final b = ring[j];
      if (_onSegment(a, point, b)) return false;
      if ((a.latitude > point.latitude) != (b.latitude > point.latitude) &&
          point.longitude < (b.longitude - a.longitude) *
              (point.latitude - a.latitude) / (b.latitude - a.latitude) +
              a.longitude) {
        inside = !inside;
      }
    }
    return inside;
  }

  bool _properIntersection(Wgs84Vertex a, Wgs84Vertex b,
      Wgs84Vertex c, Wgs84Vertex d) {
    final x = _orientation(a, b, c);
    final y = _orientation(a, b, d);
    final z = _orientation(c, d, a);
    final w = _orientation(c, d, b);
    return x * y < -1e-24 && z * w < -1e-24;
  }

  bool _segmentsMeet(Wgs84Vertex a, Wgs84Vertex b,
      Wgs84Vertex c, Wgs84Vertex d) =>
      _properIntersection(a, b, c, d) ||
      _onSegment(a, c, b) || _onSegment(a, d, b) ||
      _onSegment(c, a, d) || _onSegment(c, b, d);

  double _orientation(Wgs84Vertex a, Wgs84Vertex b, Wgs84Vertex c) =>
      (b.longitude - a.longitude) * (c.latitude - a.latitude) -
      (b.latitude - a.latitude) * (c.longitude - a.longitude);

  bool _onSegment(Wgs84Vertex a, Wgs84Vertex p, Wgs84Vertex b) =>
      _orientation(a, b, p).abs() <= 1e-12 &&
      p.longitude >= math.min(a.longitude, b.longitude) - _coordinateTolerance &&
      p.longitude <= math.max(a.longitude, b.longitude) + _coordinateTolerance &&
      p.latitude >= math.min(a.latitude, b.latitude) - _coordinateTolerance &&
      p.latitude <= math.max(a.latitude, b.latitude) + _coordinateTolerance;

  double _distance2(Wgs84Vertex a, Wgs84Vertex b) =>
      math.pow(a.longitude - b.longitude, 2).toDouble() +
      math.pow(a.latitude - b.latitude, 2).toDouble();
}

class _BoundaryPosition {
  const _BoundaryPosition(this.edge, this.fraction);
  final int edge;
  final double fraction;
  double get position => edge + fraction;
}
