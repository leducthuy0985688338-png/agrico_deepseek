import '../application/spatial_feature_revision_update_transaction.dart';
import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';
import '../domain/geometry/spatial_geometry_pair.dart';
import 'in_memory_spatial_feature_repository.dart';
import 'in_memory_spatial_feature_revision_repository.dart';
import 'in_memory_spatial_store.dart';

class InMemorySpatialFeatureRevisionUpdateTransaction
    implements SpatialFeatureRevisionUpdateTransaction {
  InMemorySpatialFeatureRevisionUpdateTransaction({required this.store});

  final InMemorySpatialStore store;

  @override
  Future<void> update({
    required SpatialFeature feature,
    required SpatialFeatureRevision revision,
  }) async {
    feature.validate();
    validateSpatialGeometryPair(feature, revision);

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

    final existingFeature = await stagedFeatureRepository.findById(feature.id);

    if (existingFeature == null) {
      throw StateError('Spatial feature not found: ${feature.id}');
    }

    if (existingFeature.featureType != feature.featureType) {
      throw StateError(
        'Spatial feature featureType is immutable for ${feature.id}.',
      );
    }

    if (existingFeature.geometryType != feature.geometryType) {
      throw StateError(
        'Spatial feature geometryType is immutable for ${feature.id}.',
      );
    }

    if (existingFeature.createdAt != feature.createdAt) {
      throw StateError(
        'Spatial feature createdAt is immutable for ${feature.id}.',
      );
    }

    if (existingFeature.createdBy != feature.createdBy) {
      throw StateError(
        'Spatial feature createdBy is immutable for ${feature.id}.',
      );
    }

    final latestRevision = await stagedRevisionRepository.findLatestByFeatureId(
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

    await stagedFeatureRepository.update(feature);
    await stagedRevisionRepository.create(revision);

    store.replaceWith(stagedStore);
  }
}
