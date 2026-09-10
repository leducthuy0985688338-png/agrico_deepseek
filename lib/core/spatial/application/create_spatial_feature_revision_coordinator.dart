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

  Future<void> execute(SpatialFeatureRevision revision) async {
    final feature = await featureRepository.findById(revision.featureId);

    if (feature == null) {
      throw StateError('Spatial feature not found: ${revision.featureId}');
    }

    revision.validateAgainstFeature(feature);

    final latestRevision = await revisionRepository.findLatestByFeatureId(
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

    await revisionRepository.create(revision);
  }
}
