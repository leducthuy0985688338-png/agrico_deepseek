import 'package:agrico_deepseek/core/spatial/application/create_spatial_feature_revision_coordinator.dart';
import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_repository.dart';
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

  group('CreateSpatialFeatureRevisionCoordinator', () {
    test('loads authoritative feature and stores valid revision', () {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      final feature = buildFeature();
      featureRepository.create(feature);

      final coordinator = CreateSpatialFeatureRevisionCoordinator(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      final revision = buildPolygonRevision();

      coordinator.execute(revision);

      expect(revisionRepository.findById(revision.id), same(revision));
      expect(
        revisionRepository.findLatestByFeatureId(feature.id),
        same(revision),
      );
    });

    test('rejects revision when parent feature does not exist', () {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      final coordinator = CreateSpatialFeatureRevisionCoordinator(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      final revision = buildPolygonRevision();

      expect(() => coordinator.execute(revision), throwsStateError);

      expect(revisionRepository.findById(revision.id), isNull);
      expect(revisionRepository.findByFeatureId(revision.featureId), isEmpty);
    });

    test('rejects geometry type mismatch against authoritative feature', () {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      final feature = buildFeature(
        geometryType: SpatialGeometryType.lineString,
      );
      featureRepository.create(feature);

      final coordinator = CreateSpatialFeatureRevisionCoordinator(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      final revision = buildPolygonRevision();

      expect(() => coordinator.execute(revision), throwsFormatException);

      expect(revisionRepository.findById(revision.id), isNull);
    });

    test('rejects invalid revision before storage', () {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      final feature = buildFeature();
      featureRepository.create(feature);

      final coordinator = CreateSpatialFeatureRevisionCoordinator(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      final revision = buildPolygonRevision(
        id: 'invalid-revision',
        revision: 0,
      );

      expect(() => coordinator.execute(revision), throwsFormatException);

      expect(revisionRepository.findById(revision.id), isNull);
    });

    test('repository still rejects duplicate revision identity', () {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      final feature = buildFeature();
      featureRepository.create(feature);

      final coordinator = CreateSpatialFeatureRevisionCoordinator(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      coordinator.execute(buildPolygonRevision(id: 'revision-a'));

      expect(
        () => coordinator.execute(buildPolygonRevision(id: 'revision-b')),
        throwsStateError,
      );

      expect(revisionRepository.findByFeatureId(feature.id), hasLength(1));
    });

    test('accepts line revision when authoritative feature is lineString', () {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      final feature = buildFeature(
        geometryType: SpatialGeometryType.lineString,
      );
      featureRepository.create(feature);

      final coordinator = CreateSpatialFeatureRevisionCoordinator(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      final revision = SpatialFeatureRevision(
        id: 'road-1-revision-1',
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

      coordinator.execute(revision);

      expect(revisionRepository.findById(revision.id), same(revision));
    });
  });
}
