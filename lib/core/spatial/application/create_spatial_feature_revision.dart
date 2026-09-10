import '../data/spatial_feature_revision_repository.dart';
import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';

class CreateSpatialFeatureRevision {
  const CreateSpatialFeatureRevision(this.repository);

  final SpatialFeatureRevisionRepository repository;

  void execute({
    required SpatialFeature feature,
    required SpatialFeatureRevision revision,
  }) {
    revision.validateAgainstFeature(feature);
    repository.create(revision);
  }
}
