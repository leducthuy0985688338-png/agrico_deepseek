import 'dart:math' as math;

import 'wgs84_geometry.dart';

/// Converts a closed tracing gesture into the interior cut. Boundary points
/// drawn before or after the interior run are already part of the source ring.
/// The closing tap on the first point is a gesture, not another cut endpoint.
class ParcelClosedOutline {
  const ParcelClosedOutline();

  static const _tolerance = 1e-9;

  List<Wgs84Vertex> interiorCut(
      Wgs84Polygon parent, List<Wgs84Vertex> traced) {
    if (traced.length < 3 || traced.any((point) => !point.isValid)) {
      throw const FormatException('A closed tracing needs valid boundary and interior points.');
    }
    final ring = parent.vertices.sublist(0, parent.vertices.length - 1);
    final points = List<Wgs84Vertex>.of(traced);
    if (points.last == points.first) points.removeLast();
    final onBoundary = points.map((point) => _onBoundary(ring, point)).toList();
    if (!onBoundary.first) {
      throw const FormatException('The tracing must start on the parcel boundary.');
    }
    final firstInterior = onBoundary.indexOf(false);
    final lastInterior = onBoundary.lastIndexOf(false);
    if (firstInterior < 1 || lastInterior < 0 ||
        onBoundary.sublist(firstInterior, lastInterior + 1).contains(true)) {
      throw const FormatException('A tracing must have one continuous interior cut.');
    }
    final entry = points[firstInterior - 1];
    final exit = lastInterior + 1 < points.length
        ? points[lastInterior + 1] : points.first;
    if (entry == exit) {
      throw const FormatException('The cut needs two distinct boundary anchors.');
    }
    for (var i = 1; i < firstInterior; i++) {
      if (!_sharesEdge(ring, points[i - 1], points[i])) {
        throw const FormatException('Traced boundary points must follow parcel edges.');
      }
    }
    for (var i = lastInterior + 2; i < points.length; i++) {
      if (!_sharesEdge(ring, points[i - 1], points[i])) {
        throw const FormatException('Traced boundary points must follow parcel edges.');
      }
    }
    return [entry, ...points.sublist(firstInterior, lastInterior + 1), exit];
  }

  bool _onBoundary(List<Wgs84Vertex> ring, Wgs84Vertex point) {
    for (var i = 0; i < ring.length; i++) {
      if (_onSegment(ring[i], point, ring[(i + 1) % ring.length])) return true;
    }
    return false;
  }

  bool _sharesEdge(List<Wgs84Vertex> ring, Wgs84Vertex a, Wgs84Vertex b) {
    for (var i = 0; i < ring.length; i++) {
      final from = ring[i];
      final to = ring[(i + 1) % ring.length];
      if (_onSegment(from, a, to) && _onSegment(from, b, to)) return true;
    }
    return false;
  }

  bool _onSegment(Wgs84Vertex a, Wgs84Vertex p, Wgs84Vertex b) {
    final cross = (b.longitude - a.longitude) * (p.latitude - a.latitude) -
        (b.latitude - a.latitude) * (p.longitude - a.longitude);
    return cross.abs() <= 1e-12 &&
        p.longitude >= math.min(a.longitude, b.longitude) - _tolerance &&
        p.longitude <= math.max(a.longitude, b.longitude) + _tolerance &&
        p.latitude >= math.min(a.latitude, b.latitude) - _tolerance &&
        p.latitude <= math.max(a.latitude, b.latitude) + _tolerance;
  }
}
