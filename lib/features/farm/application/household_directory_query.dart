import '../../../core/permissions/authorization.dart';
import '../domain/entities/land_survey.dart';
import '../domain/repositories/land_survey_repository.dart';

/// Farm-wide household browsing is available only to memberships that can
/// view fields across the farm. Narrower scopes need a separate scoped query.
class HouseholdDirectoryQuery {
  const HouseholdDirectoryQuery(this.repository);

  final LandSurveyRepository repository;

  Future<List<Household>> list(AuthorizationSubject subject) async {
    if (!const AuthorizationService().can(
          subject: subject,
          permission: PermissionCodes.fieldView,
          resource: ResourceContext(farmId: subject.farmId),
        ) ||
        !subject.dataScopes.contains(DataScope.allFarm)) {
      throw StateError('Household directory requires farm-wide field access.');
    }
    return repository.listHouseholds(subject.farmId);
  }
}
