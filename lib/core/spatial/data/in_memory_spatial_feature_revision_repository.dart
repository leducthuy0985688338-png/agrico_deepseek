import '../domain/entities/spatial_feature_revision.dart';
import 'in_memory_spatial_store.dart';
import 'spatial_feature_revision_repository.dart';

class InMemorySpatialFeatureRevisionRepository
    implements SpatialFeatureRevisionRepository {
  InMemorySpatialFeatureRevisionRepository({InMemorySpatialStore? store})
    : _store = store ?? InMemorySpatialStore();

  final InMemorySpatialStore _store;

  @override
  Future<SpatialFeatureRevision?> findById(String id) async {
    return _store.findRevisionById(id);
  }

  @override
  Future<List<SpatialFeatureRevision>> findByFeatureId(String featureId) async {
    final revisions =
        _store.revisions
            .where((revision) => revision.featureId == featureId)
            .toList()
          ..sort((a, b) => a.revision.compareTo(b.revision));

    return List<SpatialFeatureRevision>.unmodifiable(revisions);
  }

  @override
  Future<SpatialFeatureRevision?> findLatestByFeatureId(
    String featureId,
  ) async {
    final revisions = await findByFeatureId(featureId);

    if (revisions.isEmpty) {
      return null;
    }

    return revisions.last;
  }

  @override
  Future<void> create(SpatialFeatureRevision revision) async {
    revision.validate();

    if (_store.containsRevision(revision.id)) {
      throw StateError(
        'Spatial feature revision with id "${revision.id}" already exists.',
      );
    }

    final duplicateIdentity = _store.revisions.any(
      (existing) =>
          existing.featureId == revision.featureId &&
          existing.revision == revision.revision,
    );

    if (duplicateIdentity) {
      throw StateError(
        'Spatial feature revision '
        '(${revision.featureId}, ${revision.revision}) already exists.',
      );
    }

    _store.putRevision(revision);
  }
}
