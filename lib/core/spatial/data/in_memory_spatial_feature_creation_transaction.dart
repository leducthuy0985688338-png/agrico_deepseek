import '../application/spatial_feature_creation_transaction.dart';
import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';
import 'spatial_feature_repository.dart';
import 'spatial_feature_revision_repository.dart';

class InMemorySpatialFeatureCreationTransaction
    implements SpatialFeatureCreationTransaction {
  InMemorySpatialFeatureCreationTransaction({
    required this.featureRepository,
    required this.revisionRepository,
  });

  final SpatialFeatureRepository featureRepository;
  final SpatialFeatureRevisionRepository revisionRepository;

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

    if (featureRepository.findById(feature.id) != null) {
      throw StateError('Spatial feature already exists: ${feature.id}');
    }

    if (revisionRepository.findById(initialRevision.id) != null) {
      throw StateError(
        'Spatial feature revision already exists: ${initialRevision.id}',
      );
    }

    final existingRevisions = revisionRepository.findByFeatureId(feature.id);

    if (existingRevisions.isNotEmpty) {
      throw StateError(
        'Spatial feature already has revision history: ${feature.id}',
      );
    }

    featureRepository.create(feature);

    try {
      revisionRepository.create(initialRevision);
    } catch (_) {
      featureRepository.deleteById(feature.id);
      rethrow;
    }
  }
}
