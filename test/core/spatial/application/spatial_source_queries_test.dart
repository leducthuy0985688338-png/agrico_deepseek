import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/core/spatial/application/spatial_source_queries.dart';
import '../../../../lib/core/spatial/domain/repositories/spatial_feature_revision_repository.dart';
import '../../../../lib/core/spatial/domain/entities/spatial_feature_revision.dart';
import '../../../../lib/core/spatial/domain/entities/spatial_source.dart';
import '../../../../lib/core/spatial/domain/entities/spatial_temporal.dart';
import '../../../../lib/core/spatial/domain/geometry/spatial_geometry_type.dart';

void main() {
  group('SpatialSourceQueries', () {
    late FakeSpatialFeatureRevisionRepository repository;
    late SpatialSourceQueries queries;

    setUp(() {
      repository = FakeSpatialFeatureRevisionRepository();
      queries = SpatialSourceQueries(revisionRepository: repository);
    });

    test('gets source from current revision', () async {
      repository.revisions.add(
        _revision(
          id: 'REV-1',
          featureId: 'SPF-1',
          revision: 1,
          source: const SpatialSource(
            type: SpatialSourceType.survey,
            surveyedBy: 'USER-1',
          ),
        ),
      );

      final result = await queries.getCurrentSource('SPF-1');

      expect(result, isNotNull);
      expect(result!.type, SpatialSourceType.survey);
      expect(result.surveyedBy, 'USER-1');
    });

    test('returns null when current revision does not exist', () async {
      final result = await queries.getCurrentSource('SPF-MISSING');

      expect(result, isNull);
    });

    test('gets source from a specific revision', () async {
      repository.revisions.addAll([
        _revision(
          id: 'REV-1',
          featureId: 'SPF-1',
          revision: 1,
          source: const SpatialSource(
            type: SpatialSourceType.gps,
            surveyedBy: 'USER-1',
          ),
        ),
        _revision(
          id: 'REV-2',
          featureId: 'SPF-1',
          revision: 2,
          source: const SpatialSource(
            type: SpatialSourceType.survey,
            surveyedBy: 'USER-2',
          ),
        ),
      ]);

      final result = await queries.getRevisionSource('SPF-1', 2);

      expect(result, isNotNull);
      expect(result!.type, SpatialSourceType.survey);
      expect(result.surveyedBy, 'USER-2');
    });

    test('returns null for missing revision number', () async {
      repository.revisions.add(
        _revision(id: 'REV-1', featureId: 'SPF-1', revision: 1),
      );

      final result = await queries.getRevisionSource('SPF-1', 9);

      expect(result, isNull);
    });

    test('finds revisions by source type', () async {
      repository.revisions.addAll([
        _revision(
          id: 'REV-1',
          featureId: 'SPF-1',
          revision: 1,
          source: const SpatialSource(type: SpatialSourceType.gps),
        ),
        _revision(
          id: 'REV-2',
          featureId: 'SPF-1',
          revision: 2,
          source: const SpatialSource(type: SpatialSourceType.survey),
        ),
        _revision(
          id: 'REV-3',
          featureId: 'SPF-1',
          revision: 3,
          source: const SpatialSource(type: SpatialSourceType.survey),
        ),
      ]);

      final result = await queries.findRevisionsBySourceType(
        'SPF-1',
        SpatialSourceType.survey,
      );

      expect(result, hasLength(2));
      expect(result.map((item) => item.revision), [2, 3]);
    });

    test('finds revisions by surveyor', () async {
      repository.revisions.addAll([
        _revision(
          id: 'REV-1',
          featureId: 'SPF-1',
          revision: 1,
          source: const SpatialSource(
            type: SpatialSourceType.gps,
            surveyedBy: 'USER-1',
          ),
        ),
        _revision(
          id: 'REV-2',
          featureId: 'SPF-1',
          revision: 2,
          source: const SpatialSource(
            type: SpatialSourceType.survey,
            surveyedBy: 'USER-2',
          ),
        ),
        _revision(
          id: 'REV-3',
          featureId: 'SPF-1',
          revision: 3,
          source: const SpatialSource(
            type: SpatialSourceType.survey,
            surveyedBy: 'USER-2',
          ),
        ),
      ]);

      final result = await queries.findRevisionsBySurveyor('SPF-1', 'USER-2');

      expect(result, hasLength(2));
      expect(result.map((item) => item.revision), [2, 3]);
    });

    test('finds revisions between survey dates', () async {
      repository.revisions.addAll([
        _revision(
          id: 'REV-1',
          featureId: 'SPF-1',
          revision: 1,
          source: SpatialSource(
            type: SpatialSourceType.survey,
            surveyedAt: DateTime(2026, 1, 10),
          ),
        ),
        _revision(
          id: 'REV-2',
          featureId: 'SPF-1',
          revision: 2,
          source: SpatialSource(
            type: SpatialSourceType.survey,
            surveyedAt: DateTime(2026, 2, 15),
          ),
        ),
        _revision(
          id: 'REV-3',
          featureId: 'SPF-1',
          revision: 3,
          source: SpatialSource(
            type: SpatialSourceType.survey,
            surveyedAt: DateTime(2026, 3, 20),
          ),
        ),
      ]);

      final result = await queries.findRevisionsBetweenSurveyDates(
        spatialFeatureId: 'SPF-1',
        from: DateTime(2026, 2, 1),
        to: DateTime(2026, 3, 1),
      );

      expect(result, hasLength(1));
      expect(result.single.revision, 2);
    });

    test('ignores revisions without survey date', () async {
      repository.revisions.addAll([
        _revision(
          id: 'REV-1',
          featureId: 'SPF-1',
          revision: 1,
          source: const SpatialSource(type: SpatialSourceType.survey),
        ),
        _revision(
          id: 'REV-2',
          featureId: 'SPF-1',
          revision: 2,
          source: SpatialSource(
            type: SpatialSourceType.survey,
            surveyedAt: DateTime(2026, 2, 15),
          ),
        ),
      ]);

      final result = await queries.findRevisionsBetweenSurveyDates(
        spatialFeatureId: 'SPF-1',
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
      );

      expect(result, hasLength(1));
      expect(result.single.revision, 2);
    });

    test('returns complete revision history in revision order', () async {
      repository.revisions.addAll([
        _revision(id: 'REV-3', featureId: 'SPF-1', revision: 3),
        _revision(id: 'REV-1', featureId: 'SPF-1', revision: 1),
        _revision(id: 'REV-2', featureId: 'SPF-1', revision: 2),
      ]);

      final result = await queries.getRevisionHistory('SPF-1');

      expect(result.map((item) => item.revision), [1, 2, 3]);
    });

    test('preserves stable feature identity across source revisions', () async {
      repository.revisions.addAll([
        _revision(
          id: 'REV-1',
          featureId: 'SPF-STABLE',
          revision: 1,
          source: const SpatialSource(type: SpatialSourceType.gps),
        ),
        _revision(
          id: 'REV-2',
          featureId: 'SPF-STABLE',
          revision: 2,
          source: const SpatialSource(type: SpatialSourceType.survey),
        ),
      ]);

      final history = await queries.getRevisionHistory('SPF-STABLE');

      expect(history, hasLength(2));
      expect(history.map((item) => item.featureId), everyElement('SPF-STABLE'));
      expect(history[0].source.type, SpatialSourceType.gps);
      expect(history[1].source.type, SpatialSourceType.survey);
    });

    test('rejects blank spatial feature id', () async {
      expect(
        () => queries.getCurrentSource('   '),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-positive revision number', () async {
      expect(
        () => queries.getRevisionSource('SPF-1', 0),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects blank surveyor', () async {
      expect(
        () => queries.findRevisionsBySurveyor('SPF-1', '   '),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects invalid survey date range', () async {
      expect(
        () => queries.findRevisionsBetweenSurveyDates(
          spatialFeatureId: 'SPF-1',
          from: DateTime(2026, 12, 31),
          to: DateTime(2026, 1, 1),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

SpatialFeatureRevision _revision({
  required String id,
  required String featureId,
  required int revision,
  SpatialSource source = const SpatialSource(type: SpatialSourceType.manual),
}) {
  return SpatialFeatureRevision(
    id: id,
    featureId: featureId,
    revision: revision,
    geometryType: SpatialGeometryType.polygon,
    temporalState: SpatialTemporalState.baseline,
    effectivePeriod: SpatialEffectivePeriod(validFrom: DateTime(2026, 1, 1)),
    source: source,
    createdAt: DateTime(2026, 1, revision),
    createdBy: 'TEST-USER',
  );
}

class FakeSpatialFeatureRevisionRepository
    implements SpatialFeatureRevisionRepository {
  final List<SpatialFeatureRevision> revisions = <SpatialFeatureRevision>[];

  @override
  Future<SpatialFeatureRevision?> findById(String id) async {
    for (final revision in revisions) {
      if (revision.id == id) {
        return revision;
      }
    }

    return null;
  }

  @override
  Future<List<SpatialFeatureRevision>> findByFeatureId(String featureId) async {
    return revisions
        .where((revision) => revision.featureId == featureId)
        .toList();
  }

  @override
  Future<SpatialFeatureRevision?> findLatestByFeatureId(
    String featureId,
  ) async {
    final matches = revisions
        .where((revision) => revision.featureId == featureId)
        .toList();

    if (matches.isEmpty) {
      return null;
    }

    matches.sort((a, b) => a.revision.compareTo(b.revision));

    return matches.last;
  }

  @override
  Future<void> create(SpatialFeatureRevision revision) async {
    revisions.add(revision);
  }
}
