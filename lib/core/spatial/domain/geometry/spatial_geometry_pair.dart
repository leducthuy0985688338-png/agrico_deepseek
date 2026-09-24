import '../entities/spatial_feature.dart';
import '../entities/spatial_feature_revision.dart';
import 'spatial_geometry.dart';
import 'spatial_linear_geometry.dart';
import 'spatial_multi_geometry.dart';
import 'spatial_polygon.dart';

/// Validates a *new write*; legacy records may still be read with a reference
/// in place of concrete revision geometry.
void validateSpatialGeometryPair(
  SpatialFeature feature,
  SpatialFeatureRevision revision,
) {
  revision.validateAgainstFeature(feature);
  if (!_equivalent(feature.geometry, revision.geometry)) {
    throw const FormatException(
      'Spatial feature and new revision geometry must match.',
    );
  }
}

bool _equivalent(SpatialGeometry? a, SpatialGeometry? b) {
  if (a == null || b == null) return a == null && b == null;
  if (a.geometryType != b.geometryType) return false;
  if (a is SpatialPoint && b is SpatialPoint) {
    return a.coordinate == b.coordinate;
  }
  if (a is SpatialLineString && b is SpatialLineString) {
    return _sequence(a.coordinates, b.coordinates);
  }
  if (a is SpatialPolygon && b is SpatialPolygon) {
    return _sequence(a.outerRing, b.outerRing);
  }
  if (a is SpatialMultiPoint && b is SpatialMultiPoint) {
    return _sequence(a.points, b.points, _equivalent);
  }
  if (a is SpatialMultiLineString && b is SpatialMultiLineString) {
    return _sequence(a.lineStrings, b.lineStrings, _equivalent);
  }
  if (a is SpatialMultiPolygon && b is SpatialMultiPolygon) {
    return _sequence(a.polygons, b.polygons, _equivalent);
  }
  return false;
}

bool _sequence<T>(List<T> a, List<T> b, [bool Function(T, T)? equal]) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!(equal?.call(a[i], b[i]) ?? a[i] == b[i])) return false;
  }
  return true;
}
