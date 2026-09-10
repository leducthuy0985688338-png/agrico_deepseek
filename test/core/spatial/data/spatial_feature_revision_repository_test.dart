import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_revision_repository.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);

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

  group('InMemorySpatialFeatureRevisionRepository', () {
    test('starts empty', () {
      final repository = InMemorySpatialFeatureRevisionRepository();

      expect(repository.findById('missing'), isNull);
      expect(repository.findByFeatureId('parcel-1'), isEmpty);
      expect(repository.findLatestByFeatureId('parcel-1'), isNull);
    });

    test('creates and retrieves revision by id', () {
      final repository = InMemorySpatialFeatureRevisionRepository();
      final revision = buildRevision();

      repository.create(revision);

      expect(repository.findById(revision.id), same(revision));
    });

    test('finds revisions belonging to one feature', () {
      final repository = InMemorySpatialFeatureRevisionRepository();

      final parcel1Revision1 = buildRevision();
      final parcel1Revision2 = buildRevision(
        id: 'parcel-1-revision-2',
        revision: 2,
      );
      final parcel2Revision1 = buildRevision(
        id: 'parcel-2-revision-1',
        featureId: 'parcel-2',
      );

      repository.create(parcel1Revision1);
      repository.create(parcel1Revision2);
      repository.create(parcel2Revision1);

      final revisions = repository.findByFeatureId('parcel-1');

      expect(revisions, hasLength(2));
      expect(revisions[0], same(parcel1Revision1));
      expect(revisions[1], same(parcel1Revision2));
    });

    test('sorts feature revisions by revision number', () {
      final repository = InMemorySpatialFeatureRevisionRepository();

      final revision3 = buildRevision(id: 'parcel-1-revision-3', revision: 3);
      final revision1 = buildRevision(id: 'parcel-1-revision-1', revision: 1);
      final revision2 = buildRevision(id: 'parcel-1-revision-2', revision: 2);

      repository.create(revision3);
      repository.create(revision1);
      repository.create(revision2);

      final revisions = repository.findByFeatureId('parcel-1');

      expect(revisions.map((revision) => revision.revision), [1, 2, 3]);
    });

    test('finds latest revision regardless of insertion order', () {
      final repository = InMemorySpatialFeatureRevisionRepository();

      final revision3 = buildRevision(id: 'parcel-1-revision-3', revision: 3);
      final revision1 = buildRevision(id: 'parcel-1-revision-1', revision: 1);
      final revision2 = buildRevision(id: 'parcel-1-revision-2', revision: 2);

      repository.create(revision3);
      repository.create(revision1);
      repository.create(revision2);

      expect(repository.findLatestByFeatureId('parcel-1'), same(revision3));
    });

    test('rejects duplicate revision id', () {
      final repository = InMemorySpatialFeatureRevisionRepository();
      final revision = buildRevision();

      repository.create(revision);

      expect(() => repository.create(revision), throwsStateError);
    });

    test('rejects duplicate feature revision identity', () {
      final repository = InMemorySpatialFeatureRevisionRepository();

      repository.create(buildRevision(id: 'revision-a'));

      expect(
        () => repository.create(buildRevision(id: 'revision-b')),
        throwsStateError,
      );
    });

    test('allows same revision number for different features', () {
      final repository = InMemorySpatialFeatureRevisionRepository();

      final parcel1 = buildRevision(
        id: 'parcel-1-revision-1',
        featureId: 'parcel-1',
      );
      final parcel2 = buildRevision(
        id: 'parcel-2-revision-1',
        featureId: 'parcel-2',
      );

      repository.create(parcel1);
      repository.create(parcel2);

      expect(repository.findByFeatureId('parcel-1'), [parcel1]);
      expect(repository.findByFeatureId('parcel-2'), [parcel2]);
    });

    test('validates revision before storing it', () {
      final repository = InMemorySpatialFeatureRevisionRepository();

      final invalid = buildRevision(id: 'invalid', featureId: '');

      expect(() => repository.create(invalid), throwsFormatException);
      expect(repository.findById('invalid'), isNull);
    });

    test('returns an unmodifiable revision list', () {
      final repository = InMemorySpatialFeatureRevisionRepository();
      repository.create(buildRevision());

      final revisions = repository.findByFeatureId('parcel-1');

      expect(
        () => revisions.add(
          buildRevision(id: 'parcel-1-revision-2', revision: 2),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
