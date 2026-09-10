import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_creation_transaction.dart';
import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_repository.dart';
import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_revision_repository.dart';
import 'package:agrico_deepseek/core/spatial/data/spatial_feature_revision_repository.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);

  SpatialFeature buildFeature({String id = 'parcel-1'}) {
    return SpatialFeature(
      id: id,
      featureType: SpatialFeatureTypes.landParcel,
      geometryType: SpatialGeometryType.polygon,
      lifecycleStatus: SpatialFeatureLifecycleStatus.existing,
      createdAt: createdAt,
      createdBy: 'user-1',
      updatedAt: createdAt,
      updatedBy: 'user-1',
    );
  }

  SpatialFeatureRevision buildRevision({
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

  group('InMemorySpatialFeatureCreationTransaction', () {
    test('creates feature and initial revision together', () {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      final transaction = InMemorySpatialFeatureCreationTransaction(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      final feature = buildFeature();
      final revision = buildRevision();

      transaction.create(feature: feature, initialRevision: revision);

      expect(featureRepository.findById(feature.id), same(feature));
      expect(revisionRepository.findById(revision.id), same(revision));
      expect(revisionRepository.findByFeatureId(feature.id), hasLength(1));
    });

    test('duplicate feature is rejected without creating revision', () {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      final existingFeature = buildFeature();
      featureRepository.create(existingFeature);

      final transaction = InMemorySpatialFeatureCreationTransaction(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      expect(
        () => transaction.create(
          feature: buildFeature(),
          initialRevision: buildRevision(),
        ),
        throwsStateError,
      );

      expect(revisionRepository.findByFeatureId('parcel-1'), isEmpty);
      expect(featureRepository.findById('parcel-1'), same(existingFeature));
    });

    test('existing revision id is rejected without creating feature', () {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      revisionRepository.create(
        buildRevision(id: 'shared-revision-id', featureId: 'other-parcel'),
      );

      final transaction = InMemorySpatialFeatureCreationTransaction(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      expect(
        () => transaction.create(
          feature: buildFeature(),
          initialRevision: buildRevision(id: 'shared-revision-id'),
        ),
        throwsStateError,
      );

      expect(featureRepository.findById('parcel-1'), isNull);
    });

    test('existing feature revision history prevents feature creation', () {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      revisionRepository.create(buildRevision());

      final transaction = InMemorySpatialFeatureCreationTransaction(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      expect(
        () => transaction.create(
          feature: buildFeature(),
          initialRevision: buildRevision(id: 'parcel-1-another-revision'),
        ),
        throwsStateError,
      );

      expect(featureRepository.findById('parcel-1'), isNull);
      expect(revisionRepository.findByFeatureId('parcel-1'), hasLength(1));
    });

    test('rolls back feature when revision creation fails', () {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = _FailingRevisionRepository();

      final transaction = InMemorySpatialFeatureCreationTransaction(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      expect(
        () => transaction.create(
          feature: buildFeature(),
          initialRevision: buildRevision(),
        ),
        throwsStateError,
      );

      expect(featureRepository.findById('parcel-1'), isNull);
      expect(revisionRepository.createCallCount, 1);
      expect(revisionRepository.findByFeatureId('parcel-1'), isEmpty);
    });
  });
}

class _FailingRevisionRepository implements SpatialFeatureRevisionRepository {
  int createCallCount = 0;

  @override
  SpatialFeatureRevision? findById(String id) => null;

  @override
  List<SpatialFeatureRevision> findByFeatureId(String featureId) =>
      const <SpatialFeatureRevision>[];

  @override
  SpatialFeatureRevision? findLatestByFeatureId(String featureId) => null;

  @override
  void create(SpatialFeatureRevision revision) {
    createCallCount += 1;
    throw StateError('Simulated revision persistence failure.');
  }
}
