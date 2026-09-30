import 'dart:math' as math;

import 'wgs84_geometry.dart';

/// Placement checks for the Nong production model. Boundaries may be shared;
/// filled interiors may not overlap. No coverage or area-sum rule is imposed.
class FieldPlotPlacement {
  const FieldPlotPlacement();
  static const _epsilon = 1e-10;

  void validate({
    required Wgs84Polygon block,
    required Wgs84Polygon plot,
    Iterable<Wgs84Polygon> existingPlots = const [],
  }) {
    for (final (a, b) in _edges(plot)) {
      if (_samples(a, b, block).any((point) => _location(block, point) < 0)) {
        throw const FormatException(
          'Field plot extends outside its land block.',
        );
      }
    }
    // A parent exclusion entirely surrounded by the new plot would not be
    // detected by checking only the new plot's exterior boundary.
    for (final hole in block.holes) {
      if (hole.any((point) => _location(plot, point) > 0)) {
        throw const FormatException(
          'Field plot covers a land block exclusion.',
        );
      }
    }
    for (final other in existingPlots) {
      if (_overlap(plot, other)) {
        throw const FormatException(
          'Field plot overlaps an existing field plot.',
        );
      }
    }
  }

  Iterable<(Wgs84Vertex, Wgs84Vertex)> _edges(Wgs84Polygon polygon) sync* {
    for (final ring in [polygon.vertices, ...polygon.holes]) {
      for (var i = 0; i < ring.length - 1; i++) {
        yield (ring[i], ring[i + 1]);
      }
    }
  }

  bool _overlap(Wgs84Polygon a, Wgs84Polygon b) {
    for (final pair in [(a, b), (b, a)]) {
      for (final (from, to) in _edges(pair.$1)) {
        if (_samples(from, to, pair.$2).any((p) => _location(pair.$2, p) > 0)) {
          return true;
        }
        // Coincident outlines have no strictly interior boundary point.
        // Probe both sides of each subdivided segment, accepting a probe
        // only when it lies in both filled polygon interiors.
        final dx = to.longitude - from.longitude;
        final dy = to.latitude - from.latitude;
        final length = math.sqrt(dx * dx + dy * dy);
        if (length == 0) {
          continue;
        }
        for (final middle in _samples(from, to, pair.$2)) {
          for (final sign in [-1, 1]) {
            final offset = math.min(length * 1e-6, 1e-8) * sign;
            final probe = Wgs84Vertex(
              latitude: middle.latitude + dx / length * offset,
              longitude: middle.longitude - dy / length * offset,
            );
            if (_location(a, probe) > 0 && _location(b, probe) > 0) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  Iterable<Wgs84Vertex> _samples(
    Wgs84Vertex a,
    Wgs84Vertex b,
    Wgs84Polygon other,
  ) sync* {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;
    final length2 = dx * dx + dy * dy;
    final cuts = <double>[0, 1];
    if (length2 == 0) {
      yield a;
      return;
    }
    for (final (c, d) in _edges(other)) {
      final ex = d.longitude - c.longitude;
      final ey = d.latitude - c.latitude;
      final qx = c.longitude - a.longitude;
      final qy = c.latitude - a.latitude;
      final cross = dx * ey - dy * ex;
      if (cross.abs() > 1e-20) {
        final t = (qx * ey - qy * ex) / cross;
        final u = (qx * dy - qy * dx) / cross;
        if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
          cuts.add(t);
        }
      } else {
        for (final point in [c, d]) {
          if (_onSegment(a, point, b)) {
            cuts.add(
              ((point.longitude - a.longitude) * dx +
                      (point.latitude - a.latitude) * dy) /
                  length2,
            );
          }
        }
      }
    }
    cuts.sort();
    Wgs84Vertex at(double t) => Wgs84Vertex(
      latitude: a.latitude + t * dy,
      longitude: a.longitude + t * dx,
    );
    yield a;
    yield b;
    for (var i = 1; i < cuts.length; i++) {
      if (cuts[i] > cuts[i - 1]) {
        yield at((cuts[i] + cuts[i - 1]) / 2);
      }
    }
  }

  int _location(Wgs84Polygon polygon, Wgs84Vertex point) {
    final outer = _ringLocation(polygon.vertices, point);
    if (outer <= 0) {
      return outer;
    }
    for (final hole in polygon.holes) {
      final inner = _ringLocation(hole, point);
      if (inner == 0) {
        return 0;
      }
      if (inner > 0) {
        return -1;
      }
    }
    return 1;
  }

  int _ringLocation(List<Wgs84Vertex> ring, Wgs84Vertex point) {
    var inside = false;
    for (var i = 0; i < ring.length - 1; i++) {
      final a = ring[i];
      final b = ring[i + 1];
      if (_onSegment(a, point, b)) {
        return 0;
      }
      if ((a.latitude > point.latitude) != (b.latitude > point.latitude) &&
          point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        inside = !inside;
      }
    }
    return inside ? 1 : -1;
  }

  bool _onSegment(Wgs84Vertex a, Wgs84Vertex p, Wgs84Vertex b) {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) {
      return p == a;
    }
    final cross =
        dx * (p.latitude - a.latitude) - dy * (p.longitude - a.longitude);
    return cross.abs() <= _epsilon * length &&
        p.longitude >= math.min(a.longitude, b.longitude) - _epsilon &&
        p.longitude <= math.max(a.longitude, b.longitude) + _epsilon &&
        p.latitude >= math.min(a.latitude, b.latitude) - _epsilon &&
        p.latitude <= math.max(a.latitude, b.latitude) + _epsilon;
  }
}
