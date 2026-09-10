import '../application/spatial_feature_revision_update_transaction.dart';
import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';
import 'in_memory_spatial_feature_repository.dart';
import 'in_memory_spatial_feature_revision_repository.dart';
import 'in_memory_spatial_store.dart';

class InMemorySpatialFeatureRevisionUpdateTransaction
    implements SpatialFeatureRevisionUpdateTransaction {
  InMemorySpatialFeatureRevisionUpdateTransaction({required this.store});

  final InMemorySpatialStore store;

  @override
  void update({
    required SpatialFeature feature,
    required SpatialFeatureRevision revision,
  }) {
    feature.validate();
    revision.validateAgainstFeature(feature);

    if (revision.revision < 2) {
      throw StateError(
        'Updated spatial feature revision must be at least 2, '
        'but received ${revision.revision}.',
      );
    }

    final stagedStore = store.copy();

    final stagedFeatureRepository = InMemorySpatialFeatureRepository(
      store: stagedStore,
    );

    final stagedRevisionRepository = InMemorySpatialFeatureRevisionRepository(
      store: stagedStore,
    );

    final existingFeature = stagedFeatureRepository.findById(feature.id);

    if (existingFeature == null) {
      throw StateError('Spatial feature not found: ${feature.id}');
    }

    final latestRevision = stagedRevisionRepository.findLatestByFeatureId(
      feature.id,
    );

    if (latestRevision == null) {
      throw StateError(
        'Spatial feature has no revision history: ${feature.id}',
      );
    }

    final expectedRevision = latestRevision.revision + 1;

    if (revision.revision != expectedRevision) {
      throw StateError(
        'Expected spatial feature revision $expectedRevision '
        'for ${feature.id}, but received ${revision.revision}.',
      );
    }

    stagedFeatureRepository.update(feature);
    stagedRevisionRepository.create(revision);

    store.replaceWith(stagedStore);
  }
}
