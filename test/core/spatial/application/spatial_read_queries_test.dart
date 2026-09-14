import 'package:agrico_deepseek/core/spatial/application/spatial_read_queries.dart';
import 'package:agrico_deepseek/core/spatial/data/spatial_feature_repository.dart';
import 'package:agrico_deepseek/core/spatial/data/spatial_feature_revision_repository.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel_spatial_link.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_parcel_spatial_link_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSpatialFeatureRepository implements SpatialFeatureRepository {
  final Map<String, SpatialFeature> features = {};

  @override
  Future<SpatialFeature?> findById(String id) async => features[id];

  @override
  Future<List<SpatialFeature>> findAll() async => features.values.toList();

  @override
  Future<void> create(SpatialFeature feature) async {
    features[feature.id] = feature;
  }

  @override
  Future<void> update(SpatialFeature feature) async {
    features[feature.id] = feature;
  }

  @override
  Future<void> deleteById(String id) async {
    features.remove(id);
  }
}

class _FakeSpatialFeatureRevisionRepository
    implements SpatialFeatureRevisionRepository {
  final Map<String, List<SpatialFeatureRevision>> revisions = {};

  @override
  Future<SpatialFeatureRevision?> findById(String id) async {
    for (final featureRevisions in revisions.values) {
      for (final revision in featureRevisions) {
        if (revision.id == id) {
          return revision;
        }
      }
    }
    return null;
  }

  @override
  Future<List<SpatialFeatureRevision>> findByFeatureId(String featureId) async {
    return List.unmodifiable(revisions[featureId] ?? const []);
  }

  @override
  Future<SpatialFeatureRevision?> findLatestByFeatureId(
    String featureId,
  ) async {
    final featureRevisions = revisions[featureId];

    if (featureRevisions == null || featureRevisions.isEmpty) {
      return null;
    }

    return featureRevisions.reduce(
      (current, candidate) =>
          candidate.revision > current.revision ? candidate : current,
    );
  }

  @override
  Future<void> create(SpatialFeatureRevision revision) async {
    revisions.putIfAbsent(revision.featureId, () => []).add(revision);
  }
}

class _FakeLandParcelSpatialLinkRepository
    implements LandParcelSpatialLinkRepository {
  final Map<String, LandParcelSpatialLink> links = {};

  @override
  Future<LandParcelSpatialLink?> findById(String id) async => links[id];

  @override
  Future<LandParcelSpatialLink?> findByLandParcelId(String landParcelId) async {
    for (final link in links.values) {
      if (link.landParcelId == landParcelId) {
        return link;
      }
    }
    return null;
  }

  @override
  Future<LandParcelSpatialLink?> findBySpatialFeatureId(
    String spatialFeatureId,
  ) async {
    for (final link in links.values) {
      if (link.spatialFeatureId == spatialFeatureId) {
        return link;
      }
    }
    return null;
  }

  @override
  Future<void> create(LandParcelSpatialLink link) async {
    links[link.id] = link;
  }
}

SpatialPoint _point() {
  return const SpatialPoint(
    coordinate: SpatialCoordinate(latitude: 16.5, longitude: 104.7),
  );
}

SpatialFeature _feature(String id) {
  return SpatialFeature(
    id: id,
    featureType: SpatialFeatureTypes.landParcel,
    geometryType: SpatialGeometryType.point,
    geometry: _point(),
    lifecycleStatus: SpatialFeatureLifecycleStatus.active,
    projectId: 'project-1',
    businessUnitId: 'unit-1',
    code: 'parcel-$id',
    name: 'Parcel $id',
    createdAt: DateTime.utc(2026, 1, 1),
    createdBy: 'user-1',
    updatedAt: DateTime.utc(2026, 1, 2),
    updatedBy: 'user-2',
  );
}

SpatialFeatureRevision _revision(String id, String featureId, int number) {
  return SpatialFeatureRevision(
    id: id,
    featureId: featureId,
    revision: number,
    geometryType: SpatialGeometryType.point,
    geometry: _point(),
    geometryReference: 'ref/$id',
    temporalState: SpatialTemporalState.operational,
    effectivePeriod: SpatialEffectivePeriod(
      validFrom: DateTime.utc(2026, 2, 1),
      validTo: DateTime.utc(2027, 2, 1),
    ),
    source: SpatialSource(
      type: SpatialSourceType.survey,
      surveyedAt: DateTime.utc(2026, 1, 15),
      surveyedBy: 'surveyor-1',
      horizontalAccuracyM: 0.02,
      sourceReference: 'survey-1',
    ),
    changeReason: 'Initial survey',
    createdAt: DateTime.utc(2026, 2, 2),
    createdBy: 'user-1',
  );
}

LandParcelSpatialLink _link({
  String id = 'link-1',
  String landParcelId = 'parcel-1',
  String spatialFeatureId = 'spatial-1',
}) {
  return LandParcelSpatialLink(
    id: id,
    landParcelId: landParcelId,
    spatialFeatureId: spatialFeatureId,
    createdAt: DateTime.utc(2026, 1, 1),
    createdBy: 'user-1',
  );
}

SpatialReadQueries _queries({
  _FakeSpatialFeatureRepository? featureRepository,
  _FakeSpatialFeatureRevisionRepository? revisionRepository,
  _FakeLandParcelSpatialLinkRepository? linkRepository,
}) {
  return SpatialReadQueries(
    featureRepository: featureRepository ?? _FakeSpatialFeatureRepository(),
    revisionRepository:
        revisionRepository ?? _FakeSpatialFeatureRevisionRepository(),
    landParcelSpatialLinkRepository:
        linkRepository ?? _FakeLandParcelSpatialLinkRepository(),
  );
}

void main() {
  group('SpatialReadQueries', () {
    test('gets SpatialFeature by stable id', () async {
      final featureRepository = _FakeSpatialFeatureRepository();
      final feature = _feature('spatial-1');

      await featureRepository.create(feature);

      final queries = _queries(featureRepository: featureRepository);

      final result = await queries.getSpatialFeature('spatial-1');

      expect(result, same(feature));
    });

    test('returns null when SpatialFeature does not exist', () async {
      final queries = _queries();

      final result = await queries.getSpatialFeature('missing');

      expect(result, isNull);
    });

    test('gets latest revision as current revision', () async {
      final revisionRepository = _FakeSpatialFeatureRevisionRepository();

      final revision1 = _revision('revision-1', 'spatial-1', 1);
      final revision2 = _revision('revision-2', 'spatial-1', 2);
      final revision3 = _revision('revision-3', 'spatial-1', 3);

      await revisionRepository.create(revision1);
      await revisionRepository.create(revision3);
      await revisionRepository.create(revision2);

      final queries = _queries(revisionRepository: revisionRepository);

      final result = await queries.getCurrentRevision('spatial-1');

      expect(result, same(revision3));
      expect(result!.revision, 3);
    });

    test('returns null when SpatialFeature has no revision', () async {
      final queries = _queries();

      final result = await queries.getCurrentRevision('spatial-1');

      expect(result, isNull);
    });

    test('resolves LandParcel to stable SpatialFeature identity', () async {
      final linkRepository = _FakeLandParcelSpatialLinkRepository();

      await linkRepository.create(
        _link(landParcelId: 'parcel-123', spatialFeatureId: 'spatial-456'),
      );

      final queries = _queries(linkRepository: linkRepository);

      final result = await queries.getLandParcelSpatialIdentity('parcel-123');

      expect(result, isNotNull);
      expect(result!.landParcelId, 'parcel-123');
      expect(result.spatialFeatureId, 'spatial-456');
    });

    test('returns null when LandParcel has no spatial link', () async {
      final queries = _queries();

      final result = await queries.getLandParcelSpatialIdentity(
        'parcel-missing',
      );

      expect(result, isNull);
    });

    test('lists all SpatialFeatures', () async {
      final featureRepository = _FakeSpatialFeatureRepository();

      final feature1 = _feature('spatial-1');
      final feature2 = _feature('spatial-2');

      await featureRepository.create(feature1);
      await featureRepository.create(feature2);

      final queries = _queries(featureRepository: featureRepository);

      final result = await queries.listSpatialFeatures();

      expect(result, hasLength(2));
      expect(
        result.map((feature) => feature.id),
        containsAll(<String>['spatial-1', 'spatial-2']),
      );
    });

    test('finds SpatialFeature by stable identity', () async {
      final featureRepository = _FakeSpatialFeatureRepository();
      final feature = _feature('spatial-stable-1');

      await featureRepository.create(feature);

      final queries = _queries(featureRepository: featureRepository);

      final result = await queries.findSpatialFeatureByIdentity(
        'spatial-stable-1',
      );

      expect(result, same(feature));
    });

    test('rejects blank SpatialFeature id', () {
      final queries = _queries();

      expect(
        () => queries.getSpatialFeature('   '),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects blank LandParcel id', () {
      final queries = _queries();

      expect(
        () => queries.getLandParcelSpatialIdentity('   '),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
