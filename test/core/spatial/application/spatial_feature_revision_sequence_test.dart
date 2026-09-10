import 'package:agrico_deepseek/core/spatial/application/create_spatial_feature_revision_coordinator.dart';
import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_repository.dart';
import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_revision_repository.dart';
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

  SpatialFeature buildFeature(String id) {
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
    required String featureId,
    required int revision,
  }) {
    return SpatialFeatureRevision(
      id: '$featureId-revision-$revision',
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

  group('Spatial feature revision sequence', () {
    test('new feature accepts revision 1', () async {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      await featureRepository.create(buildFeature('parcel-1'));

      final coordinator = CreateSpatialFeatureRevisionCoordinator(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      await coordinator.execute(
        buildRevision(featureId: 'parcel-1', revision: 1),
      );

      expect(
        (await revisionRepository.findLatestByFeatureId('parcel-1'))?.revision,
        1,
      );
    });

    test('new feature rejects revision greater than 1', () async {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      await featureRepository.create(buildFeature('parcel-1'));

      final coordinator = CreateSpatialFeatureRevisionCoordinator(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      await expectLater(
        coordinator.execute(buildRevision(featureId: 'parcel-1', revision: 2)),
        throwsStateError,
      );

      expect(await revisionRepository.findByFeatureId('parcel-1'), isEmpty);
    });

    test('accepts strictly sequential revisions 1 2 3', () async {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      await featureRepository.create(buildFeature('parcel-1'));

      final coordinator = CreateSpatialFeatureRevisionCoordinator(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      await coordinator.execute(
        buildRevision(featureId: 'parcel-1', revision: 1),
      );
      await coordinator.execute(
        buildRevision(featureId: 'parcel-1', revision: 2),
      );
      await coordinator.execute(
        buildRevision(featureId: 'parcel-1', revision: 3),
      );

      final revisions = await revisionRepository.findByFeatureId('parcel-1');

      expect(revisions.map((item) => item.revision).toList(), [1, 2, 3]);
    });

    test('rejects gap in revision sequence', () async {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      await featureRepository.create(buildFeature('parcel-1'));

      final coordinator = CreateSpatialFeatureRevisionCoordinator(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      await coordinator.execute(
        buildRevision(featureId: 'parcel-1', revision: 1),
      );

      await expectLater(
        coordinator.execute(buildRevision(featureId: 'parcel-1', revision: 3)),
        throwsStateError,
      );

      expect(
        await revisionRepository.findByFeatureId('parcel-1'),
        hasLength(1),
      );
    });

    test('rejects repeated or backward revision', () async {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      await featureRepository.create(buildFeature('parcel-1'));

      final coordinator = CreateSpatialFeatureRevisionCoordinator(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      await coordinator.execute(
        buildRevision(featureId: 'parcel-1', revision: 1),
      );
      await coordinator.execute(
        buildRevision(featureId: 'parcel-1', revision: 2),
      );

      await expectLater(
        coordinator.execute(buildRevision(featureId: 'parcel-1', revision: 1)),
        throwsStateError,
      );

      expect(
        await revisionRepository.findByFeatureId('parcel-1'),
        hasLength(2),
      );
    });

    test('each spatial feature maintains an independent sequence', () async {
      final featureRepository = InMemorySpatialFeatureRepository();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository();

      await featureRepository.create(buildFeature('parcel-1'));
      await featureRepository.create(buildFeature('parcel-2'));

      final coordinator = CreateSpatialFeatureRevisionCoordinator(
        featureRepository: featureRepository,
        revisionRepository: revisionRepository,
      );

      await coordinator.execute(
        buildRevision(featureId: 'parcel-1', revision: 1),
      );
      await coordinator.execute(
        buildRevision(featureId: 'parcel-1', revision: 2),
      );

      await coordinator.execute(
        buildRevision(featureId: 'parcel-2', revision: 1),
      );

      expect(
        (await revisionRepository.findLatestByFeatureId('parcel-1'))?.revision,
        2,
      );
      expect(
        (await revisionRepository.findLatestByFeatureId('parcel-2'))?.revision,
        1,
      );
    });
  });
}
