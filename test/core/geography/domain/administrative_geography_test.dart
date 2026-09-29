import 'package:agrico_deepseek/core/geography/domain/entities/administrative_unit.dart';
import 'package:agrico_deepseek/core/geography/domain/relationships/spatial_administrative_coverage.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 10, 8);

  group('AdministrativeUnit', () {
    test('supports country province district village hierarchy', () {
      final country = AdministrativeUnit(
        id: 'country-la',
        level: AdministrativeLevel.country,
        name: 'Laos',
        code: 'LA',
        countryCode: 'LA',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      final province = AdministrativeUnit(
        id: 'province-1',
        level: AdministrativeLevel.province,
        name: 'Province 1',
        parentId: country.id,
        countryCode: 'LA',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      final district = AdministrativeUnit(
        id: 'district-1',
        level: AdministrativeLevel.district,
        name: 'District 1',
        parentId: province.id,
        countryCode: 'LA',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      final village = AdministrativeUnit(
        id: 'village-1',
        level: AdministrativeLevel.village,
        name: 'Village 1',
        parentId: district.id,
        countryCode: 'LA',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      country.validate();
      province.validate();
      district.validate();
      village.validate();

      expect(province.parentId, country.id);
      expect(district.parentId, province.id);
      expect(village.parentId, district.id);
    });

    test('supports flexible multi-country administrative levels', () {
      final province = AdministrativeUnit(
        id: 'province-vn-1',
        level: AdministrativeLevel.province,
        name: 'Province 1',
        parentId: 'country-vn',
        countryCode: 'VN',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      final commune = AdministrativeUnit(
        id: 'commune-vn-1',
        level: AdministrativeLevel.commune,
        name: 'Commune 1',
        parentId: province.id,
        countryCode: 'VN',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      final village = AdministrativeUnit(
        id: 'village-vn-1',
        level: AdministrativeLevel.village,
        name: 'Village 1',
        parentId: commune.id,
        countryCode: 'VN',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      final ward = AdministrativeUnit(
        id: 'ward-vn-1',
        level: AdministrativeLevel.ward,
        name: 'Ward 1',
        parentId: 'municipality-vn-1',
        countryCode: 'VN',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      province.validate();
      commune.validate();
      village.validate();
      ward.validate();

      expect(commune.parentId, province.id);
      expect(village.parentId, commune.id);
      expect(ward.level, AdministrativeLevel.ward);
    });
    test('links administrative unit to versioned spatial boundary', () {
      final unit = AdministrativeUnit(
        id: 'district-la-1',
        level: AdministrativeLevel.district,
        name: 'District 1',
        parentId: 'province-la-1',
        countryCode: 'LA',
        spatialFeatureId: 'admin-boundary-district-la-1',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      final boundary = SpatialFeature(
        id: unit.spatialFeatureId!,
        featureType: SpatialFeatureTypes.administrativeBoundary,
        geometryType: SpatialGeometryType.multiPolygon,
        lifecycleStatus: SpatialFeatureLifecycleStatus.active,
        name: unit.name,
        createdAt: createdAt,
        createdBy: 'user-1',
        updatedAt: createdAt,
        updatedBy: 'user-1',
      );

      unit.validate();
      boundary.validate();

      expect(boundary.id, unit.spatialFeatureId);
      expect(boundary.featureType, SpatialFeatureTypes.administrativeBoundary);
      expect(boundary.geometryType, SpatialGeometryType.multiPolygon);
    });
    test('rejects parent on country', () {
      final unit = AdministrativeUnit(
        id: 'country-la',
        level: AdministrativeLevel.country,
        name: 'Laos',
        parentId: 'another-country',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      expect(unit.validate, throwsFormatException);
    });

    test('requires parent for non-country unit', () {
      final unit = AdministrativeUnit(
        id: 'province-1',
        level: AdministrativeLevel.province,
        name: 'Province 1',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      expect(unit.validate, throwsFormatException);
    });

    test('rejects self parent relationship', () {
      final unit = AdministrativeUnit(
        id: 'district-1',
        level: AdministrativeLevel.district,
        name: 'District 1',
        parentId: 'district-1',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      expect(unit.validate, throwsFormatException);
    });
  });

  group('SpatialAdministrativeCoverage', () {
    test('allows one spatial feature to intersect multiple villages', () {
      final firstVillage = SpatialAdministrativeCoverage(
        id: 'coverage-1',
        spatialFeatureId: 'cultivation-area-1',
        administrativeUnitId: 'village-1',
        coverageType: AdministrativeCoverageType.intersects,
        coverageShare: 0.6,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      final secondVillage = SpatialAdministrativeCoverage(
        id: 'coverage-2',
        spatialFeatureId: 'cultivation-area-1',
        administrativeUnitId: 'village-2',
        coverageType: AdministrativeCoverageType.intersects,
        coverageShare: 0.4,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      firstVillage.validate();
      secondVillage.validate();

      expect(firstVillage.spatialFeatureId, secondVillage.spatialFeatureId);
      expect(
        firstVillage.administrativeUnitId,
        isNot(secondVillage.administrativeUnitId),
      );
    });

    test('supports historical administrative coverage period', () {
      final coverage = SpatialAdministrativeCoverage(
        id: 'coverage-historical-1',
        spatialFeatureId: 'pre-compensation-parcel-1',
        administrativeUnitId: 'district-old-1',
        coverageType: AdministrativeCoverageType.intersects,
        effectivePeriod: SpatialEffectivePeriod(
          validFrom: DateTime.utc(2024, 1, 1),
          validTo: DateTime.utc(2025, 1, 1),
        ),
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      coverage.validate();

      expect(
        coverage.effectivePeriod!.contains(DateTime.utc(2024, 6, 1)),
        isTrue,
      );
      expect(
        coverage.effectivePeriod!.contains(DateTime.utc(2025, 1, 1)),
        isFalse,
      );
    });
    test('rejects invalid administrative coverage period', () {
      final instant = DateTime.utc(2024, 1, 1);

      final coverage = SpatialAdministrativeCoverage(
        id: 'coverage-invalid-period',
        spatialFeatureId: 'pre-compensation-parcel-1',
        administrativeUnitId: 'district-old-1',
        coverageType: AdministrativeCoverageType.intersects,
        effectivePeriod: SpatialEffectivePeriod(
          validFrom: instant,
          validTo: instant,
        ),
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      expect(coverage.validate, throwsFormatException);
    });
    test('allows coverage when share has not been calculated yet', () {
      final coverage = SpatialAdministrativeCoverage(
        id: 'coverage-1',
        spatialFeatureId: 'road-1',
        administrativeUnitId: 'district-1',
        coverageType: AdministrativeCoverageType.intersects,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      coverage.validate();

      expect(coverage.coverageShare, isNull);
    });

    test('rejects coverage share greater than one', () {
      final coverage = SpatialAdministrativeCoverage(
        id: 'coverage-1',
        spatialFeatureId: 'cultivation-area-1',
        administrativeUnitId: 'village-1',
        coverageType: AdministrativeCoverageType.intersects,
        coverageShare: 1.1,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      expect(coverage.validate, throwsFormatException);
    });

    test('rejects zero coverage share', () {
      final coverage = SpatialAdministrativeCoverage(
        id: 'coverage-1',
        spatialFeatureId: 'cultivation-area-1',
        administrativeUnitId: 'village-1',
        coverageType: AdministrativeCoverageType.intersects,
        coverageShare: 0,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      expect(coverage.validate, throwsFormatException);
    });
  });
}
