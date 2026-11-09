enum SpatialGeometryType {
  point,
  lineString,
  polygon,
  multiPoint,
  multiLineString,
  multiPolygon,
}

/// Describes the geometry family of a spatial feature.
///
/// Coordinate implementations remain domain-specific during the first
/// Spatial Core migration phase. Existing farm WGS84 geometry is therefore
/// not moved or duplicated yet.
extension SpatialGeometryTypeX on SpatialGeometryType {
  bool get isPoint =>
      this == SpatialGeometryType.point ||
      this == SpatialGeometryType.multiPoint;

  bool get isLinear =>
      this == SpatialGeometryType.lineString ||
      this == SpatialGeometryType.multiLineString;

  bool get isAreal =>
      this == SpatialGeometryType.polygon ||
      this == SpatialGeometryType.multiPolygon;

  bool get isMultipart =>
      this == SpatialGeometryType.multiPoint ||
      this == SpatialGeometryType.multiLineString ||
      this == SpatialGeometryType.multiPolygon;
}
