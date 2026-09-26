import 'package:agrico_deepseek/features/infrastructure/domain/entities/infrastructure_asset.dart';
import 'package:agrico_deepseek/features/infrastructure/domain/entities/infrastructure_system.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InfrastructureSystem', () {
    final createdAt = DateTime.utc(2026, 9, 10);

    test('groups multiple infrastructure assets without owning geometry', () {
      final system = InfrastructureSystem(
        id: 'irrigation-system-1',
        systemType: InfrastructureSystemType.irrigation,
        name: 'Irrigation System A',
        assetIds: const [
          'reservoir-1',
          'pump-station-1',
          'pipeline-1',
          'pipeline-2',
        ],
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      system.validate();

      expect(system.assetIds, hasLength(4));
      expect(system.assetIds.toSet(), hasLength(4));
      expect(system.systemType, InfrastructureSystemType.irrigation);
    });

    test('rejects duplicate asset membership', () {
      final system = InfrastructureSystem(
        id: 'road-system-1',
        systemType: InfrastructureSystemType.roadNetwork,
        assetIds: const ['road-1', 'road-1'],
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      expect(system.validate, throwsFormatException);
    });
  });
  group('InfrastructureAsset', () {
    final createdAt = DateTime.utc(2026, 9, 10);

    test('keeps infrastructure origin separate from temporal state', () {
      final road = InfrastructureAsset(
        id: 'road-1',
        spatialFeatureId: 'spatial-road-1',
        assetType: InfrastructureAssetType.road,
        origin: InfrastructureOrigin.existingPublic,
        name: 'Existing access road',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      road.validate();

      expect(road.assetType, InfrastructureAssetType.road);
      expect(road.origin, InfrastructureOrigin.existingPublic);
      expect(road.spatialFeatureId, 'spatial-road-1');
    });

    test('maps infrastructure types to Spatial Core contracts', () {
      final road = InfrastructureAsset(
        id: 'road-1',
        spatialFeatureId: 'spatial-road-1',
        assetType: InfrastructureAssetType.road,
        origin: InfrastructureOrigin.existingPublic,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      final reservoir = InfrastructureAsset(
        id: 'reservoir-1',
        spatialFeatureId: 'spatial-reservoir-1',
        assetType: InfrastructureAssetType.reservoir,
        origin: InfrastructureOrigin.companyBuilt,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      final borehole = InfrastructureAsset(
        id: 'borehole-1',
        spatialFeatureId: 'spatial-borehole-1',
        assetType: InfrastructureAssetType.borehole,
        origin: InfrastructureOrigin.companyBuilt,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      expect(road.spatialFeatureType, SpatialFeatureTypes.road);
      expect(road.defaultGeometryType, SpatialGeometryType.lineString);

      expect(reservoir.spatialFeatureType, SpatialFeatureTypes.reservoir);
      expect(reservoir.defaultGeometryType, SpatialGeometryType.polygon);

      expect(borehole.spatialFeatureType, SpatialFeatureTypes.borehole);
      expect(borehole.defaultGeometryType, SpatialGeometryType.point);
    });
    test('supports company-built infrastructure', () {
      final canal = InfrastructureAsset(
        id: 'canal-1',
        spatialFeatureId: 'spatial-canal-1',
        assetType: InfrastructureAssetType.canal,
        origin: InfrastructureOrigin.companyBuilt,
        name: 'Main irrigation canal',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      canal.validate();

      expect(canal.origin, InfrastructureOrigin.companyBuilt);
    });
  });
}
