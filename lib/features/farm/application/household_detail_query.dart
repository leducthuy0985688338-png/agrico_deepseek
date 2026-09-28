import '../../../core/permissions/authorization.dart';
import '../domain/entities/land_parcel.dart';
import '../domain/entities/land_survey.dart';
import '../domain/repositories/land_parcel_repository.dart';
import '../domain/repositories/land_survey_repository.dart';

class HouseholdWithParcels {
  const HouseholdWithParcels(this.household, this.parcels);

  final Household household;
  final List<LandParcel> parcels;
}

/// Resolves parcel ownership by stable household ID, never by name or code.
class HouseholdDetailQuery {
  const HouseholdDetailQuery(this.households, this.parcels);

  final LandSurveyRepository households;
  final LandParcelRepository parcels;

  Future<HouseholdWithParcels?> load(
      AuthorizationSubject subject, String householdId) async {
    if (!const AuthorizationService().can(
          subject: subject,
          permission: PermissionCodes.fieldView,
          resource: ResourceContext(farmId: subject.farmId),
        ) ||
        !subject.dataScopes.contains(DataScope.allFarm)) {
      throw StateError('Household detail requires farm-wide field access.');
    }
    final household = await households.getHousehold(householdId);
    if (household == null || household.farmId != subject.farmId) return null;
    final linked = (await parcels.listByFarm(
      subject.farmId, includeInactive: true,
    )).where((parcel) => parcel.ownerHouseholdId == household.id).toList()
      ..sort((a, b) => a.parcelCode.compareTo(b.parcelCode));
    return HouseholdWithParcels(household, List.unmodifiable(linked));
  }
}
