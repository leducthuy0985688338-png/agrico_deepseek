import 'dart:collection';

import 'spatial_geometry_type.dart';
import 'spatial_linear_geometry.dart';
import 'spatial_polygon.dart';

/// Collection of one or more point geometries.
class SpatialMultiPoint {
  SpatialMultiPoint._(List<SpatialPoint> points)
    : points = UnmodifiableListView(points);

  factory SpatialMultiPoint.fromPoints(Iterable<SpatialPoint> input) {
    final points = List<SpatialPoint>.of(input);

    if (points.isEmpty) {
      throw const FormatException(
        'Spatial MultiPoint must contain at least one point.',
      );
    }

    for (final point in points) {
      point.validate();
    }

    return SpatialMultiPoint._(points);
  }

  final UnmodifiableListView<SpatialPoint> points;

  SpatialGeometryType get geometryType => SpatialGeometryType.multiPoint;

  void validate() {
    if (points.isEmpty) {
      throw const FormatException(
        'Spatial MultiPoint must contain at least one point.',
      );
    }

    for (final point in points) {
      point.validate();
    }
  }
}

/// Collection of one or more LineString geometries.
class SpatialMultiLineString {
  SpatialMultiLineString._(List<SpatialLineString> lineStrings)
    : lineStrings = UnmodifiableListView(lineStrings);

  factory SpatialMultiLineString.fromLineStrings(
    Iterable<SpatialLineString> input,
  ) {
    final lineStrings = List<SpatialLineString>.of(input);

    if (lineStrings.isEmpty) {
      throw const FormatException(
        'Spatial MultiLineString must contain at least one LineString.',
      );
    }

    for (final lineString in lineStrings) {
      lineString.validate();
    }

    return SpatialMultiLineString._(lineStrings);
  }

  final UnmodifiableListView<SpatialLineString> lineStrings;

  SpatialGeometryType get geometryType => SpatialGeometryType.multiLineString;

  void validate() {
    if (lineStrings.isEmpty) {
      throw const FormatException(
        'Spatial MultiLineString must contain at least one LineString.',
      );
    }

    for (final lineString in lineStrings) {
      lineString.validate();
    }
  }
}

/// Collection of one or more Polygon geometries.
///
/// This allows one stable spatial feature, such as a cultivation area,
/// to consist of multiple geographically separate polygon parts.
class SpatialMultiPolygon {
  SpatialMultiPolygon._(List<SpatialPolygon> polygons)
    : polygons = UnmodifiableListView(polygons);

  factory SpatialMultiPolygon.fromPolygons(Iterable<SpatialPolygon> input) {
    final polygons = List<SpatialPolygon>.of(input);

    if (polygons.isEmpty) {
      throw const FormatException(
        'Spatial MultiPolygon must contain at least one Polygon.',
      );
    }

    for (final polygon in polygons) {
      polygon.validate();
    }

    return SpatialMultiPolygon._(polygons);
  }

  final UnmodifiableListView<SpatialPolygon> polygons;

  SpatialGeometryType get geometryType => SpatialGeometryType.multiPolygon;

  void validate() {
    if (polygons.isEmpty) {
      throw const FormatException(
        'Spatial MultiPolygon must contain at least one Polygon.',
      );
    }

    for (final polygon in polygons) {
      polygon.validate();
    }
  }
}
