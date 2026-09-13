import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';
import 'spatial_feature_creation_transaction.dart';

class CreateSpatialFeatureWithInitialRevision {
  const CreateSpatialFeatureWithInitialRevision(this.transaction);

  final SpatialFeatureCreationTransaction transaction;

  Future<void> execute({
    required SpatialFeature feature,
    required SpatialFeatureRevision initialRevision,
  }) async {
    feature.validate();
    initialRevision.validateAgainstFeature(feature);

    if (initialRevision.revision != 1) {
      throw StateError(
        'Initial spatial feature revision must be 1, '
        'but received ${initialRevision.revision}.',
      );
    }

    await transaction.create(
      feature: feature,
      initialRevision: initialRevision,
    );
  }
}
