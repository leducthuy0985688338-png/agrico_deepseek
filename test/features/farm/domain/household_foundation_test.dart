import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 10, 8);
  final updatedAt = DateTime.utc(2026, 9, 10, 9);

  AdministrativeLocation location() => const AdministrativeLocation(
    countryCode: 'LA',
    countryName: 'Laos',
    provinceCode: 'PROV-01',
    provinceName: 'Province 1',
    districtCode: 'DIST-01',
    districtName: 'District 1',
    villageCode: 'VIL-01',
    villageName: 'Village 1',
  );

  Household household({
    String id = 'household-1',
    String farmId = 'farm-1',
    String householdCode = 'HH-001',
    String headOfHouseholdName = 'Household Head',
    String? phone,
    String? alternativeContact,
    String? address,
    String? notes,
    bool active = true,
    DateTime? created,
    String createdBy = 'user-1',
    DateTime? updated,
    String updatedBy = 'user-1',
    int schemaVersion = Household.currentSchemaVersion,
  }) => Household(
    id: id,
    farmId: farmId,
    householdCode: householdCode,
    headOfHouseholdName: headOfHouseholdName,
    phone: phone,
    alternativeContact: alternativeContact,
    administrativeLocation: location(),
    address: address,
    notes: notes,
    active: active,
    createdAt: created ?? createdAt,
    createdBy: createdBy,
    updatedAt: updated ?? updatedAt,
    updatedBy: updatedBy,
    schemaVersion: schemaVersion,
  );

  group('Household', () {
    test('valid household passes validation', () {
      household().validate();
    });

    test('rejects blank stable identity', () {
      expect(() => household(id: '   ').validate(), throwsFormatException);
    });

    test('rejects blank farm identity', () {
      expect(() => household(farmId: '   ').validate(), throwsFormatException);
    });

    test('rejects blank household code', () {
      expect(
        () => household(householdCode: '   ').validate(),
        throwsFormatException,
      );
    });

    test('rejects blank head of household name', () {
      expect(
        () => household(headOfHouseholdName: '   ').validate(),
        throwsFormatException,
      );
    });

    test('rejects blank audit actor', () {
      expect(
        () => household(createdBy: '   ').validate(),
        throwsFormatException,
      );

      expect(
        () => household(updatedBy: '   ').validate(),
        throwsFormatException,
      );
    });

    test('rejects updatedAt before createdAt', () {
      expect(
        () => household(
          created: DateTime.utc(2026, 9, 10, 10),
          updated: DateTime.utc(2026, 9, 10, 9),
        ).validate(),
        throwsFormatException,
      );
    });

    test('rejects blank optional contact metadata when provided', () {
      expect(() => household(phone: '   ').validate(), throwsFormatException);

      expect(
        () => household(alternativeContact: '   ').validate(),
        throwsFormatException,
      );

      expect(() => household(address: '   ').validate(), throwsFormatException);

      expect(() => household(notes: '   ').validate(), throwsFormatException);
    });

    test('rejects invalid schema version', () {
      expect(
        () => household(schemaVersion: 0).validate(),
        throwsFormatException,
      );
    });
  });
}
