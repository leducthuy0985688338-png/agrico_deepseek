import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';
import 'spatial_feature_revision_update_transaction.dart';

class UpdateSpatialFeatureWithRevision {
  const UpdateSpatialFeatureWithRevision(this.transaction);

  final SpatialFeatureRevisionUpdateTransaction transaction;

  void execute({
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

    transaction.update(feature: feature, revision: revision);
  }
}
