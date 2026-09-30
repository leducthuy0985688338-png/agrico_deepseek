import 'dart:math' as math;

import 'wgs84_geometry.dart';

/// Quan hệ không gian giữa hai vùng đóng WGS84 (có thể có lỗ).
///
/// `contains` và `containedBy` là chứa NGHIÊM NGẶT. Trường hợp biên bằng
/// nhau về hình học (kể cả khác số đỉnh do điểm thẳng hàng) trả về `equal`.
enum Wgs84SpatialRelation {
  disjoint,
  boundaryOnly,
  partiallyOverlap,
  contains,
  containedBy,
  equal,
}

/// Phép topology WGS84 dùng chung cho nghiệp vụ Lô–Thửa.
///
/// Không phụ thuộc `FieldPlotPlacement`. Không trộn containment với
/// overlap. Epsilon đồng nhất với `Wgs84Polygon` và `FieldPlotPlacement`.
///
/// Containment dùng **quét ngang phân hoạch thực tế**: chia theo latitude
/// sự kiện (đỉnh + giao điểm), mỗi dải chọn đường quét ngang, tính giao
/// điểm với mọi cạnh, kiểm từng khoảng giữa giao điểm.
class Wgs84Topology {
  const Wgs84Topology();

  static const double _epsilon = 1e-10;
  static const double _orientationEpsilon = 1e-12;
  static const double _probeScale = 1e-6;
  static const double _probeFloor = 1e-8;
  static const double _collinearAreaEpsilon = 1e-18;

  int locate(Wgs84Polygon polygon, Wgs84Vertex point) {
    final outer = _ringLocation(polygon.vertices, point);
    if (outer <= 0) return outer;
    for (final hole in polygon.holes) {
      final inner = _ringLocation(hole, point);
      if (inner == 0) return 0;
      if (inner > 0) return -1;
    }
    return 1;
  }

  Wgs84SpatialRelation relate(Wgs84Polygon a, Wgs84Polygon b) {
    if (_geometricallyEqual(a, b)) return Wgs84SpatialRelation.equal;

    if (!_interiorsOverlap(a, b)) {
      return _boundariesTouch(a, b)
          ? Wgs84SpatialRelation.boundaryOnly
          : Wgs84SpatialRelation.disjoint;
    }

    final aCoversB = _coversRing(a, b);
    final bCoversA = _coversRing(b, a);
    if (aCoversB && !bCoversA) return Wgs84SpatialRelation.contains;
    if (bCoversA && !aCoversB) return Wgs84SpatialRelation.containedBy;
    return Wgs84SpatialRelation.partiallyOverlap;
  }

  Wgs84SpatialRelation relateToMulti(
    Wgs84Polygon plot,
    List<Wgs84Polygon> block,
  ) {
    if (block.isEmpty) return Wgs84SpatialRelation.disjoint;

    final plotCovered = coversMulti(block, plot);
    final unionCovered = _unionCoveredByPolygon(block, plot);

    if (plotCovered && unionCovered) {
      return Wgs84SpatialRelation.equal;
    }

    if (plotCovered) {
      return Wgs84SpatialRelation.containedBy;
    }

    if (unionCovered) {
      return Wgs84SpatialRelation.contains;
    }

    if (_anyInteriorOverlapWithUnion(block, plot)) {
      return Wgs84SpatialRelation.partiallyOverlap;
    }

    if (_boundariesTouchMulti(block, plot)) {
      return Wgs84SpatialRelation.boundaryOnly;
    }

    return Wgs84SpatialRelation.disjoint;
  }

  bool interiorsOverlap(Wgs84Polygon a, Wgs84Polygon b) =>
      _interiorsOverlap(a, b);

  bool covers(Wgs84Polygon outer, Wgs84Polygon inner) =>
      _coversRing(outer, inner);

  /// `true` nếu toàn bộ vùng thực tế của [inner] nằm trong HỢP các vùng
  /// của [multi]. Dùng quét ngang phân hoạch thực tế.
  bool coversMulti(List<Wgs84Polygon> multi, Wgs84Polygon inner) {
    if (multi.isEmpty) return false;

    // 1) Biên inner phải được hợp vùng phủ.
    for (final ring in [inner.vertices, ...inner.holes]) {
      for (var i = 0; i < ring.length - 1; i++) {
        if (!_segmentCoveredByUnion(multi, ring[i], ring[i + 1])) {
          return false;
        }
      }
    }

    // 2) Quét ngang phân hoạch nội thất inner.
    return _everySweepIntervalCovered(multi, inner);
  }

  // ---------------------------------------------------------------------------
  // Quét ngang phân hoạch thực tế
  // ---------------------------------------------------------------------------

  /// Trả `false` nếu tồn tại khoảng nội thất inner không được hợp multi phủ.
  bool _everySweepIntervalCovered(
    List<Wgs84Polygon> multi,
    Wgs84Polygon inner,
  ) {
    // Latitude sự kiện: đỉnh + giao điểm.
    final lats = <double>{};

    void collectVertices(Wgs84Polygon p) {
      for (final ring in [p.vertices, ...p.holes]) {
        for (final v in ring) {
          lats.add(v.latitude);
        }
      }
    }

    collectVertices(inner);
    for (final p in multi) {
      collectVertices(p);
    }

    // Giao điểm giữa cạnh inner và cạnh multi.
    for (final innerRing in [inner.vertices, ...inner.holes]) {
      for (var i = 0; i < innerRing.length - 1; i++) {
        final a = innerRing[i];
        final b = innerRing[i + 1];
        for (final p in multi) {
          for (final pRing in [p.vertices, ...p.holes]) {
            for (var j = 0; j < pRing.length - 1; j++) {
              final c = pRing[j];
              final d = pRing[j + 1];
              final x = _segmentIntersection(a, b, c, d);
              if (x != null) lats.add(x.latitude);
            }
          }
        }
      }
    }

    final sortedLats = lats.toList()..sort();
    for (var i = 0; i + 1 < sortedLats.length; i++) {
      final latLo = sortedLats[i];
      final latHi = sortedLats[i + 1];
      if (latHi - latLo < _epsilon) continue;
      final sweepLat = (latLo + latHi) / 2;
      if (!_sweepLineCovered(multi, inner, sweepLat)) return false;
    }

    return true;
  }

  /// Kiểm tra một đường quét ngang `latitude = sweepLat` có được hợp multi
  /// phủ trên toàn bộ phần nội thất inner không.
  bool _sweepLineCovered(
    List<Wgs84Polygon> multi,
    Wgs84Polygon inner,
    double sweepLat,
  ) {
    // Thu thập giao điểm hoành độ của đường quét với mọi cạnh.
    final xs = <double>[];

    void collectCrossings(Wgs84Polygon p) {
      for (final ring in [p.vertices, ...p.holes]) {
        for (var i = 0; i < ring.length - 1; i++) {
          final a = ring[i];
          final b = ring[i + 1];
          final x = _horizontalIntersection(a, b, sweepLat);
          if (x != null) xs.add(x);
        }
      }
    }

    collectCrossings(inner);
    for (final p in multi) {
      collectCrossings(p);
    }

    if (xs.length < 2) return true;
    xs.sort();

    for (var i = 0; i + 1 < xs.length; i++) {
      final xLo = xs[i];
      final xHi = xs[i + 1];
      if (xHi - xLo < _epsilon) continue;
      final midX = (xLo + xHi) / 2;
      final point = Wgs84Vertex(latitude: sweepLat, longitude: midX);

      // Nội thất inner (>= 0, kể cả trên biên outer; loại nếu trong lỗ).
      final innerLoc = locate(inner, point);
      if (innerLoc < 0) continue;

      // Phải được hợp multi phủ (>= 0 trên ít nhất một vùng).
      if (!_pointCoveredByUnion(multi, point)) return false;
    }

    return true;
  }

  /// Giao điểm của đoạn `(a,b)` với đường ngang `latitude = y`.
  /// Trả hoành độ (longitude) hoặc `null` nếu không cắt.
  double? _horizontalIntersection(Wgs84Vertex a, Wgs84Vertex b, double y) {
    final lat1 = a.latitude;
    final lat2 = b.latitude;
    if ((lat1 - y).abs() < _epsilon && (lat2 - y).abs() < _epsilon) {
      // Đoạn nằm ngang trên đường quét — bỏ qua, biên được xử lý bởi
      // các điểm lân cận.
      return null;
    }
    if (lat1 == lat2) return null;
    final t = (y - lat1) / (lat2 - lat1);
    if (t < 0 || t > 1) return null;
    return a.longitude + t * (b.longitude - a.longitude);
  }

  /// Giao điểm hai đoạn `(a,b)` và `(c,d)` nếu có; ngược lại `null`.
  Wgs84Vertex? _segmentIntersection(
    Wgs84Vertex a,
    Wgs84Vertex b,
    Wgs84Vertex c,
    Wgs84Vertex d,
  ) {
    final dx1 = b.longitude - a.longitude;
    final dy1 = b.latitude - a.latitude;
    final dx2 = d.longitude - c.longitude;
    final dy2 = d.latitude - c.latitude;
    final denom = dx1 * dy2 - dy1 * dx2;
    if (denom.abs() < 1e-20) return null;
    final qx = c.longitude - a.longitude;
    final qy = c.latitude - a.latitude;
    final t = (qx * dy2 - qy * dx2) / denom;
    final u = (qx * dy1 - qy * dx1) / denom;
    if (t < -_epsilon || t > 1 + _epsilon) return null;
    if (u < -_epsilon || u > 1 + _epsilon) return null;
    return Wgs84Vertex(
      latitude: a.latitude + t * dy1,
      longitude: a.longitude + t * dx1,
    );
  }

  // ---------------------------------------------------------------------------
  // Equality
  // ---------------------------------------------------------------------------

  bool _geometricallyEqual(Wgs84Polygon a, Wgs84Polygon b) {
    if (a.holes.length != b.holes.length) return false;
    if (!_ringsEqualNormalized(a.vertices, b.vertices)) return false;
    final usedHoles = <int>{};
    for (final holeA in a.holes) {
      var found = false;
      for (var i = 0; i < b.holes.length; i++) {
        if (usedHoles.contains(i)) continue;
        if (_ringsEqualNormalized(holeA, b.holes[i])) {
          usedHoles.add(i);
          found = true;
          break;
        }
      }
      if (!found) return false;
    }
    return true;
  }

  bool _ringsEqualNormalized(List<Wgs84Vertex> a, List<Wgs84Vertex> b) {
    final aNorm = _normalizeRing(a);
    final bNorm = _normalizeRing(b);
    if (aNorm.length != bNorm.length) return false;
    if (aNorm.isEmpty) return true;
    for (var start = 0; start < bNorm.length; start++) {
      if (bNorm[start] == aNorm.first) {
        if (_ringMatchesForward(aNorm, bNorm, start)) return true;
        if (_ringMatchesReverse(aNorm, bNorm, start)) return true;
      }
    }
    return false;
  }

  List<Wgs84Vertex> _normalizeRing(List<Wgs84Vertex> ring) {
    final open = _stripClosing(ring);
    if (open.length < 3) return open;
    final result = <Wgs84Vertex>[];
    for (var i = 0; i < open.length; i++) {
      final prev = open[(i - 1 + open.length) % open.length];
      final curr = open[i];
      final next = open[(i + 1) % open.length];
      if (!_isCollinear(prev, curr, next)) {
        result.add(curr);
      }
    }
    return result;
  }

  bool _isCollinear(Wgs84Vertex a, Wgs84Vertex b, Wgs84Vertex c) {
    final area =
        (b.longitude - a.longitude) * (c.latitude - a.latitude) -
        (b.latitude - a.latitude) * (c.longitude - a.longitude);
    return area.abs() < _collinearAreaEpsilon;
  }

  List<Wgs84Vertex> _stripClosing(List<Wgs84Vertex> ring) {
    if (ring.length >= 2 && ring.first == ring.last) {
      return ring.sublist(0, ring.length - 1);
    }
    return List<Wgs84Vertex>.of(ring);
  }

  bool _ringMatchesForward(
    List<Wgs84Vertex> a,
    List<Wgs84Vertex> b,
    int start,
  ) {
    final n = a.length;
    for (var i = 0; i < n; i++) {
      if (a[i] != b[(start + i) % n]) return false;
    }
    return true;
  }

  bool _ringMatchesReverse(
    List<Wgs84Vertex> a,
    List<Wgs84Vertex> b,
    int start,
  ) {
    for (var i = 0; i < a.length; i++) {
      final index = (start - i) % a.length;
      final wrapped = index < 0 ? index + a.length : index;
      if (a[i] != b[wrapped]) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Overlap / boundary
  // ---------------------------------------------------------------------------

  bool _interiorsOverlap(Wgs84Polygon a, Wgs84Polygon b) {
    for (final pair in [(a, b), (b, a)]) {
      final source = pair.$1;
      final target = pair.$2;
      for (final ring in [source.vertices, ...source.holes]) {
        for (var i = 0; i < ring.length - 1; i++) {
          if (_anyInteriorProbeOverlaps(ring[i], ring[i + 1], source, target)) {
            return true;
          }
        }
      }
    }
    for (final vertex in a.vertices.take(a.vertices.length - 1)) {
      if (locate(b, vertex) > 0) return true;
    }
    for (final vertex in b.vertices.take(b.vertices.length - 1)) {
      if (locate(a, vertex) > 0) return true;
    }
    return false;
  }

  bool _anyInteriorProbeOverlaps(
    Wgs84Vertex from,
    Wgs84Vertex to,
    Wgs84Polygon source,
    Wgs84Polygon target,
  ) {
    final dx = to.longitude - from.longitude;
    final dy = to.latitude - from.latitude;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return false;
    final cuts = _segmentCuts(from, to, target)..sort();
    for (var i = 1; i < cuts.length; i++) {
      if (cuts[i] <= cuts[i - 1]) continue;
      final midT = (cuts[i] + cuts[i - 1]) / 2;
      final mid = Wgs84Vertex(
        latitude: from.latitude + midT * dy,
        longitude: from.longitude + midT * dx,
      );
      final offset = math.min(length * _probeScale, _probeFloor);
      for (final sign in [-1, 1]) {
        final probe = Wgs84Vertex(
          latitude: mid.latitude + dx / length * offset * sign,
          longitude: mid.longitude - dy / length * offset * sign,
        );
        if (locate(source, probe) > 0 && locate(target, probe) > 0) {
          return true;
        }
      }
    }
    return false;
  }

  List<double> _segmentCuts(
    Wgs84Vertex from,
    Wgs84Vertex to,
    Wgs84Polygon other,
  ) {
    final dx = to.longitude - from.longitude;
    final dy = to.latitude - from.latitude;
    final length2 = dx * dx + dy * dy;
    final cuts = <double>[0, 1];
    if (length2 == 0) return cuts;
    for (final ring in [other.vertices, ...other.holes]) {
      for (var i = 0; i < ring.length - 1; i++) {
        final c = ring[i];
        final d = ring[i + 1];
        final ex = d.longitude - c.longitude;
        final ey = d.latitude - c.latitude;
        final qx = c.longitude - from.longitude;
        final qy = c.latitude - from.latitude;
        final cross = dx * ey - dy * ex;
        if (cross.abs() > 1e-20) {
          final t = (qx * ey - qy * ex) / cross;
          final u = (qx * dy - qy * dx) / cross;
          if (t >= 0 && t <= 1 && u >= 0 && u <= 1) cuts.add(t);
        } else {
          for (final point in [c, d]) {
            if (_onSegment(from, point, to)) {
              cuts.add(
                ((point.longitude - from.longitude) * dx +
                        (point.latitude - from.latitude) * dy) /
                    length2,
              );
            }
          }
        }
      }
    }
    return cuts;
  }

  bool _boundariesTouch(Wgs84Polygon a, Wgs84Polygon b) {
    for (final ringA in [a.vertices, ...a.holes]) {
      for (var i = 0; i < ringA.length - 1; i++) {
        for (final ringB in [b.vertices, ...b.holes]) {
          for (var j = 0; j < ringB.length - 1; j++) {
            if (_segmentsIntersect(
              ringA[i],
              ringA[i + 1],
              ringB[j],
              ringB[j + 1],
            )) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Covers đơn
  // ---------------------------------------------------------------------------

  bool _coversRing(Wgs84Polygon outer, Wgs84Polygon inner) {
    for (final hole in outer.holes) {
      if (_ringIntersectsRealRegion(hole, inner)) return false;
    }

    for (final ring in [inner.vertices, ...inner.holes]) {
      for (var i = 0; i < ring.length - 1; i++) {
        final from = ring[i];
        final to = ring[i + 1];
        if (!_segmentWithinOuterOrBoundary(outer, from, to)) return false;
      }
    }

    for (final sample in _realInteriorSamples(inner)) {
      if (locate(outer, sample) < 0) return false;
    }

    return true;
  }

  bool _segmentWithinOuterOrBoundary(
    Wgs84Polygon outer,
    Wgs84Vertex from,
    Wgs84Vertex to,
  ) {
    if (locate(outer, from) < 0 || locate(outer, to) < 0) return false;
    final cuts = _segmentCuts(from, to, outer)..sort();
    for (var i = 1; i < cuts.length; i++) {
      if (cuts[i] <= cuts[i - 1]) continue;
      final midT = (cuts[i] + cuts[i - 1]) / 2;
      final mid = Wgs84Vertex(
        latitude: from.latitude + (to.latitude - from.latitude) * midT,
        longitude: from.longitude + (to.longitude - from.longitude) * midT,
      );
      if (locate(outer, mid) < 0) return false;
    }
    return true;
  }

  bool _ringIntersectsRealRegion(List<Wgs84Vertex> ring, Wgs84Polygon inner) {
    for (var i = 0; i < ring.length - 1; i++) {
      final from = ring[i];
      final to = ring[i + 1];
      final cuts = _segmentCuts(from, to, inner)..sort();
      for (var k = 1; k < cuts.length; k++) {
        if (cuts[k] <= cuts[k - 1]) continue;
        final midT = (cuts[k] + cuts[k - 1]) / 2;
        final mid = Wgs84Vertex(
          latitude: from.latitude + (to.latitude - from.latitude) * midT,
          longitude: from.longitude + (to.longitude - from.longitude) * midT,
        );
        if (locate(inner, mid) > 0) return true;
      }
    }
    return false;
  }

  Iterable<Wgs84Vertex> _realInteriorSamples(Wgs84Polygon inner) sync* {
    yield* _interiorSamples(inner);
    final c = _ringCentroid(inner.vertices);
    if (c != null && locate(inner, c) > 0) yield c;
  }

  Wgs84Vertex? _ringCentroid(List<Wgs84Vertex> ring) {
    if (ring.isEmpty) return null;
    final open = _stripClosing(ring);
    if (open.isEmpty) return null;
    var latSum = 0.0;
    var lonSum = 0.0;
    for (final v in open) {
      latSum += v.latitude;
      lonSum += v.longitude;
    }
    return Wgs84Vertex(
      latitude: latSum / open.length,
      longitude: lonSum / open.length,
    );
  }

  bool _unionCoveredByPolygon(List<Wgs84Polygon> multi, Wgs84Polygon plot) {
    for (final polygon in multi) {
      if (!_coversRing(plot, polygon)) return false;
    }
    return true;
  }

  bool _anyInteriorOverlapWithUnion(
    List<Wgs84Polygon> multi,
    Wgs84Polygon plot,
  ) {
    for (final polygon in multi) {
      if (_interiorsOverlap(polygon, plot)) return true;
    }
    return false;
  }

  bool _boundariesTouchMulti(List<Wgs84Polygon> multi, Wgs84Polygon plot) {
    for (final polygon in multi) {
      if (_boundariesTouch(polygon, plot)) return true;
    }
    return false;
  }

  bool _segmentCoveredByUnion(
    List<Wgs84Polygon> multi,
    Wgs84Vertex from,
    Wgs84Vertex to,
  ) {
    for (final polygon in multi) {
      if (_segmentCoveredByPolygon(polygon, from, to)) return true;
    }
    final cuts = <double>[0, 1];
    for (final polygon in multi) {
      cuts.addAll(_segmentCuts(from, to, polygon));
    }
    cuts.sort();
    final dx = to.longitude - from.longitude;
    final dy = to.latitude - from.latitude;
    for (var i = 1; i < cuts.length; i++) {
      if (cuts[i] <= cuts[i - 1]) continue;
      final midT = (cuts[i] + cuts[i - 1]) / 2;
      final mid = Wgs84Vertex(
        latitude: from.latitude + midT * dy,
        longitude: from.longitude + midT * dx,
      );
      if (!_pointCoveredByUnion(multi, mid)) return false;
    }
    return true;
  }

  bool _segmentCoveredByPolygon(
    Wgs84Polygon polygon,
    Wgs84Vertex from,
    Wgs84Vertex to,
  ) {
    if (locate(polygon, from) < 0 || locate(polygon, to) < 0) return false;
    final cuts = _segmentCuts(from, to, polygon)..sort();
    for (var i = 1; i < cuts.length; i++) {
      if (cuts[i] <= cuts[i - 1]) continue;
      final midT = (cuts[i] + cuts[i - 1]) / 2;
      final mid = Wgs84Vertex(
        latitude: from.latitude + (to.latitude - from.latitude) * midT,
        longitude: from.longitude + (to.longitude - from.longitude) * midT,
      );
      if (locate(polygon, mid) < 0) return false;
    }
    return true;
  }

  bool _pointCoveredByUnion(List<Wgs84Polygon> multi, Wgs84Vertex point) {
    for (final polygon in multi) {
      if (locate(polygon, point) >= 0) return true;
    }
    return false;
  }

  Iterable<Wgs84Vertex> _interiorSamples(Wgs84Polygon polygon) sync* {
    final ring = polygon.vertices;
    for (var i = 0; i < ring.length - 1; i++) {
      final from = ring[i];
      final to = ring[i + 1];
      final dx = to.longitude - from.longitude;
      final dy = to.latitude - from.latitude;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length == 0) continue;
      final mid = Wgs84Vertex(
        latitude: (from.latitude + to.latitude) / 2,
        longitude: (from.longitude + to.longitude) / 2,
      );
      final offset = math.min(length * _probeScale, _probeFloor);
      final a = Wgs84Vertex(
        latitude: mid.latitude - dx / length * offset,
        longitude: mid.longitude + dy / length * offset,
      );
      if (locate(polygon, a) > 0) yield a;
      final b = Wgs84Vertex(
        latitude: mid.latitude + dx / length * offset,
        longitude: mid.longitude - dy / length * offset,
      );
      if (locate(polygon, b) > 0) yield b;
    }
  }

  int _ringLocation(List<Wgs84Vertex> ring, Wgs84Vertex point) {
    var inside = false;
    for (var i = 0; i < ring.length - 1; i++) {
      final a = ring[i];
      final b = ring[i + 1];
      if (_onSegment(a, point, b)) return 0;
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
    if (length == 0) return p == a;
    final cross =
        dx * (p.latitude - a.latitude) - dy * (p.longitude - a.longitude);
    return cross.abs() <= _epsilon * length &&
        p.longitude >= math.min(a.longitude, b.longitude) - _epsilon &&
        p.longitude <= math.max(a.longitude, b.longitude) + _epsilon &&
        p.latitude >= math.min(a.latitude, b.latitude) - _epsilon &&
        p.latitude <= math.max(a.latitude, b.latitude) + _epsilon;
  }

  bool _segmentsIntersect(
    Wgs84Vertex a,
    Wgs84Vertex b,
    Wgs84Vertex c,
    Wgs84Vertex d,
  ) {
    final o1 = _orientation(a, b, c);
    final o2 = _orientation(a, b, d);
    final o3 = _orientation(c, d, a);
    final o4 = _orientation(c, d, b);
    if (o1.abs() < _orientationEpsilon && _onSegment(a, c, b)) return true;
    if (o2.abs() < _orientationEpsilon && _onSegment(a, d, b)) return true;
    if (o3.abs() < _orientationEpsilon && _onSegment(c, a, d)) return true;
    if (o4.abs() < _orientationEpsilon && _onSegment(c, b, d)) return true;
    return (o1 > 0) != (o2 > 0) && (o3 > 0) != (o4 > 0);
  }

  double _orientation(Wgs84Vertex a, Wgs84Vertex b, Wgs84Vertex c) =>
      (b.longitude - a.longitude) * (c.latitude - a.latitude) -
      (b.latitude - a.latitude) * (c.longitude - a.longitude);
}
