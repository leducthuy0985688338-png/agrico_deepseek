import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SpatialFeatureRevision buildRevision({
    required SpatialGeometryType geometryType,
    SpatialGeometry? geometry,
    String? geometryReference,
  }) {
    return SpatialFeatureRevision(
      id: 'revision-1',
      featureId: 'feature-1',
      revision: 1,
      geometryType: geometryType,
      geometry: geometry,
      geometryReference: geometryReference,
      temporalState: SpatialTemporalState.baseline,
      effectivePeriod: SpatialEffectivePeriod(
        validFrom: DateTime.utc(2026, 1, 1),
      ),
      source: const SpatialSource(type: SpatialSourceType.survey),
      createdAt: DateTime.utc(2026, 1, 1),
      createdBy: 'tester',
    );
  }

  group('SpatialFeatureRevision geometry payload', () {
    test('accepts concrete geometry matching geometryType', () {
      final revision = buildRevision(
        geometryType: SpatialGeometryType.point,
        geometry: const SpatialPoint(
          coordinate: SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        ),
      );

      revision.validate();

      expect(revision.geometry, isA<SpatialPoint>());
    });

    test('rejects concrete geometry that does not match geometryType', () {
      final revision = buildRevision(
        geometryType: SpatialGeometryType.lineString,
        geometry: const SpatialPoint(
          coordinate: SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        ),
      );

      expect(revision.validate, throwsFormatException);
    });

    test('keeps migration compatibility with geometryReference only', () {
      final revision = buildRevision(
        geometryType: SpatialGeometryType.polygon,
        geometryReference: 'legacy-geometry-1',
      );

      expect(revision.validate, returnsNormally);
      expect(revision.geometry, isNull);
    });

    test('keeps compatibility with metadata-only legacy revision', () {
      final revision = buildRevision(geometryType: SpatialGeometryType.polygon);

      expect(revision.validate, returnsNormally);
      expect(revision.geometry, isNull);
      expect(revision.geometryReference, isNull);
    });
  });
}
