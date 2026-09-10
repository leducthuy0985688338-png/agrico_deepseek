import 'package:agrico_deepseek/core/spatial/data/in_memory_spatial_feature_repository.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);

  SpatialFeature buildFeature({
    String id = 'parcel-1',
    String name = 'Parcel 1',
  }) {
    return SpatialFeature(
      id: id,
      featureType: SpatialFeatureTypes.landParcel,
      geometryType: SpatialGeometryType.polygon,
      geometry: SpatialPolygon.fromOuterRing(const [
        SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        SpatialCoordinate(latitude: 16.5, longitude: 104.8),
        SpatialCoordinate(latitude: 16.6, longitude: 104.8),
        SpatialCoordinate(latitude: 16.6, longitude: 104.7),
      ]),
      lifecycleStatus: SpatialFeatureLifecycleStatus.existing,
      name: name,
      createdAt: createdAt,
      createdBy: 'user-1',
      updatedAt: createdAt,
      updatedBy: 'user-1',
    );
  }

  group('InMemorySpatialFeatureRepository', () {
    test('starts empty', () {
      final repository = InMemorySpatialFeatureRepository();

      expect(repository.findAll(), isEmpty);
      expect(repository.findById('missing'), isNull);
    });

    test('creates and retrieves a feature by id', () {
      final repository = InMemorySpatialFeatureRepository();
      final feature = buildFeature();

      repository.create(feature);

      expect(repository.findById(feature.id), same(feature));
      expect(repository.findAll(), hasLength(1));
    });

    test('create rejects duplicate feature id', () {
      final repository = InMemorySpatialFeatureRepository();
      final feature = buildFeature();

      repository.create(feature);

      expect(
        () => repository.create(buildFeature(name: 'Duplicate')),
        throwsStateError,
      );
    });

    test('update replaces an existing feature', () {
      final repository = InMemorySpatialFeatureRepository();
      final original = buildFeature();
      repository.create(original);

      final updated = buildFeature(name: 'Updated');
      repository.update(updated);

      expect(repository.findById(original.id), same(updated));
      expect(repository.findById(original.id)!.name, 'Updated');
      expect(repository.findAll(), hasLength(1));
    });

    test('update rejects a missing feature', () {
      final repository = InMemorySpatialFeatureRepository();

      expect(() => repository.update(buildFeature()), throwsStateError);
    });

    test('delete removes an existing feature', () {
      final repository = InMemorySpatialFeatureRepository();
      final feature = buildFeature();

      repository.create(feature);
      repository.deleteById(feature.id);

      expect(repository.findById(feature.id), isNull);
      expect(repository.findAll(), isEmpty);
    });

    test('delete rejects a missing feature', () {
      final repository = InMemorySpatialFeatureRepository();

      expect(() => repository.deleteById('missing'), throwsStateError);
    });

    test('findAll returns an unmodifiable collection', () {
      final repository = InMemorySpatialFeatureRepository();
      repository.create(buildFeature());

      final features = repository.findAll();

      expect(
        () => features.add(buildFeature(id: 'parcel-2')),
        throwsUnsupportedError,
      );
    });

    test('create validates the feature before storing it', () {
      final repository = InMemorySpatialFeatureRepository();

      final invalid = SpatialFeature(
        id: 'invalid',
        featureType: '',
        geometryType: SpatialGeometryType.polygon,
        lifecycleStatus: SpatialFeatureLifecycleStatus.existing,
        createdAt: createdAt,
        createdBy: 'user-1',
        updatedAt: createdAt,
        updatedBy: 'user-1',
      );

      expect(() => repository.create(invalid), throwsFormatException);
      expect(repository.findById('invalid'), isNull);
    });

    test('update validates the feature before replacing it', () {
      final repository = InMemorySpatialFeatureRepository();
      final original = buildFeature();
      repository.create(original);

      final invalid = SpatialFeature(
        id: original.id,
        featureType: '',
        geometryType: SpatialGeometryType.polygon,
        lifecycleStatus: SpatialFeatureLifecycleStatus.existing,
        createdAt: createdAt,
        createdBy: 'user-1',
        updatedAt: createdAt,
        updatedBy: 'user-1',
      );

      expect(() => repository.update(invalid), throwsFormatException);
      expect(repository.findById(original.id), same(original));
    });
  });
}
