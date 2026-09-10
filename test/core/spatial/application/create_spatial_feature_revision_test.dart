import 'package:agrico_deepseek/core/spatial/application/create_spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_revision_repository.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);

  SpatialFeature buildFeature({
    String id = 'parcel-1',
    SpatialGeometryType geometryType = SpatialGeometryType.polygon,
  }) {
    return SpatialFeature(
      id: id,
      featureType: SpatialFeatureTypes.landParcel,
      geometryType: geometryType,
      lifecycleStatus: SpatialFeatureLifecycleStatus.existing,
      createdAt: createdAt,
      createdBy: 'user-1',
      updatedAt: createdAt,
      updatedBy: 'user-1',
    );
  }

  SpatialFeatureRevision buildPolygonRevision({
    String id = 'parcel-1-revision-1',
    String featureId = 'parcel-1',
    int revision = 1,
  }) {
    return SpatialFeatureRevision(
      id: id,
      featureId: featureId,
      revision: revision,
      geometryType: SpatialGeometryType.polygon,
      geometry: SpatialPolygon.fromOuterRing(const [
        SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        SpatialCoordinate(latitude: 16.5, longitude: 104.8),
        SpatialCoordinate(latitude: 16.6, longitude: 104.8),
        SpatialCoordinate(latitude: 16.6, longitude: 104.7),
      ]),
      temporalState: SpatialTemporalState.baseline,
      effectivePeriod: SpatialEffectivePeriod(validFrom: createdAt),
      source: const SpatialSource(type: SpatialSourceType.survey),
      createdAt: createdAt,
      createdBy: 'user-1',
    );
  }

  group('CreateSpatialFeatureRevision', () {
    test('stores a revision that matches its feature', () {
      final repository = InMemorySpatialFeatureRevisionRepository();
      final useCase = CreateSpatialFeatureRevision(repository);
      final feature = buildFeature();
      final revision = buildPolygonRevision();

      useCase.execute(feature: feature, revision: revision);

      expect(repository.findById(revision.id), same(revision));
      expect(repository.findLatestByFeatureId(feature.id), same(revision));
    });

    test('rejects revision belonging to another feature', () {
      final repository = InMemorySpatialFeatureRevisionRepository();
      final useCase = CreateSpatialFeatureRevision(repository);
      final feature = buildFeature();
      final revision = buildPolygonRevision(featureId: 'parcel-2');

      expect(
        () => useCase.execute(feature: feature, revision: revision),
        throwsFormatException,
      );

      expect(repository.findById(revision.id), isNull);
    });

    test('rejects revision geometry type different from feature', () {
      final repository = InMemorySpatialFeatureRevisionRepository();
      final useCase = CreateSpatialFeatureRevision(repository);
      final feature = buildFeature();

      final revision = SpatialFeatureRevision(
        id: 'parcel-1-revision-1',
        featureId: feature.id,
        revision: 1,
        geometryType: SpatialGeometryType.lineString,
        geometry: SpatialLineString.fromCoordinates(const [
          SpatialCoordinate(latitude: 16.5, longitude: 104.7),
          SpatialCoordinate(latitude: 16.6, longitude: 104.8),
        ]),
        temporalState: SpatialTemporalState.baseline,
        effectivePeriod: SpatialEffectivePeriod(validFrom: createdAt),
        source: const SpatialSource(type: SpatialSourceType.survey),
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      expect(
        () => useCase.execute(feature: feature, revision: revision),
        throwsFormatException,
      );

      expect(repository.findById(revision.id), isNull);
    });

    test('rejects invalid revision before repository storage', () {
      final repository = InMemorySpatialFeatureRevisionRepository();
      final useCase = CreateSpatialFeatureRevision(repository);
      final feature = buildFeature();

      final revision = buildPolygonRevision(
        id: 'invalid-revision',
        featureId: '',
      );

      expect(
        () => useCase.execute(feature: feature, revision: revision),
        throwsFormatException,
      );

      expect(repository.findById('invalid-revision'), isNull);
    });

    test('repository still enforces duplicate revision identity', () {
      final repository = InMemorySpatialFeatureRevisionRepository();
      final useCase = CreateSpatialFeatureRevision(repository);
      final feature = buildFeature();

      useCase.execute(
        feature: feature,
        revision: buildPolygonRevision(id: 'revision-a'),
      );

      expect(
        () => useCase.execute(
          feature: feature,
          revision: buildPolygonRevision(id: 'revision-b'),
        ),
        throwsStateError,
      );

      expect(repository.findByFeatureId(feature.id), hasLength(1));
    });
  });
}
