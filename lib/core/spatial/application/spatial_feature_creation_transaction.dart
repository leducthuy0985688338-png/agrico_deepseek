import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';

abstract interface class SpatialFeatureCreationTransaction {
  void create({
    required SpatialFeature feature,
    required SpatialFeatureRevision initialRevision,
  });
}
