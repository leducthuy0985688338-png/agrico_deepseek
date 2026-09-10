import '../data/spatial_feature_repository.dart';
import '../data/spatial_feature_revision_repository.dart';
import '../domain/entities/spatial_feature_revision.dart';

class CreateSpatialFeatureRevisionCoordinator {
  const CreateSpatialFeatureRevisionCoordinator({
    required this.featureRepository,
    required this.revisionRepository,
  });

  final SpatialFeatureRepository featureRepository;
  final SpatialFeatureRevisionRepository revisionRepository;

  void execute(SpatialFeatureRevision revision) {
    final feature = featureRepository.findById(revision.featureId);

    if (feature == null) {
      throw StateError('Spatial feature not found: ${revision.featureId}');
    }

    revision.validateAgainstFeature(feature);

    final latestRevision = revisionRepository.findLatestByFeatureId(
      revision.featureId,
    );

    final expectedRevision = latestRevision == null
        ? 1
        : latestRevision.revision + 1;

    if (revision.revision != expectedRevision) {
      throw StateError(
        'Expected spatial feature revision $expectedRevision '
        'for ${revision.featureId}, but received ${revision.revision}.',
      );
    }

    revisionRepository.create(revision);
  }
}
