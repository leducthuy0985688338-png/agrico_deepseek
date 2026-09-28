import 'dart:math' as math;

import 'wgs84_geometry.dart';

/// Joins two simple rings that share a real edge. Point-only contacts and
/// overlapping interiors cannot be stored as one valid interior ring.
class ParcelRingUnion {
  const ParcelRingUnion();

  static const _epsilon = 1e-10;

  List<Wgs84Vertex>? merge(
      List<Wgs84Vertex> first, List<Wgs84Vertex> second) {
    final a = first.sublist(0, first.length - 1);
    final b = second.sublist(0, second.length - 1);
    for (final point in a) {
      if (_inside(b, point)) throw const FormatException('Adjacent parcel overlaps an existing parcel.');
    }
    for (final point in b) {
      if (_inside(a, point)) throw const FormatException('Adjacent parcel overlaps an existing parcel.');
    }
    for (var i = 0; i < a.length; i++) {
      for (var j = 0; j < b.length; j++) {
        if (_properIntersection(a[i], a[(i + 1) % a.length],
            b[j], b[(j + 1) % b.length])) {
          throw const FormatException('Adjacent parcel crosses an existing boundary.');
        }
      }
    }

    final nodes = <Wgs84Vertex>[];
    int node(Wgs84Vertex point) {
      final found = nodes.indexWhere((v) => _same(v, point));
      if (found >= 0) return found;
      nodes.add(point);
      return nodes.length - 1;
    }

    final edges = <(int, int)>[];
    var sharedLength = 0.0;
    void collect(List<Wgs84Vertex> ring, List<Wgs84Vertex> other) {
      for (var i = 0; i < ring.length; i++) {
        final start = ring[i];
        final end = ring[(i + 1) % ring.length];
        final points = <Wgs84Vertex>[start, end,
          ...other.where((point) => _onSegment(start, point, end))];
        points.sort((x, y) => _fraction(start, end, x)
            .compareTo(_fraction(start, end, y)));
        for (var j = 0; j < points.length - 1; j++) {
          final from = points[j];
          final to = points[j + 1];
          if (_same(from, to)) continue;
          final middle = Wgs84Vertex(
            latitude: (from.latitude + to.latitude) / 2,
            longitude: (from.longitude + to.longitude) / 2);
          if (_onRing(other, middle)) {
            sharedLength += _length(from, to);
            continue;
          }
          if (_inside(other, middle)) {
            throw const FormatException('Adjacent parcel overlaps an existing parcel.');
          }
          edges.add((node(from), node(to)));
        }
      }
    }

    collect(a, b);
    collect(b, a);
    if (sharedLength <= _epsilon) {
      if (a.any((point) => _onRing(b, point)) ||
          b.any((point) => _onRing(a, point))) {
        throw const FormatException('Two parcels touch only at a point.');
      }
      return null;
    }

    final neighbors = <int, List<int>>{};
    for (final (from, to) in edges) {
      neighbors.putIfAbsent(from, () => []).add(to);
      neighbors.putIfAbsent(to, () => []).add(from);
    }
    if (neighbors.isEmpty || neighbors.values.any((links) => links.length != 2)) {
      throw const FormatException('Shared edges do not form one closed boundary.');
    }
    final ring = <Wgs84Vertex>[];
    final initial = edges.first.$1;
    var previous = -1;
    var current = initial;
    do {
      ring.add(nodes[current]);
      final options = neighbors[current]!;
      final next = options.first == previous ? options.last : options.first;
      previous = current;
      current = next;
      if (ring.length > edges.length) {
        throw const FormatException('Shared boundaries contain several loops.');
      }
    } while (current != initial);
    if (ring.length != edges.length) {
      throw const FormatException('Shared boundaries contain several loops.');
    }
    return Wgs84Polygon.fromVertices(ring).vertices.toList();
  }

  bool _same(Wgs84Vertex a, Wgs84Vertex b) =>
    (a.longitude - b.longitude).abs() <= _epsilon &&
    (a.latitude - b.latitude).abs() <= _epsilon;

  double _length(Wgs84Vertex a, Wgs84Vertex b) => math.sqrt(
    math.pow(a.longitude - b.longitude, 2) +
    math.pow(a.latitude - b.latitude, 2));

  double _cross(Wgs84Vertex a, Wgs84Vertex b, Wgs84Vertex p) =>
    (b.longitude - a.longitude) * (p.latitude - a.latitude) -
    (b.latitude - a.latitude) * (p.longitude - a.longitude);

  bool _onSegment(Wgs84Vertex a, Wgs84Vertex p, Wgs84Vertex b) =>
    _cross(a, b, p).abs() <= 1e-12 &&
    p.longitude >= math.min(a.longitude, b.longitude) - _epsilon &&
    p.longitude <= math.max(a.longitude, b.longitude) + _epsilon &&
    p.latitude >= math.min(a.latitude, b.latitude) - _epsilon &&
    p.latitude <= math.max(a.latitude, b.latitude) + _epsilon;

  bool _onRing(List<Wgs84Vertex> ring, Wgs84Vertex point) {
    for (var i = 0; i < ring.length; i++) {
      if (_onSegment(ring[i], point, ring[(i + 1) % ring.length])) return true;
    }
    return false;
  }

  bool _inside(List<Wgs84Vertex> ring, Wgs84Vertex point) {
    if (_onRing(ring, point)) return false;
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i];
      final b = ring[j];
      if ((a.latitude > point.latitude) != (b.latitude > point.latitude) &&
          point.longitude < (b.longitude - a.longitude) *
              (point.latitude - a.latitude) / (b.latitude - a.latitude) +
              a.longitude) inside = !inside;
    }
    return inside;
  }

  bool _properIntersection(Wgs84Vertex a, Wgs84Vertex b,
      Wgs84Vertex c, Wgs84Vertex d) =>
    _cross(a, b, c) * _cross(a, b, d) < -1e-24 &&
    _cross(c, d, a) * _cross(c, d, b) < -1e-24;

  double _fraction(Wgs84Vertex a, Wgs84Vertex b, Wgs84Vertex p) {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;
    return ((p.longitude - a.longitude) * dx +
      (p.latitude - a.latitude) * dy) / (dx * dx + dy * dy);
  }
}
