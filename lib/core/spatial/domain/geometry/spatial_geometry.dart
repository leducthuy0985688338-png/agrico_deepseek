import 'spatial_geometry_type.dart';

/// Common contract for every concrete geometry owned by Spatial Core.
///
/// Concrete geometry implementations remain responsible for validating their
/// own topology and coordinate invariants.
abstract interface class SpatialGeometry {
  SpatialGeometryType get geometryType;

  void validate();
}
