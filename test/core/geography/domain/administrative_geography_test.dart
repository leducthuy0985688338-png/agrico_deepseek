import 'package:agrico_deepseek/core/geography/domain/entities/administrative_unit.dart';
import 'package:agrico_deepseek/core/geography/domain/relationships/spatial_administrative_coverage.dart';
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
