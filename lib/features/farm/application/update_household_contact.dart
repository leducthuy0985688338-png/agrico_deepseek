import '../../../core/permissions/authorization.dart';
import '../domain/entities/land_survey.dart';
import '../domain/repositories/land_survey_repository.dart';

/// Updates only the current household contact. Parcel owner display snapshots
/// and the household's business code and administrative path remain intact.
class UpdateHouseholdContact {
  const UpdateHouseholdContact(this.repository);

  final LandSurveyRepository repository;

  Future<Household> execute({
    required AuthorizationSubject subject,
    required String householdId,
    required String headName,
    required String phone,
    required String alternativeContact,
  }) async {
    if (!const AuthorizationService().can(
          subject: subject,
          permission: PermissionCodes.householdEdit,
          resource: ResourceContext(farmId: subject.farmId),
        ) || !subject.dataScopes.contains(DataScope.allFarm)) {
      throw StateError('Household editing requires farm-wide access.');
    }
    final name = headName.trim();
    if (name.isEmpty) {
      throw const FormatException('The household head cannot be blank.');
    }
    String? optional(String value) => value.trim().isEmpty ? null : value.trim();
    return repository.transaction((tx) async {
      final existing = await tx.getHousehold(householdId);
      if (existing == null || existing.farmId != subject.farmId) {
        throw StateError('Household is not in the current farm.');
      }
      final now = DateTime.now().toUtc();
      final updated = Household(
        id: existing.id,
        farmId: existing.farmId,
        householdCode: existing.householdCode,
        headOfHouseholdName: name,
        phone: optional(phone),
        alternativeContact: optional(alternativeContact),
        administrativeLocation: existing.administrativeLocation,
        address: existing.address,
        notes: existing.notes,
        active: existing.active,
        createdAt: existing.createdAt,
        createdBy: existing.createdBy,
        updatedAt: now.isBefore(existing.createdAt) ? existing.createdAt : now,
        updatedBy: subject.membershipId,
        schemaVersion: existing.schemaVersion,
      );
      updated.validate();
      await tx.updateHousehold(updated);
      return updated;
    });
  }
}
