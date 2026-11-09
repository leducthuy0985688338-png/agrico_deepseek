import 'dart:math';

import '../../../core/geography/domain/administrative_catalog_repository.dart';
import '../../../core/geography/domain/entities/administrative_unit.dart';
import '../../../core/permissions/authorization.dart';
import '../domain/entities/land_survey.dart';

abstract interface class HouseholdCreationTransaction {
  Future<Household> create({
    required String farmId,
    required Household Function(String code) build,
  });
}

/// The village comes from the approved catalog, while the H-number is
/// allocated and persisted in one SQLite transaction by the adapter.
class CreateHousehold {
  const CreateHousehold(this.catalog, this.transaction);

  final AdministrativeCatalogRepository catalog;
  final HouseholdCreationTransaction transaction;

  Future<Household> execute({
    required AuthorizationSubject subject,
    required String villageId,
    required String headName,
    String? phone,
    String? alternativeContact,
  }) async {
    if (!const AuthorizationService().can(
          subject: subject,
          permission: PermissionCodes.householdCreate,
          resource: ResourceContext(farmId: subject.farmId),
        ) ||
        !subject.dataScopes.contains(DataScope.allFarm)) {
      throw StateError('Household creation requires farm-wide access.');
    }
    final name = headName.trim();
    if (name.isEmpty || villageId.isEmpty) {
      throw const FormatException('A household head and village are required.');
    }
    final units = {for (final unit in await catalog.all()) unit.id: unit};
    AdministrativeUnit require(String? id, AdministrativeLevel level) {
      final unit = units[id];
      if (unit == null || !unit.active || unit.level != level ||
          unit.code == null ||
          !RegExp(r'^[A-Z0-9]+$').hasMatch(unit.code!)) {
        throw const FormatException('Select an active coded administrative path.');
      }
      return unit;
    }
    final village = require(villageId, AdministrativeLevel.village);
    final district = require(village.parentId, AdministrativeLevel.district);
    final province = require(district.parentId, AdministrativeLevel.province);
    final country = require(province.parentId, AdministrativeLevel.country);
    if (country.parentId != null) {
      throw const FormatException('Invalid country hierarchy.');
    }
    final location = AdministrativeLocation(
      countryName: country.name, countryCode: country.code,
      provinceName: province.name, provinceCode: province.code,
      districtName: district.name, districtCode: district.code,
      villageName: village.name, villageCode: village.code,
    );
    final now = DateTime.now().toUtc();
    final id = 'household-${now.microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(1 << 32)}';
    String? optional(String? value) => value?.trim().isEmpty == true
        ? null : value?.trim();
    return transaction.create(
      farmId: subject.farmId,
      build: (code) {
        final household = Household(
          id: id, farmId: subject.farmId, householdCode: code,
          headOfHouseholdName: name, administrativeLocation: location,
          phone: optional(phone), alternativeContact: optional(alternativeContact),
          active: true, createdAt: now, createdBy: subject.membershipId,
          updatedAt: now, updatedBy: subject.membershipId,
        );
        household.validate();
        return household;
      },
    );
  }
}
