import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_pair.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_multi_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a = SpatialCoordinate(latitude: 1, longitude: 1);
  const b = SpatialCoordinate(latitude: 1, longitude: 2);
  const c = SpatialCoordinate(latitude: 2, longitude: 1);
  const d = SpatialCoordinate(latitude: 2, longitude: 2);
  final time = DateTime.utc(2026);

  SpatialFeature feature(SpatialGeometry? geometry, SpatialGeometry typed) =>
      SpatialFeature(
        id: 'f',
        featureType: SpatialFeatureTypes.landParcel,
        geometryType: typed.geometryType,
        geometry: geometry,
        lifecycleStatus: SpatialFeatureLifecycleStatus.active,
        createdAt: time,
        createdBy: 'user',
        updatedAt: time,
        updatedBy: 'user',
      );

  SpatialFeatureRevision revision(SpatialGeometry? geometry, SpatialGeometry typed) =>
      SpatialFeatureRevision(
        id: 'r',
        featureId: 'f',
        revision: 1,
        geometryType: typed.geometryType,
        geometry: geometry,
        temporalState: SpatialTemporalState.baseline,
        effectivePeriod: SpatialEffectivePeriod(validFrom: time),
        source: const SpatialSource(type: SpatialSourceType.survey),
        createdAt: time,
        createdBy: 'user',
      );

  test('independent equal instances pass for every geometry type', () {
    final first = <SpatialGeometry>[
      const SpatialPoint(coordinate: a),
      SpatialLineString.fromCoordinates([a, b]),
      SpatialPolygon.fromOuterRing([a, b, c]),
      SpatialMultiPoint.fromPoints([const SpatialPoint(coordinate: a)]),
      SpatialMultiLineString.fromLineStrings([SpatialLineString.fromCoordinates([a, b])]),
      SpatialMultiPolygon.fromPolygons([SpatialPolygon.fromOuterRing([a, b, c])]),
    ];
    final same = <SpatialGeometry>[
      const SpatialPoint(coordinate: a),
      SpatialLineString.fromCoordinates([a, b]),
      SpatialPolygon.fromOuterRing([a, b, c]),
      SpatialMultiPoint.fromPoints([const SpatialPoint(coordinate: a)]),
      SpatialMultiLineString.fromLineStrings([SpatialLineString.fromCoordinates([a, b])]),
      SpatialMultiPolygon.fromPolygons([SpatialPolygon.fromOuterRing([a, b, c])]),
    ];
    final changed = <SpatialGeometry>[
      const SpatialPoint(coordinate: d),
      SpatialLineString.fromCoordinates([a, d]),
      SpatialPolygon.fromOuterRing([a, d, c]),
      SpatialMultiPoint.fromPoints([const SpatialPoint(coordinate: d)]),
      SpatialMultiLineString.fromLineStrings([SpatialLineString.fromCoordinates([a, d])]),
      SpatialMultiPolygon.fromPolygons([SpatialPolygon.fromOuterRing([a, d, c])]),
    ];
    for (var i = 0; i < first.length; i++) {
      expect(() => validateSpatialGeometryPair(feature(first[i], first[i]), revision(same[i], first[i])), returnsNormally);
      expect(() => validateSpatialGeometryPair(feature(first[i], first[i]), revision(changed[i], first[i])), throwsFormatException);
    }
  });

  test('null/null passes and either one-null pair fails', () {
    const point = SpatialPoint(coordinate: a);
    expect(() => validateSpatialGeometryPair(feature(null, point), revision(null, point)), returnsNormally);
    expect(() => validateSpatialGeometryPair(feature(null, point), revision(point, point)), throwsFormatException);
    expect(() => validateSpatialGeometryPair(feature(point, point), revision(null, point)), throwsFormatException);
  });
}
