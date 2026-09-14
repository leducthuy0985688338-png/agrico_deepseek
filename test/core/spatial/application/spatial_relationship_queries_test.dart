import 'package:agrico_deepseek/core/spatial/application/spatial_relationship_queries.dart';
import 'package:agrico_deepseek/core/spatial/data/spatial_relationship_repository.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_relationship.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 14);

  SpatialRelationship relationship({
    String id = 'rel-1',
    String source = 'feature-1',
    String target = 'feature-2',
    String type = 'serves',
  }) {
    return SpatialRelationship(
      id: id,
      sourceFeatureId: source,
      targetFeatureId: target,
      relationshipType: type,
      createdAt: createdAt,
      createdBy: 'user-1',
    );
  }

  SpatialRelationshipQueries queries(
    FakeSpatialRelationshipRepository repository,
  ) {
    return SpatialRelationshipQueries(repository: repository);
  }

  test('gets relationship by stable relationship id', () async {
    final repository = FakeSpatialRelationshipRepository([relationship()]);

    final result = await queries(repository).getRelationship('rel-1');

    expect(result, isNotNull);
    expect(result!.id, 'rel-1');
    expect(result.sourceFeatureId, 'feature-1');
    expect(result.targetFeatureId, 'feature-2');
  });

  test('returns null when relationship does not exist', () async {
    final repository = FakeSpatialRelationshipRepository();

    final result = await queries(repository).getRelationship('missing');

    expect(result, isNull);
  });

  test('gets outgoing relationships', () async {
    final repository = FakeSpatialRelationshipRepository([
      relationship(id: 'rel-1', source: 'feature-1', target: 'feature-2'),
      relationship(id: 'rel-2', source: 'feature-1', target: 'feature-3'),
      relationship(id: 'rel-3', source: 'feature-9', target: 'feature-1'),
    ]);

    final result = await queries(
      repository,
    ).getOutgoingRelationships('feature-1');

    expect(result.map((item) => item.id), ['rel-1', 'rel-2']);
  });

  test('gets incoming relationships', () async {
    final repository = FakeSpatialRelationshipRepository([
      relationship(id: 'rel-1', source: 'feature-1', target: 'feature-3'),
      relationship(id: 'rel-2', source: 'feature-2', target: 'feature-3'),
      relationship(id: 'rel-3', source: 'feature-3', target: 'feature-4'),
    ]);

    final result = await queries(
      repository,
    ).getIncomingRelationships('feature-3');

    expect(result.map((item) => item.id), ['rel-1', 'rel-2']);
  });

  test('gets directed relationships between two features', () async {
    final repository = FakeSpatialRelationshipRepository([
      relationship(id: 'rel-1', source: 'feature-1', target: 'feature-2'),
      relationship(id: 'rel-2', source: 'feature-2', target: 'feature-1'),
      relationship(id: 'rel-3', source: 'feature-1', target: 'feature-3'),
    ]);

    final result = await queries(
      repository,
    ).getRelationshipsBetween('feature-1', 'feature-2');

    expect(result.map((item) => item.id), ['rel-1']);
  });

  test('gets relationships by type', () async {
    final repository = FakeSpatialRelationshipRepository([
      relationship(id: 'rel-1', type: 'serves'),
      relationship(id: 'rel-2', type: 'crosses'),
      relationship(id: 'rel-3', type: 'serves'),
    ]);

    final result = await queries(repository).getRelationshipsByType('serves');

    expect(result.map((item) => item.id), ['rel-1', 'rel-3']);
  });

  test('lists all relationships', () async {
    final repository = FakeSpatialRelationshipRepository([
      relationship(id: 'rel-1'),
      relationship(id: 'rel-2'),
      relationship(id: 'rel-3'),
    ]);

    final result = await queries(repository).listRelationships();

    expect(result, hasLength(3));
  });

  test('rejects blank relationship id', () async {
    final repository = FakeSpatialRelationshipRepository();

    expect(
      () => queries(repository).getRelationship('   '),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects blank source feature id', () async {
    final repository = FakeSpatialRelationshipRepository();

    expect(
      () => queries(repository).getOutgoingRelationships('   '),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects blank relationship type', () async {
    final repository = FakeSpatialRelationshipRepository();

    expect(
      () => queries(repository).getRelationshipsByType('   '),
      throwsA(isA<FormatException>()),
    );
  });

  test('relationship validation rejects self relationship', () {
    final item = relationship(source: 'feature-1', target: 'feature-1');

    expect(item.validate, throwsA(isA<FormatException>()));
  });
}

class FakeSpatialRelationshipRepository
    implements SpatialRelationshipRepository {
  FakeSpatialRelationshipRepository([
    List<SpatialRelationship> relationships = const [],
  ]) : _relationships = List<SpatialRelationship>.of(relationships);

  final List<SpatialRelationship> _relationships;

  @override
  Future<SpatialRelationship?> findById(String id) async {
    for (final relationship in _relationships) {
      if (relationship.id == id) {
        return relationship;
      }
    }
    return null;
  }

  @override
  Future<List<SpatialRelationship>> findBySourceFeatureId(
    String sourceFeatureId,
  ) async {
    return _relationships
        .where(
          (relationship) => relationship.sourceFeatureId == sourceFeatureId,
        )
        .toList();
  }

  @override
  Future<List<SpatialRelationship>> findByTargetFeatureId(
    String targetFeatureId,
  ) async {
    return _relationships
        .where(
          (relationship) => relationship.targetFeatureId == targetFeatureId,
        )
        .toList();
  }

  @override
  Future<List<SpatialRelationship>> findBetweenFeatures({
    required String sourceFeatureId,
    required String targetFeatureId,
  }) async {
    return _relationships
        .where(
          (relationship) =>
              relationship.sourceFeatureId == sourceFeatureId &&
              relationship.targetFeatureId == targetFeatureId,
        )
        .toList();
  }

  @override
  Future<List<SpatialRelationship>> findByRelationshipType(
    String relationshipType,
  ) async {
    return _relationships
        .where(
          (relationship) => relationship.relationshipType == relationshipType,
        )
        .toList();
  }

  @override
  Future<List<SpatialRelationship>> findAll() async {
    return List<SpatialRelationship>.of(_relationships);
  }

  @override
  Future<void> create(SpatialRelationship relationship) async {
    relationship.validate();

    if (_relationships.any((item) => item.id == relationship.id)) {
      throw StateError(
        'Spatial relationship ${relationship.id} already exists.',
      );
    }

    _relationships.add(relationship);
  }
}
