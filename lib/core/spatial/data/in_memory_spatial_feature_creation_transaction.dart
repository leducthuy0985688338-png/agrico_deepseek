import '../application/spatial_feature_creation_transaction.dart';
import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';
import 'in_memory_spatial_feature_repository.dart';
import 'in_memory_spatial_feature_revision_repository.dart';
import 'in_memory_spatial_store.dart';

class InMemorySpatialFeatureCreationTransaction
    implements SpatialFeatureCreationTransaction {
  InMemorySpatialFeatureCreationTransaction({required this.store});

  final InMemorySpatialStore store;

  @override
  void create({
    required SpatialFeature feature,
    required SpatialFeatureRevision initialRevision,
  }) {
    feature.validate();
    initialRevision.validateAgainstFeature(feature);

    if (initialRevision.revision != 1) {
      throw StateError(
        'Initial spatial feature revision must be 1, '
        'but received ${initialRevision.revision}.',
      );
    }

    final stagedStore = store.copy();

    final stagedFeatureRepository = InMemorySpatialFeatureRepository(
      store: stagedStore,
    );

    final stagedRevisionRepository = InMemorySpatialFeatureRevisionRepository(
      store: stagedStore,
    );

    stagedFeatureRepository.create(feature);

    final existingRevisions = stagedRevisionRepository.findByFeatureId(
      feature.id,
    );

    if (existingRevisions.isNotEmpty) {
      throw StateError(
        'Spatial feature already has revision history: ${feature.id}',
      );
    }

    stagedRevisionRepository.create(initialRevision);

    store.replaceWith(stagedStore);
  }
}
