import '../domain/entities/spatial_feature.dart';
import 'spatial_feature_repository.dart';

class InMemorySpatialFeatureRepository implements SpatialFeatureRepository {
  final Map<String, SpatialFeature> _features = <String, SpatialFeature>{};

  @override
  SpatialFeature? findById(String id) {
    return _features[id];
  }

  @override
  List<SpatialFeature> findAll() {
    return List<SpatialFeature>.unmodifiable(_features.values);
  }

  @override
  void create(SpatialFeature feature) {
    feature.validate();

    if (_features.containsKey(feature.id)) {
      throw StateError(
        'Spatial feature with id "${feature.id}" already exists.',
      );
    }

    _features[feature.id] = feature;
  }

  @override
  void update(SpatialFeature feature) {
    feature.validate();

    if (!_features.containsKey(feature.id)) {
      throw StateError(
        'Spatial feature with id "${feature.id}" does not exist.',
      );
    }

    _features[feature.id] = feature;
  }

  @override
  void deleteById(String id) {
    if (!_features.containsKey(id)) {
      throw StateError('Spatial feature with id "$id" does not exist.');
    }

    _features.remove(id);
  }
}
