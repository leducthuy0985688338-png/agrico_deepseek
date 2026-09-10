import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_repository.dart';
import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_revision_repository.dart';
import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_revision_update_transaction.dart';
import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_store.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);
  final updatedAt = DateTime.utc(2026, 2, 1);

  SpatialFeature buildFeature({
    String id = 'parcel-1',
    String featureType = SpatialFeatureTypes.landParcel,
    SpatialGeometryType geometryType = SpatialGeometryType.polygon,
    DateTime? creationTime,
    String createdBy = 'user-1',
    SpatialFeatureLifecycleStatus lifecycleStatus =
        SpatialFeatureLifecycleStatus.existing,
    String? name,
    DateTime? updateTime,
    String updatedBy = 'user-1',
  }) {
    final featureCreatedAt = creationTime ?? createdAt;

    return SpatialFeature(
      id: id,
      featureType: featureType,
      geometryType: geometryType,
      lifecycleStatus: lifecycleStatus,
      name: name,
      createdAt: featureCreatedAt,
      createdBy: createdBy,
      updatedAt: updateTime ?? featureCreatedAt,
      updatedBy: updatedBy,
    );
  }

  SpatialFeatureRevision buildRevision({
    String id = '',
    String featureId = 'parcel-1',
    int revision = 1,
    SpatialGeometryType geometryType = SpatialGeometryType.polygon,
    SpatialGeometry? geometry,
  }) {
    final revisionId = id.isEmpty ? '$featureId-revision-$revision' : id;

    return SpatialFeatureRevision(
      id: revisionId,
      featureId: featureId,
      revision: revision,
      geometryType: geometryType,
      geometry:
          geometry ??
          SpatialPolygon.fromOuterRing(const [
            SpatialCoordinate(latitude: 16.5, longitude: 104.7),
            SpatialCoordinate(latitude: 16.5, longitude: 104.8),
            SpatialCoordinate(latitude: 16.6, longitude: 104.8),
            SpatialCoordinate(latitude: 16.6, longitude: 104.7),
          ]),
      temporalState: revision == 1
          ? SpatialTemporalState.baseline
          : SpatialTemporalState.operational,
      effectivePeriod: SpatialEffectivePeriod(
        validFrom: revision == 1 ? createdAt : updatedAt,
      ),
      source: const SpatialSource(type: SpatialSourceType.survey),
      createdAt: revision == 1 ? createdAt : updatedAt,
      createdBy: 'user-1',
    );
  }

  group('InMemorySpatialFeatureRevisionUpdateTransaction', () {
    test('updates feature and appends revision 2 atomically', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );

      final originalFeature = buildFeature();
      final revision1 = buildRevision();

      await featureRepository.create(originalFeature);
      await revisionRepository.create(revision1);

      final transaction = InMemorySpatialFeatureRevisionUpdateTransaction(
        store: store,
      );

      final updatedFeature = buildFeature(
        updateTime: updatedAt,
        updatedBy: 'user-2',
      );
      final revision2 = buildRevision(revision: 2);

      await transaction.update(feature: updatedFeature, revision: revision2);

      expect(
        await featureRepository.findById('parcel-1'),
        same(updatedFeature),
      );
      expect(
        await revisionRepository.findByFeatureId('parcel-1'),
        hasLength(2),
      );
      expect(await revisionRepository.findById(revision1.id), same(revision1));
      expect(await revisionRepository.findById(revision2.id), same(revision2));
    });

    test('rejects featureType mutation without changing state', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );
      final originalFeature = buildFeature();
      final revision1 = buildRevision();
      await featureRepository.create(originalFeature);
      await revisionRepository.create(revision1);
      final transaction = InMemorySpatialFeatureRevisionUpdateTransaction(
        store: store,
      );

      await expectLater(
        transaction.update(
          feature: buildFeature(
            featureType: SpatialFeatureTypes.road,
            updateTime: updatedAt,
          ),
          revision: buildRevision(revision: 2),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('featureType'),
          ),
        ),
      );
      expect(
        await featureRepository.findById(originalFeature.id),
        same(originalFeature),
      );
      expect(
        await revisionRepository.findByFeatureId(originalFeature.id),
        hasLength(1),
      );
      expect(await revisionRepository.findById(revision1.id), same(revision1));
    });

    test('rejects geometryType mutation without changing state', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );
      final originalFeature = buildFeature();
      final revision1 = buildRevision();
      await featureRepository.create(originalFeature);
      await revisionRepository.create(revision1);
      final transaction = InMemorySpatialFeatureRevisionUpdateTransaction(
        store: store,
      );
      final line = SpatialLineString.fromCoordinates(const [
        SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        SpatialCoordinate(latitude: 16.6, longitude: 104.8),
      ]);

      await expectLater(
        transaction.update(
          feature: buildFeature(
            geometryType: SpatialGeometryType.lineString,
            updateTime: updatedAt,
          ),
          revision: buildRevision(
            revision: 2,
            geometryType: SpatialGeometryType.lineString,
            geometry: line,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('geometryType'),
          ),
        ),
      );
      expect(
        await featureRepository.findById(originalFeature.id),
        same(originalFeature),
      );
      expect(
        await revisionRepository.findByFeatureId(originalFeature.id),
        hasLength(1),
      );
      expect(await revisionRepository.findById(revision1.id), same(revision1));
    });

    test('rejects createdAt mutation without changing state', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );
      final originalFeature = buildFeature();
      final revision1 = buildRevision();
      await featureRepository.create(originalFeature);
      await revisionRepository.create(revision1);
      final transaction = InMemorySpatialFeatureRevisionUpdateTransaction(
        store: store,
      );
      final changedCreationTime = createdAt.add(const Duration(days: 1));

      await expectLater(
        transaction.update(
          feature: buildFeature(
            creationTime: changedCreationTime,
            updateTime: updatedAt,
          ),
          revision: buildRevision(revision: 2),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('createdAt'),
          ),
        ),
      );
      expect(
        await featureRepository.findById(originalFeature.id),
        same(originalFeature),
      );
      expect(
        await revisionRepository.findByFeatureId(originalFeature.id),
        hasLength(1),
      );
      expect(await revisionRepository.findById(revision1.id), same(revision1));
    });

    test('rejects createdBy mutation without changing state', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );
      final originalFeature = buildFeature();
      final revision1 = buildRevision();
      await featureRepository.create(originalFeature);
      await revisionRepository.create(revision1);
      final transaction = InMemorySpatialFeatureRevisionUpdateTransaction(
        store: store,
      );

      await expectLater(
        transaction.update(
          feature: buildFeature(createdBy: 'user-2', updateTime: updatedAt),
          revision: buildRevision(revision: 2),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('createdBy'),
          ),
        ),
      );
      expect(
        await featureRepository.findById(originalFeature.id),
        same(originalFeature),
      );
      expect(
        await revisionRepository.findByFeatureId(originalFeature.id),
        hasLength(1),
      );
      expect(await revisionRepository.findById(revision1.id), same(revision1));
    });

    test('allows legitimate mutable snapshot changes', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );
      final originalFeature = buildFeature();
      final revision1 = buildRevision();
      await featureRepository.create(originalFeature);
      await revisionRepository.create(revision1);
      final transaction = InMemorySpatialFeatureRevisionUpdateTransaction(
        store: store,
      );
      final updatedFeature = buildFeature(
        lifecycleStatus: SpatialFeatureLifecycleStatus.inactive,
        name: 'Updated parcel',
        updateTime: updatedAt,
        updatedBy: 'user-2',
      );
      final revision2 = buildRevision(revision: 2);

      await transaction.update(feature: updatedFeature, revision: revision2);

      expect(
        await featureRepository.findById(originalFeature.id),
        same(updatedFeature),
      );
      expect(
        await revisionRepository.findByFeatureId(originalFeature.id),
        hasLength(2),
      );
      expect(await revisionRepository.findById(revision1.id), same(revision1));
      expect(await revisionRepository.findById(revision2.id), same(revision2));
    });

    test('continues sequentially from revision 2 to revision 3', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );

      await featureRepository.create(buildFeature());
      await revisionRepository.create(buildRevision());
      await revisionRepository.create(buildRevision(revision: 2));

      final transaction = InMemorySpatialFeatureRevisionUpdateTransaction(
        store: store,
      );

      final revision3 = buildRevision(revision: 3);

      await transaction.update(
        feature: buildFeature(updateTime: updatedAt, updatedBy: 'user-3'),
        revision: revision3,
      );

      expect(
        await revisionRepository.findByFeatureId('parcel-1'),
        hasLength(3),
      );
      expect(
        await revisionRepository.findLatestByFeatureId('parcel-1'),
        same(revision3),
      );
    });

    test('rejects revision gap without changing state', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );

      final originalFeature = buildFeature();
      final revision1 = buildRevision();

      await featureRepository.create(originalFeature);
      await revisionRepository.create(revision1);

      final transaction = InMemorySpatialFeatureRevisionUpdateTransaction(
        store: store,
      );

      await expectLater(
        transaction.update(
          feature: buildFeature(updateTime: updatedAt, updatedBy: 'user-2'),
          revision: buildRevision(revision: 3),
        ),
        throwsStateError,
      );

      expect(
        await featureRepository.findById('parcel-1'),
        same(originalFeature),
      );
      expect(
        await revisionRepository.findByFeatureId('parcel-1'),
        hasLength(1),
      );
    });

    test('rejects repeated or backward revision', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );

      await featureRepository.create(buildFeature());
      await revisionRepository.create(buildRevision());
      await revisionRepository.create(buildRevision(revision: 2));

      final transaction = InMemorySpatialFeatureRevisionUpdateTransaction(
        store: store,
      );

      await expectLater(
        transaction.update(
          feature: buildFeature(updateTime: updatedAt, updatedBy: 'user-2'),
          revision: buildRevision(
            id: 'parcel-1-repeated-revision-2',
            revision: 2,
          ),
        ),
        throwsStateError,
      );

      expect(
        await revisionRepository.findByFeatureId('parcel-1'),
        hasLength(2),
      );
    });

    test('rejects update when feature does not exist', () async {
      final store = InMemorySpatialStore();
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );

      await revisionRepository.create(buildRevision());

      final transaction = InMemorySpatialFeatureRevisionUpdateTransaction(
        store: store,
      );

      await expectLater(
        transaction.update(
          feature: buildFeature(),
          revision: buildRevision(revision: 2),
        ),
        throwsStateError,
      );

      expect(
        await revisionRepository.findByFeatureId('parcel-1'),
        hasLength(1),
      );
    });

    test('rejects update when feature has no revision history', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);

      final originalFeature = buildFeature();
      await featureRepository.create(originalFeature);

      final transaction = InMemorySpatialFeatureRevisionUpdateTransaction(
        store: store,
      );

      await expectLater(
        transaction.update(
          feature: buildFeature(updateTime: updatedAt, updatedBy: 'user-2'),
          revision: buildRevision(revision: 2),
        ),
        throwsStateError,
      );

      expect(
        await featureRepository.findById('parcel-1'),
        same(originalFeature),
      );
    });

    test('revision conflict leaves original store unchanged', () async {
      final store = InMemorySpatialStore();
      final featureRepository = InMemorySpatialFeatureRepository(store: store);
      final revisionRepository = InMemorySpatialFeatureRevisionRepository(
        store: store,
      );

      final originalFeature = buildFeature();
      final revision1 = buildRevision();

      await featureRepository.create(originalFeature);
      await revisionRepository.create(revision1);

      final conflictingRevision = buildRevision(
        id: 'shared-revision-id',
        featureId: 'other-parcel',
      );
      await revisionRepository.create(conflictingRevision);

      final transaction = InMemorySpatialFeatureRevisionUpdateTransaction(
        store: store,
      );

      await expectLater(
        transaction.update(
          feature: buildFeature(updateTime: updatedAt, updatedBy: 'user-2'),
          revision: buildRevision(id: 'shared-revision-id', revision: 2),
        ),
        throwsStateError,
      );

      expect(
        await featureRepository.findById('parcel-1'),
        same(originalFeature),
      );
      expect(
        await revisionRepository.findByFeatureId('parcel-1'),
        hasLength(1),
      );
      expect(await revisionRepository.findById(revision1.id), same(revision1));
      expect(
        await revisionRepository.findById('shared-revision-id'),
        same(conflictingRevision),
      );
    });
  });
}
