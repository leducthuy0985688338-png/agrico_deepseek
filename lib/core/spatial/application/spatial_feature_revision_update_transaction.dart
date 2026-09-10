import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';

abstract interface class SpatialFeatureRevisionUpdateTransaction {
  void update({
    required SpatialFeature feature,
    required SpatialFeatureRevision revision,
  });
}
