import '../../../core/permissions/authorization.dart';
import '../domain/entities/parcel_work.dart';
import '../domain/repositories/parcel_work_repository.dart';

class ParcelWorkService {
  const ParcelWorkService(this.repository);

  final ParcelWorkRepository repository;

  void _authorize(AuthorizationSubject subject, String permission,
      {String? parcelId}) {
    if (!const AuthorizationService().can(
          subject: subject, permission: permission,
          resource: ResourceContext(farmId: subject.farmId, fieldId: parcelId),
        ) || !subject.dataScopes.contains(DataScope.allFarm)) {
      throw StateError('Parcel work requires farm-wide access.');
    }
  }

  Future<void> register(AuthorizationSubject subject, WorkResource resource) {
    _authorize(subject, PermissionCodes.fieldEdit);
    if (resource.farmId != subject.farmId) {
      throw StateError('Resource is outside the current farm.');
    }
    return repository.register(resource);
  }

  Future<List<WorkResource>> resources(AuthorizationSubject subject) {
    _authorize(subject, PermissionCodes.fieldView);
    return repository.resources(subject.farmId);
  }

  Future<void> record(AuthorizationSubject subject, ParcelWorkEvent event) {
    _authorize(subject, PermissionCodes.fieldEdit, parcelId: event.parcelId);
    if (event.farmId != subject.farmId ||
        event.actorMembershipId != subject.membershipId) {
      throw StateError('Work actor or farm does not match.');
    }
    return repository.record(event);
  }

  Future<List<ParcelWorkEvent>> events(
      AuthorizationSubject subject, String parcelId) {
    _authorize(subject, PermissionCodes.fieldView, parcelId: parcelId);
    return repository.events(subject.farmId, parcelId);
  }
}
