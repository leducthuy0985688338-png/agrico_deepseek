import 'wgs84_geometry.dart';
import 'wgs84_multi_polygon.dart';
import 'wgs84_topology.dart';

class Wgs84MultiPolygonMetrics {
  const Wgs84MultiPolygonMetrics({
    required this.representativePoint,
    required this.totalAreaM2,
    required this.totalPerimeterM,
    required this.unionBoundaryPerimeterM,
  });

  final Wgs84Vertex representativePoint;
  final double totalAreaM2;
  final double totalPerimeterM;
  final double? unionBoundaryPerimeterM;

  double get totalAreaHa => totalAreaM2 / 10000;
}

class Wgs84MultiGeometryService {
  const Wgs84MultiGeometryService();

  static const Wgs84GeometryService _single = Wgs84GeometryService();
  static const Wgs84Topology _topology = Wgs84Topology();

  /// Đo một `Wgs84MultiPolygon`.
  ///
  /// Ném `FormatException` nếu hai vùng chồng nội thất — không cho phép
  /// cộng chồng diện tích Lô. Gọi `validateNoInteriorOverlap` trước khi
  /// tính metrics.
  Wgs84MultiPolygonMetrics measure(Wgs84MultiPolygon multi) {
    if (multi.polygons.isEmpty) {
      throw const FormatException('Cannot measure an empty Wgs84MultiPolygon.');
    }

    // Từ chối vùng trùng / vùng lồng trước khi cộng diện tích.
    validateNoInteriorOverlap(multi);

    var totalArea = 0.0;
    var totalPerimeter = 0.0;
    var latitudeAccumulator = 0.0;
    var longitudeAccumulator = 0.0;

    for (final polygon in multi.polygons) {
      final metrics = _single.measure(polygon);
      totalArea += metrics.areaM2;
      totalPerimeter += metrics.perimeterM;
      latitudeAccumulator += metrics.centroid.latitude * metrics.areaM2;
      longitudeAccumulator += metrics.centroid.longitude * metrics.areaM2;
    }

    if (totalArea <= 0) {
      throw const FormatException(
        'Wgs84MultiPolygon must enclose a positive total area.',
      );
    }

    return Wgs84MultiPolygonMetrics(
      representativePoint: Wgs84Vertex(
        latitude: latitudeAccumulator / totalArea,
        longitude: longitudeAccumulator / totalArea,
      ),
      totalAreaM2: totalArea,
      totalPerimeterM: totalPerimeter,
      unionBoundaryPerimeterM: null,
    );
  }

  /// Ném `FormatException` nếu hai vùng bất kỳ trong [multi] chồng nội thất
  /// với diện tích dương. Chung cạnh hoặc chung đỉnh được phép.
  void validateNoInteriorOverlap(Wgs84MultiPolygon multi) {
    final polygons = multi.polygons;
    for (var i = 0; i < polygons.length; i++) {
      for (var j = i + 1; j < polygons.length; j++) {
        if (_topology.interiorsOverlap(polygons[i], polygons[j])) {
          throw const FormatException(
            'Wgs84MultiPolygon regions must not overlap interiors; '
            'shared boundaries or vertices are allowed.',
          );
        }
      }
    }
  }

  bool covers(Wgs84MultiPolygon multi, Wgs84Polygon inner) =>
      _topology.coversMulti(multi.polygons, inner);

  Wgs84SpatialRelation relateToMulti(
    Wgs84Polygon plot,
    Wgs84MultiPolygon block,
  ) => _topology.relateToMulti(plot, block.polygons);
}
