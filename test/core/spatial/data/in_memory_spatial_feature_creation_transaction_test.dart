import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_creation_transaction.dart';
import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_repository.dart';
import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_revision_repository.dart';
import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_store.dart';
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

  SpatialFeature buildFeature({String id = 'parcel-1', bool noGeometry = false}) {
    return SpatialFeature(
      id: id,
      featureType: SpatialFeatureTypes.landParcel,
      geometryType: SpatialGeometryType.polygon,
      geometry: noGeometry ? null : SpatialPolygon.fromOuterRing(const [
        SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        SpatialCoordinate(latitude: 16.5, longitude: 104.8),
        SpatialCoordinate(latitude: 16.6, longitude: 104.8),
        SpatialCoordinate(latitude: 16.6, longitude: 104.7),
      ]),
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
    bool noGeometry = false,
  }) {
    return SpatialFeatureRevision(
      id: id,
      featureId: featureId,
      revision: revision,
      geometryType: SpatialGeometryType.polygon,
      geometry: noGeometry ? null : SpatialPolygon.fromOuterRing(const [
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
    test('rejects one-null pair before changing store', () async {
      final store = InMemorySpatialStore();
      final transaction = InMemorySpatialFeatureCreationTransaction(store: store);
      await expectLater(
        transaction.create(feature: buildFeature(), initialRevision: buildRevision(noGeometry: true)),
        throwsFormatException,
      );
      expect(await InMemorySpatialFeatureRepository(store: store).findById('parcel-1'), isNull);
      expect(await InMemorySpatialFeatureRevisionRepository(store: store).findByFeatureId('parcel-1'), isEmpty);
    });

    test('accepts null/null pair', () async {
      final store = InMemorySpatialStore();
      await InMemorySpatialFeatureCreationTransaction(store: store).create(
        feature: buildFeature(noGeometry: true),
        initialRevision: buildRevision(noGeometry: true),
      );
      expect(await InMemorySpatialFeatureRepository(store: store).findById('parcel-1'), isNotNull);
    });
    test('creates feature and initial revision together', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );

      final transaction = InMemorySpatialFeatureCreationTransaction(
        store: store,
      );

      final feature = buildFeature();
      final revision = buildRevision();

      await transaction.create(feature: feature, initialRevision: revision);

      expect(await featureRepository.findById(feature.id), same(feature));
      expect(await revisionRepository.findById(revision.id), same(revision));
      expect(
        await revisionRepository.findByFeatureId(feature.id),
        hasLength(1),
      );
    });

    test('duplicate feature is rejected without creating revision', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );

      final existingFeature = buildFeature();
      await featureRepository.create(existingFeature);

      final transaction = InMemorySpatialFeatureCreationTransaction(
        store: store,
      );

      await expectLater(
        transaction.create(
          feature: buildFeature(),
          initialRevision: buildRevision(),
        ),
        throwsStateError,
      );

      expect(await revisionRepository.findByFeatureId('parcel-1'), isEmpty);
      expect(
        await featureRepository.findById('parcel-1'),
        same(existingFeature),
      );
    });

    test('existing revision id is rejected without creating feature', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );

      await revisionRepository.create(
        buildRevision(id: 'shared-revision-id', featureId: 'other-parcel'),
      );

      final transaction = InMemorySpatialFeatureCreationTransaction(
        store: store,
      );

      await expectLater(
        transaction.create(
          feature: buildFeature(),
          initialRevision: buildRevision(id: 'shared-revision-id'),
        ),
        throwsStateError,
      );

      expect(await featureRepository.findById('parcel-1'), isNull);
      expect(
        await revisionRepository.findById('shared-revision-id'),
        isNotNull,
      );
    });

    test(
      'existing feature revision history prevents feature creation',
      () async {
        final store = InMemorySpatialStore();
        final featureRepository = InMemorySpatialFeatureRepository(
          store: store,
        );
        final revisionRepository = InMemorySpatialFeatureRevisionRepository(
          store: store,
        );

        final existingRevision = buildRevision();
        await revisionRepository.create(existingRevision);

        final transaction = InMemorySpatialFeatureCreationTransaction(
          store: store,
        );

        await expectLater(
          transaction.create(
            feature: buildFeature(),
            initialRevision: buildRevision(id: 'parcel-1-another-revision'),
          ),
          throwsStateError,
        );

        expect(await featureRepository.findById('parcel-1'), isNull);
        expect(
          await revisionRepository.findByFeatureId('parcel-1'),
          hasLength(1),
        );
        expect(
          await revisionRepository.findById(existingRevision.id),
          same(existingRevision),
        );
      },
    );

    test('failed staged revision leaves original store unchanged', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );

      final unrelatedFeature = buildFeature(id: 'parcel-existing');
      await featureRepository.create(unrelatedFeature);

      final conflictingRevision = buildRevision(
        id: 'shared-revision-id',
        featureId: 'parcel-existing',
      );
      await revisionRepository.create(conflictingRevision);

      final transaction = InMemorySpatialFeatureCreationTransaction(
        store: store,
      );

      await expectLater(
        transaction.create(
          feature: buildFeature(),
          initialRevision: buildRevision(id: 'shared-revision-id'),
        ),
        throwsStateError,
      );

      expect(await featureRepository.findById('parcel-1'), isNull);
      expect(
        await featureRepository.findById('parcel-existing'),
        same(unrelatedFeature),
      );
      expect(
        await revisionRepository.findById('shared-revision-id'),
        same(conflictingRevision),
      );
      expect(
        await revisionRepository.findByFeatureId('parcel-existing'),
        hasLength(1),
      );
    });
  });
}
