import 'dart:collection';

import 'spatial_coordinate.dart';
import 'spatial_geometry_type.dart';

/// Point geometry in canonical WGS84 coordinates.
class SpatialPoint {
  const SpatialPoint({required this.coordinate});

  final SpatialCoordinate coordinate;

  SpatialGeometryType get geometryType => SpatialGeometryType.point;

  void validate() {
    coordinate.validate();
  }
}

/// LineString geometry in canonical WGS84 coordinates.
///
/// A valid LineString contains at least two coordinates. The coordinate
/// collection is defensively copied and exposed as an unmodifiable view.
class SpatialLineString {
  SpatialLineString._(List<SpatialCoordinate> coordinates)
    : coordinates = UnmodifiableListView(coordinates);

  factory SpatialLineString.fromCoordinates(Iterable<SpatialCoordinate> input) {
    final coordinates = List<SpatialCoordinate>.of(input);

    if (coordinates.length < 2) {
      throw const FormatException(
        'Spatial LineString must contain at least two coordinates.',
      );
    }

    for (final coordinate in coordinates) {
      coordinate.validate();
    }

    return SpatialLineString._(coordinates);
  }

  final UnmodifiableListView<SpatialCoordinate> coordinates;

  SpatialGeometryType get geometryType => SpatialGeometryType.lineString;

  void validate() {
    if (coordinates.length < 2) {
      throw const FormatException(
        'Spatial LineString must contain at least two coordinates.',
      );
    }

    for (final coordinate in coordinates) {
      coordinate.validate();
    }
  }
}
