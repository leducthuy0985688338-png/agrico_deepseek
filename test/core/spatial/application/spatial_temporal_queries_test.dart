import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/core/spatial/application/spatial_temporal_queries.dart';
import '../../../../lib/core/spatial/data/spatial_temporal_repository.dart';
import '../../../../lib/core/spatial/domain/entities/spatial_temporal_record.dart';

void main() {
  group('SpatialTemporalQueries', () {
    final before = DateTime(2026, 1, 1);
    final change = DateTime(2026, 2, 1);
    final after = DateTime(2026, 3, 1);

    final records = <SpatialTemporalRecord>[
      SpatialTemporalRecord(
        id: 'STR-003',
        spatialFeatureId: 'SPF-001',
        state: SpatialTemporalState.after,
        occurredAt: after,
        recordedBy: 'USER-001',
      ),
      SpatialTemporalRecord(
        id: 'STR-001',
        spatialFeatureId: 'SPF-001',
        state: SpatialTemporalState.before,
        occurredAt: before,
        recordedBy: 'USER-001',
      ),
      SpatialTemporalRecord(
        id: 'STR-002',
        spatialFeatureId: 'SPF-001',
        state: SpatialTemporalState.change,
        occurredAt: change,
        recordedBy: 'USER-001',
      ),
    ];

    test('gets temporal record by stable id', () async {
      final repository = _FakeSpatialTemporalRepository(records);
      final queries = SpatialTemporalQueries(repository: repository);

      final result = await queries.getRecord('STR-002');

      expect(result, isNotNull);
      expect(result!.id, 'STR-002');
      expect(result.spatialFeatureId, 'SPF-001');
      expect(result.state, SpatialTemporalState.change);
    });

    test('returns null for missing temporal record', () async {
      final repository = _FakeSpatialTemporalRepository(records);
      final queries = SpatialTemporalQueries(repository: repository);

      final result = await queries.getRecord('STR-999');

      expect(result, isNull);
    });

    test('returns feature temporal history in chronological order', () async {
      final repository = _FakeSpatialTemporalRepository(records);
      final queries = SpatialTemporalQueries(repository: repository);

      final result = await queries.getFeatureHistory('SPF-001');

      expect(result, hasLength(3));
      expect(result[0].state, SpatialTemporalState.before);
      expect(result[1].state, SpatialTemporalState.change);
      expect(result[2].state, SpatialTemporalState.after);
    });

    test(
      'preserves stable SpatialFeature identity across temporal states',
      () async {
        final repository = _FakeSpatialTemporalRepository(records);
        final queries = SpatialTemporalQueries(repository: repository);

        final result = await queries.getFeatureHistory('SPF-001');

        expect(result.map((record) => record.spatialFeatureId).toSet(), {
          'SPF-001',
        });
      },
    );

    test('returns records by temporal state', () async {
      final repository = _FakeSpatialTemporalRepository(records);
      final queries = SpatialTemporalQueries(repository: repository);

      final result = await queries.getRecordsByState(
        SpatialTemporalState.change,
      );

      expect(result, hasLength(1));
      expect(result.single.id, 'STR-002');
    });

    test('returns records between dates in chronological order', () async {
      final repository = _FakeSpatialTemporalRepository(records);
      final queries = SpatialTemporalQueries(repository: repository);

      final result = await queries.getRecordsBetweenDates(
        from: DateTime(2026, 1, 15),
        to: DateTime(2026, 3, 15),
      );

      expect(result, hasLength(2));
      expect(result[0].id, 'STR-002');
      expect(result[1].id, 'STR-003');
    });

    test('returns all records in chronological order', () async {
      final repository = _FakeSpatialTemporalRepository(records);
      final queries = SpatialTemporalQueries(repository: repository);

      final result = await queries.listRecords();

      expect(result, hasLength(3));
      expect(result.map((record) => record.id), [
        'STR-001',
        'STR-002',
        'STR-003',
      ]);
    });

    test('rejects blank record id', () async {
      final repository = _FakeSpatialTemporalRepository(records);
      final queries = SpatialTemporalQueries(repository: repository);

      expect(() => queries.getRecord('   '), throwsA(isA<FormatException>()));
    });

    test('rejects blank SpatialFeature id', () async {
      final repository = _FakeSpatialTemporalRepository(records);
      final queries = SpatialTemporalQueries(repository: repository);

      expect(
        () => queries.getFeatureHistory('   '),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects invalid date range', () async {
      final repository = _FakeSpatialTemporalRepository(records);
      final queries = SpatialTemporalQueries(repository: repository);

      expect(
        () => queries.getRecordsBetweenDates(
          from: DateTime(2026, 4, 1),
          to: DateTime(2026, 3, 1),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('entity validation rejects blank SpatialFeature id', () {
      final record = SpatialTemporalRecord(
        id: 'STR-001',
        spatialFeatureId: '   ',
        state: SpatialTemporalState.before,
        occurredAt: before,
        recordedBy: 'USER-001',
      );

      expect(record.validate, throwsA(isA<FormatException>()));
    });
  });
}

class _FakeSpatialTemporalRepository implements SpatialTemporalRepository {
  _FakeSpatialTemporalRepository(Iterable<SpatialTemporalRecord> records)
    : _records = List<SpatialTemporalRecord>.of(records);

  final List<SpatialTemporalRecord> _records;

  @override
  Future<SpatialTemporalRecord?> findById(String id) async {
    for (final record in _records) {
      if (record.id == id) {
        return record;
      }
    }

    return null;
  }

  @override
  Future<List<SpatialTemporalRecord>> findBySpatialFeatureId(
    String spatialFeatureId,
  ) async {
    return _records
        .where((record) => record.spatialFeatureId == spatialFeatureId)
        .toList();
  }

  @override
  Future<List<SpatialTemporalRecord>> findByState(
    SpatialTemporalState state,
  ) async {
    return _records.where((record) => record.state == state).toList();
  }

  @override
  Future<List<SpatialTemporalRecord>> findBetweenDates({
    required DateTime from,
    required DateTime to,
  }) async {
    return _records
        .where(
          (record) =>
              !record.occurredAt.isBefore(from) &&
              !record.occurredAt.isAfter(to),
        )
        .toList();
  }

  @override
  Future<List<SpatialTemporalRecord>> findAll() async {
    return List<SpatialTemporalRecord>.of(_records);
  }

  @override
  Future<void> create(SpatialTemporalRecord record) async {
    record.validate();

    if (_records.any((existing) => existing.id == record.id)) {
      throw StateError('Duplicate temporal record id.');
    }

    _records.add(record);
  }
}
