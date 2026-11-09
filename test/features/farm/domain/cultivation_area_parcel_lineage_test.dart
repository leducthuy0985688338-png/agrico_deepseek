import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/cultivation_area.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_lineage.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/pre_compensation_parcel.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 10, 8);
  final effectiveAt = DateTime.utc(2026, 9, 1);

  group('CultivationArea', () {
    test('uses a stable multipart spatial feature', () {
      final area = CultivationArea(
        id: 'area-1',
        farmId: 'farm-1',
        areaCode: 'AREA-001',
        name: 'Northern cultivation area',
        spatialFeatureId: 'feature-area-1',
        active: true,
        createdAt: createdAt,
        createdBy: 'user-1',
        updatedAt: createdAt,
        updatedBy: 'user-1',
      );

      area.validate();

      final feature = area.toSpatialFeature(
        lifecycleStatus: SpatialFeatureLifecycleStatus.active,
      );

      expect(feature.featureType, SpatialFeatureTypes.cultivationArea);
      expect(feature.geometryType, SpatialGeometryType.multiPolygon);
      expect(feature.id, area.spatialFeatureId);
    });

    test('rejects blank cultivation area code', () {
      final area = CultivationArea(
        id: 'area-1',
        farmId: 'farm-1',
        areaCode: ' ',
        name: 'Area',
        spatialFeatureId: 'feature-area-1',
        active: true,
        createdAt: createdAt,
        createdBy: 'user-1',
        updatedAt: createdAt,
        updatedBy: 'user-1',
      );

      expect(area.validate, throwsFormatException);
    });
  });

  group('PreCompensationParcel', () {
    test('maps historical parcel to a polygon spatial feature', () {
      final parcel = PreCompensationParcel(
        id: 'pre-1',
        farmId: 'farm-1',
        parcelCode: 'PRE-001',
        spatialFeatureId: 'feature-pre-1',
        householdId: 'household-1',
        ownerDisplayName: 'Owner at compensation baseline',
        status: CompensationParcelStatus.verified,
        recordedAt: effectiveAt,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      parcel.validate();

      final feature = parcel.toSpatialFeature();

      expect(feature.featureType, SpatialFeatureTypes.preCompensationParcel);
      expect(feature.geometryType, SpatialGeometryType.polygon);
      expect(feature.lifecycleStatus, SpatialFeatureLifecycleStatus.historical);
      expect(feature.name, parcel.ownerDisplayName);
    });

    test('rejects creation before historical recorded date', () {
      final parcel = PreCompensationParcel(
        id: 'pre-1',
        farmId: 'farm-1',
        parcelCode: 'PRE-001',
        spatialFeatureId: 'feature-pre-1',
        householdId: 'household-1',
        ownerDisplayName: 'Owner',
        status: CompensationParcelStatus.recorded,
        recordedAt: createdAt,
        createdAt: effectiveAt,
        createdBy: 'user-1',
      );

      expect(parcel.validate, throwsFormatException);
    });
  });

  group('ParcelLineage', () {
    test(
      'supports partial derivation from historical to production parcel',
      () {
        final lineage = ParcelLineage(
          id: 'lineage-1',
          preCompensationParcelId: 'pre-1',
          productionParcelId: 'production-1',
          lineageType: ParcelLineageType.partialDerivation,
          sourceAreaM2: 10000,
          derivedAreaM2: 4000,
          derivedShare: 0.4,
          effectiveAt: effectiveAt,
          createdAt: createdAt,
          createdBy: 'user-1',
        );

        expect(lineage.validate, returnsNormally);
      },
    );

    test('supports multiple source records for a merged production parcel', () {
      final first = ParcelLineage(
        id: 'lineage-1',
        preCompensationParcelId: 'pre-1',
        productionParcelId: 'production-1',
        lineageType: ParcelLineageType.merge,
        effectiveAt: effectiveAt,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      final second = ParcelLineage(
        id: 'lineage-2',
        preCompensationParcelId: 'pre-2',
        productionParcelId: 'production-1',
        lineageType: ParcelLineageType.merge,
        effectiveAt: effectiveAt,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      expect(first.validate, returnsNormally);
      expect(second.validate, returnsNormally);
      expect(
        first.preCompensationParcelId,
        isNot(second.preCompensationParcelId),
      );
      expect(first.productionParcelId, second.productionParcelId);
    });

    test('allows relocation derived area to exceed historical source area', () {
      final lineage = ParcelLineage(
        id: 'lineage-1',
        preCompensationParcelId: 'pre-1',
        productionParcelId: 'production-1',
        lineageType: ParcelLineageType.relocation,
        sourceAreaM2: 8000,
        derivedAreaM2: 10000,
        effectiveAt: effectiveAt,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      expect(lineage.validate, returnsNormally);
    });

    test('rejects lineage share outside zero-to-one range', () {
      final lineage = ParcelLineage(
        id: 'lineage-1',
        preCompensationParcelId: 'pre-1',
        productionParcelId: 'production-1',
        lineageType: ParcelLineageType.partialDerivation,
        derivedShare: 1.2,
        effectiveAt: effectiveAt,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      expect(lineage.validate, throwsFormatException);
    });
  });
}
