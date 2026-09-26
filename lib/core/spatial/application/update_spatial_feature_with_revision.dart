import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';
import '../domain/geometry/spatial_geometry_pair.dart';
import 'spatial_feature_revision_update_transaction.dart';

class UpdateSpatialFeatureWithRevision {
  const UpdateSpatialFeatureWithRevision(this.transaction);

  final SpatialFeatureRevisionUpdateTransaction transaction;

  Future<void> execute({
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

    await transaction.update(feature: feature, revision: revision);
  }
}
