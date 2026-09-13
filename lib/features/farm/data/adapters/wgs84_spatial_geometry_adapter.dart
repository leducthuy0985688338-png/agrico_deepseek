import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';

/// Bridges the legacy Farm WGS84 geometry model and Spatial Core geometry.
///
/// This adapter deliberately performs data translation only. Validation and
/// topology rules remain owned by the respective geometry models.
class Wgs84SpatialGeometryAdapter {
  const Wgs84SpatialGeometryAdapter();

  SpatialCoordinate toSpatialCoordinate(Wgs84Vertex vertex) {
    return SpatialCoordinate(
      latitude: vertex.latitude,
      longitude: vertex.longitude,
      altitudeM: vertex.altitudeM,
    );
  }

  Wgs84Vertex toWgs84Vertex(SpatialCoordinate coordinate) {
    return Wgs84Vertex(
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
      altitudeM: coordinate.altitudeM,
    );
  }

  SpatialPolygon toSpatialPolygon(Wgs84Polygon polygon) {
    return SpatialPolygon.fromOuterRing(
      polygon.vertices.map(toSpatialCoordinate).toList(growable: false),
    );
  }

  Wgs84Polygon toWgs84Polygon(SpatialPolygon polygon) {
    return Wgs84Polygon.fromVertices(
      polygon.outerRing.map(toWgs84Vertex).toList(growable: false),
    );
  }
}
