import 'package:agrico_deepseek/core/spatial/application/spatial_revision_history_queries.dart';
import 'package:agrico_deepseek/core/spatial/data/spatial_feature_revision_repository.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

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

SpatialPoint _point() {
  return const SpatialPoint(
    coordinate: SpatialCoordinate(latitude: 16.5, longitude: 104.7),
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
      validFrom: DateTime.utc(2026, number, 1),
      validTo: DateTime.utc(2027, number, 1),
    ),
    source: SpatialSource(
      type: SpatialSourceType.survey,
      surveyedAt: DateTime.utc(2026, number, 2),
      surveyedBy: 'surveyor-$number',
      horizontalAccuracyM: 0.02,
      sourceReference: 'survey-$number',
    ),
    changeReason: 'Revision $number',
    createdAt: DateTime.utc(2026, number, 3),
    createdBy: 'user-$number',
  );
}

SpatialRevisionHistoryQueries _queries(
  _FakeSpatialFeatureRevisionRepository repository,
) {
  return SpatialRevisionHistoryQueries(revisionRepository: repository);
}

Future<_FakeSpatialFeatureRevisionRepository> _repositoryWithHistory({
  String featureId = 'spatial-1',
}) async {
  final repository = _FakeSpatialFeatureRevisionRepository();

  await repository.create(_revision('revision-3', featureId, 3));
  await repository.create(_revision('revision-1', featureId, 1));
  await repository.create(_revision('revision-2', featureId, 2));

  return repository;
}

void main() {
  group('SpatialRevisionHistoryQueries', () {
    test('returns complete revision history in ascending order', () async {
      final repository = await _repositoryWithHistory();
      final queries = _queries(repository);

      final result = await queries.getRevisionHistory('spatial-1');

      expect(result, hasLength(3));
      expect(result.map((revision) => revision.revision), [1, 2, 3]);
    });

    test('preserves stable feature identity across revisions', () async {
      final repository = await _repositoryWithHistory(
        featureId: 'spatial-stable-1',
      );
      final queries = _queries(repository);

      final result = await queries.getRevisionHistory('spatial-stable-1');

      expect(
        result.every((revision) => revision.featureId == 'spatial-stable-1'),
        isTrue,
      );
    });

    test('returns a specific revision by revision number', () async {
      final repository = await _repositoryWithHistory();
      final queries = _queries(repository);

      final result = await queries.getRevision('spatial-1', 2);

      expect(result, isNotNull);
      expect(result!.id, 'revision-2');
      expect(result.revision, 2);
    });

    test('returns null when requested revision does not exist', () async {
      final repository = await _repositoryWithHistory();
      final queries = _queries(repository);

      final result = await queries.getRevision('spatial-1', 99);

      expect(result, isNull);
    });

    test('returns latest revision as current revision', () async {
      final repository = await _repositoryWithHistory();
      final queries = _queries(repository);

      final result = await queries.getCurrentRevision('spatial-1');

      expect(result, isNotNull);
      expect(result!.id, 'revision-3');
      expect(result.revision, 3);
    });

    test('returns null when feature has no revision history', () async {
      final repository = _FakeSpatialFeatureRevisionRepository();
      final queries = _queries(repository);

      final result = await queries.getCurrentRevision('missing');

      expect(result, isNull);
    });

    test('returns previous revision', () async {
      final repository = await _repositoryWithHistory();
      final queries = _queries(repository);

      final result = await queries.getPreviousRevision('spatial-1', 3);

      expect(result, isNotNull);
      expect(result!.id, 'revision-2');
      expect(result.revision, 2);
    });

    test('returns null because R1 has no previous revision', () async {
      final repository = await _repositoryWithHistory();
      final queries = _queries(repository);

      final result = await queries.getPreviousRevision('spatial-1', 1);

      expect(result, isNull);
    });

    test('rejects blank SpatialFeature id', () {
      final repository = _FakeSpatialFeatureRevisionRepository();
      final queries = _queries(repository);

      expect(
        () => queries.getRevisionHistory('   '),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-positive revision number', () {
      final repository = _FakeSpatialFeatureRevisionRepository();
      final queries = _queries(repository);

      expect(
        () => queries.getRevision('spatial-1', 0),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
