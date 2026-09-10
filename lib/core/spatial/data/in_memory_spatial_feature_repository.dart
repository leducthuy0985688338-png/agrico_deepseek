import '../domain/entities/spatial_feature.dart';
import 'in_memory_spatial_store.dart';
import 'spatial_feature_repository.dart';

class InMemorySpatialFeatureRepository implements SpatialFeatureRepository {
  InMemorySpatialFeatureRepository({InMemorySpatialStore? store})
    : _store = store ?? InMemorySpatialStore();

  final InMemorySpatialStore _store;

  @override
  SpatialFeature? findById(String id) {
    return _store.findFeatureById(id);
  }

  @override
  List<SpatialFeature> findAll() {
    return List<SpatialFeature>.unmodifiable(_store.features);
  }

  @override
  void create(SpatialFeature feature) {
    feature.validate();

    if (_store.containsFeature(feature.id)) {
      throw StateError(
        'Spatial feature with id "${feature.id}" already exists.',
      );
    }

    _store.putFeature(feature);
  }

  @override
  void update(SpatialFeature feature) {
    feature.validate();

    if (!_store.containsFeature(feature.id)) {
      throw StateError(
        'Spatial feature with id "${feature.id}" does not exist.',
      );
    }

    _store.putFeature(feature);
  }

  @override
  void deleteById(String id) {
    if (!_store.containsFeature(id)) {
      throw StateError('Spatial feature with id "$id" does not exist.');
    }

    _store.removeFeature(id);
  }
}
