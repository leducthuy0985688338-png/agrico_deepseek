import '../domain/entities/spatial_feature_revision.dart';
import 'spatial_feature_revision_repository.dart';

class InMemorySpatialFeatureRevisionRepository
    implements SpatialFeatureRevisionRepository {
  final Map<String, SpatialFeatureRevision> _revisions =
      <String, SpatialFeatureRevision>{};

  @override
  SpatialFeatureRevision? findById(String id) {
    return _revisions[id];
  }

  @override
  List<SpatialFeatureRevision> findByFeatureId(String featureId) {
    final revisions =
        _revisions.values
            .where((revision) => revision.featureId == featureId)
            .toList()
          ..sort((a, b) => a.revision.compareTo(b.revision));

    return List<SpatialFeatureRevision>.unmodifiable(revisions);
  }

  @override
  SpatialFeatureRevision? findLatestByFeatureId(String featureId) {
    final revisions = findByFeatureId(featureId);

    if (revisions.isEmpty) {
      return null;
    }

    return revisions.last;
  }

  @override
  void create(SpatialFeatureRevision revision) {
    revision.validate();

    if (_revisions.containsKey(revision.id)) {
      throw StateError(
        'Spatial feature revision with id "${revision.id}" already exists.',
      );
    }

    final duplicateIdentity = _revisions.values.any(
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

    _revisions[revision.id] = revision;
  }
}
