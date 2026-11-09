import 'dart:collection';
import 'dart:math' as math;

enum PolygonValidationIssue {
  tooFewDistinctVertices,
  invalidCoordinate,
  selfIntersection,
}

class PolygonValidationException implements FormatException {
  const PolygonValidationException(this.issue, this.message);

  final PolygonValidationIssue issue;

  @override
  final String message;

  @override
  dynamic get source => null;

  @override
  int? get offset => null;

  @override
  String toString() => 'PolygonValidationException($issue): $message';
}

/// A coordinate in WGS84 (EPSG:4326). Domain order is always latitude then
/// longitude; format adapters such as KML must map their own coordinate order.
class Wgs84Vertex {
  const Wgs84Vertex({
    required this.latitude,
    required this.longitude,
    this.altitudeM,
  });

  final double latitude;
  final double longitude;
  final double? altitudeM;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      (altitudeM == null || altitudeM!.isFinite);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Wgs84Vertex &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          altitudeM == other.altitudeM;

  @override
  int get hashCode => Object.hash(latitude, longitude, altitudeM);
}

class Wgs84Polygon {
  Wgs84Polygon._(List<Wgs84Vertex> vertices,
      List<List<Wgs84Vertex>> holes)
    : vertices = UnmodifiableListView(vertices),
      holes = UnmodifiableListView(holes.map(
        (ring) => UnmodifiableListView<Wgs84Vertex>(ring)).toList());

  factory Wgs84Polygon.fromVertices(Iterable<Wgs84Vertex> input, {
    Iterable<Iterable<Wgs84Vertex>> holes = const [],
  }) {
    final vertices = List<Wgs84Vertex>.of(input);
    if (vertices.any((vertex) => !vertex.isValid)) {
      throw const PolygonValidationException(
        PolygonValidationIssue.invalidCoordinate,
        'Every vertex must be a finite WGS84 latitude/longitude coordinate.',
      );
    }

    if (vertices.isNotEmpty && vertices.first == vertices.last) {
      vertices.removeLast();
    }
    if (vertices.toSet().length < 3) {
      throw const PolygonValidationException(
        PolygonValidationIssue.tooFewDistinctVertices,
        'A polygon requires at least three distinct vertices.',
      );
    }

    vertices.add(vertices.first);
    if (_hasSelfIntersection(vertices)) {
      throw const PolygonValidationException(
        PolygonValidationIssue.selfIntersection,
        'The polygon exterior ring intersects itself.',
      );
    }
    final innerRings = <List<Wgs84Vertex>>[];
    for (final rawHole in holes) {
      final ring = Wgs84Polygon.fromVertices(rawHole).vertices.toList();
      if (ring.take(ring.length - 1)
          .any((point) => !_strictlyInside(vertices, point)) ||
          _ringsMeet(vertices, ring)) {
        throw const FormatException('Interior ring must lie strictly inside the exterior ring.');
      }
      for (final other in innerRings) {
        if (_ringsMeet(other, ring) ||
            _strictlyInside(other, ring.first) ||
            _strictlyInside(ring, other.first)) {
          throw const FormatException('Interior rings cannot overlap or nest.');
        }
      }
      innerRings.add(ring);
    }
    return Wgs84Polygon._(vertices, innerRings);
  }

  static const crsCode = 'EPSG:4326';

  final UnmodifiableListView<Wgs84Vertex> vertices;
  final UnmodifiableListView<UnmodifiableListView<Wgs84Vertex>> holes;

  String get crs => crsCode;
  int get distinctVertexCount => vertices.length - 1;
  bool get isClosed => vertices.first == vertices.last;

  static bool _strictlyInside(List<Wgs84Vertex> ring, Wgs84Vertex point) {
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

  static bool _ringsMeet(List<Wgs84Vertex> first, List<Wgs84Vertex> second) {
    for (var i = 0; i < first.length - 1; i++) {
      for (var j = 0; j < second.length - 1; j++) {
        if (_segmentsIntersect(first[i], first[i + 1],
            second[j], second[j + 1])) return true;
      }
    }
    return false;
  }

  static bool _hasSelfIntersection(List<Wgs84Vertex> ring) {
    final segmentCount = ring.length - 1;
    for (var first = 0; first < segmentCount; first++) {
      for (var second = first + 1; second < segmentCount; second++) {
        final adjacent =
            second == first + 1 || (first == 0 && second == segmentCount - 1);
        if (adjacent) continue;
        if (_segmentsIntersect(
          ring[first],
          ring[first + 1],
          ring[second],
          ring[second + 1],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _segmentsIntersect(
    Wgs84Vertex a,
    Wgs84Vertex b,
    Wgs84Vertex c,
    Wgs84Vertex d,
  ) {
    final o1 = _orientation(a, b, c);
    final o2 = _orientation(a, b, d);
    final o3 = _orientation(c, d, a);
    final o4 = _orientation(c, d, b);
    const epsilon = 1e-12;

    if (o1.abs() < epsilon && _onSegment(a, c, b)) return true;
    if (o2.abs() < epsilon && _onSegment(a, d, b)) return true;
    if (o3.abs() < epsilon && _onSegment(c, a, d)) return true;
    if (o4.abs() < epsilon && _onSegment(c, b, d)) return true;
    return (o1 > 0) != (o2 > 0) && (o3 > 0) != (o4 > 0);
  }

  static double _orientation(Wgs84Vertex a, Wgs84Vertex b, Wgs84Vertex c) =>
      (b.longitude - a.longitude) * (c.latitude - a.latitude) -
      (b.latitude - a.latitude) * (c.longitude - a.longitude);

  static bool _onSegment(Wgs84Vertex a, Wgs84Vertex point, Wgs84Vertex b) =>
      point.longitude >= math.min(a.longitude, b.longitude) &&
      point.longitude <= math.max(a.longitude, b.longitude) &&
      point.latitude >= math.min(a.latitude, b.latitude) &&
      point.latitude <= math.max(a.latitude, b.latitude);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Wgs84Polygon || vertices.length != other.vertices.length ||
        holes.length != other.holes.length) {
      return false;
    }
    for (var index = 0; index < vertices.length; index++) {
      if (vertices[index] != other.vertices[index]) return false;
    }
    for (var ring = 0; ring < holes.length; ring++) {
      if (holes[ring].length != other.holes[ring].length) return false;
      for (var point = 0; point < holes[ring].length; point++) {
        if (holes[ring][point] != other.holes[ring][point]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(vertices),
    Object.hashAll(holes.map((ring) => Object.hashAll(ring))));
}

class Wgs84PolygonMetrics {
  const Wgs84PolygonMetrics({
    required this.centroid,
    required this.areaM2,
    required this.perimeterM,
  });

  final Wgs84Vertex centroid;
  final double areaM2;
  final double perimeterM;

  double get areaHa => areaM2 / 10000;
}

class Wgs84GeometryService {
  const Wgs84GeometryService();

  static const earthRadiusM = 6371008.8;

  Wgs84PolygonMetrics measure(Wgs84Polygon polygon) {
    final outerArea = _area(polygon.vertices);
    final holeAreas = polygon.holes.map(_area).toList();
    final area = outerArea - holeAreas.fold(0.0, (sum, value) => sum + value);
    if (area <= 0) {
      throw const FormatException('Polygon holes cannot cover its exterior.');
    }
    final outerCentroid = _centroid(polygon.vertices);
    var latitude = outerCentroid.latitude * outerArea;
    var longitude = outerCentroid.longitude * outerArea;
    for (var i = 0; i < polygon.holes.length; i++) {
      final center = _centroid(polygon.holes[i]);
      latitude -= center.latitude * holeAreas[i];
      longitude -= center.longitude * holeAreas[i];
    }
    return Wgs84PolygonMetrics(
      centroid: Wgs84Vertex(latitude: latitude / area,
        longitude: longitude / area),
      areaM2: area,
      perimeterM: _perimeter(polygon.vertices) +
        polygon.holes.fold(0.0, (sum, ring) => sum + _perimeter(ring)),
    );
  }

  double _area(List<Wgs84Vertex> ring) {
    var sum = 0.0;
    for (var index = 0; index < ring.length - 1; index++) {
      final current = ring[index];
      final next = ring[index + 1];
      final deltaLongitude = _normalizeRadians(
        _radians(next.longitude - current.longitude),
      );
      sum +=
          deltaLongitude *
          (2 +
              math.sin(_radians(current.latitude)) +
              math.sin(_radians(next.latitude)));
    }
    return (sum * earthRadiusM * earthRadiusM / 2).abs();
  }

  double _perimeter(List<Wgs84Vertex> ring) {
    var total = 0.0;
    for (var index = 0; index < ring.length - 1; index++) {
      total += _distance(ring[index], ring[index + 1]);
    }
    return total;
  }

  Wgs84Vertex _centroid(List<Wgs84Vertex> ring) {
    final origin = ring.first;
    final latitude0 = _radians(
      ring.take(ring.length - 1).fold(0.0, (sum, item) => sum + item.latitude) /
          (ring.length - 1),
    );
    final points = ring
        .map((vertex) {
          final longitudeDelta = _normalizeRadians(
            _radians(vertex.longitude - origin.longitude),
          );
          return (
            x: earthRadiusM * longitudeDelta * math.cos(latitude0),
            y: earthRadiusM * _radians(vertex.latitude - origin.latitude),
          );
        })
        .toList(growable: false);

    var twiceArea = 0.0;
    var xSum = 0.0;
    var ySum = 0.0;
    for (var index = 0; index < points.length - 1; index++) {
      final cross =
          points[index].x * points[index + 1].y -
          points[index + 1].x * points[index].y;
      twiceArea += cross;
      xSum += (points[index].x + points[index + 1].x) * cross;
      ySum += (points[index].y + points[index + 1].y) * cross;
    }

    if (twiceArea.abs() < 1e-9) {
      throw const PolygonValidationException(
        PolygonValidationIssue.tooFewDistinctVertices,
        'Polygon vertices must enclose a non-zero area.',
      );
    }
    final centroidX = xSum / (3 * twiceArea);
    final centroidY = ySum / (3 * twiceArea);
    return Wgs84Vertex(
      latitude: origin.latitude + _degrees(centroidY / earthRadiusM),
      longitude:
          origin.longitude +
          _degrees(centroidX / (earthRadiusM * math.cos(latitude0))),
    );
  }

  double _distance(Wgs84Vertex first, Wgs84Vertex second) {
    final deltaLatitude = _radians(second.latitude - first.latitude);
    final deltaLongitude = _normalizeRadians(
      _radians(second.longitude - first.longitude),
    );
    final firstLatitude = _radians(first.latitude);
    final secondLatitude = _radians(second.latitude);
    final haversine =
        math.pow(math.sin(deltaLatitude / 2), 2) +
        math.cos(firstLatitude) *
            math.cos(secondLatitude) *
            math.pow(math.sin(deltaLongitude / 2), 2);
    return 2 * earthRadiusM * math.asin(math.sqrt(haversine));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
  static double _degrees(double radians) => radians * 180 / math.pi;
  static double _normalizeRadians(double value) {
    var normalized = value;
    while (normalized > math.pi) {
      normalized -= 2 * math.pi;
    }
    while (normalized < -math.pi) {
      normalized += 2 * math.pi;
    }
    return normalized;
  }
}
