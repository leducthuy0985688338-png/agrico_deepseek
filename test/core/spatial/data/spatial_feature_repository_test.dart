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
    test('starts empty', () async {
      final repository = InMemorySpatialFeatureRepository();

      expect(await repository.findAll(), isEmpty);
      expect(await repository.findById('missing'), isNull);
    });

    test('creates and retrieves a feature by id', () async {
      final repository = InMemorySpatialFeatureRepository();
      final feature = buildFeature();

      await repository.create(feature);

      expect(await repository.findById(feature.id), same(feature));
      expect(await repository.findAll(), hasLength(1));
    });

    test('create rejects duplicate feature id', () async {
      final repository = InMemorySpatialFeatureRepository();
      final feature = buildFeature();

      await repository.create(feature);

      await expectLater(
        repository.create(buildFeature(name: 'Duplicate')),
        throwsStateError,
      );
    });

    test('update replaces an existing feature', () async {
      final repository = InMemorySpatialFeatureRepository();
      final original = buildFeature();
      await repository.create(original);

      final updated = buildFeature(name: 'Updated');
      await repository.update(updated);

      expect(await repository.findById(original.id), same(updated));
      expect((await repository.findById(original.id))!.name, 'Updated');
      expect(await repository.findAll(), hasLength(1));
    });

    test('update rejects a missing feature', () async {
      final repository = InMemorySpatialFeatureRepository();

      await expectLater(repository.update(buildFeature()), throwsStateError);
    });

    test('delete removes an existing feature', () async {
      final repository = InMemorySpatialFeatureRepository();
      final feature = buildFeature();

      await repository.create(feature);
      await repository.deleteById(feature.id);

      expect(await repository.findById(feature.id), isNull);
      expect(await repository.findAll(), isEmpty);
    });

    test('delete rejects a missing feature', () async {
      final repository = InMemorySpatialFeatureRepository();

      await expectLater(repository.deleteById('missing'), throwsStateError);
    });

    test('findAll returns an unmodifiable collection', () async {
      final repository = InMemorySpatialFeatureRepository();
      await repository.create(buildFeature());

      final features = await repository.findAll();

      expect(
        () => features.add(buildFeature(id: 'parcel-2')),
        throwsUnsupportedError,
      );
    });

    test('create validates the feature before storing it', () async {
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

      await expectLater(repository.create(invalid), throwsFormatException);
      expect(await repository.findById('invalid'), isNull);
    });

    test('update validates the feature before replacing it', () async {
      final repository = InMemorySpatialFeatureRepository();
      final original = buildFeature();
      await repository.create(original);

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

      await expectLater(repository.update(invalid), throwsFormatException);
      expect(await repository.findById(original.id), same(original));
    });
  });
}
