import '../../../core/permissions/authorization.dart';
import '../domain/entities/parcel_work.dart';
import '../domain/repositories/task_work_repository.dart';

class TaskWorkService {
  const TaskWorkService(this.repository);
  final TaskWorkRepository repository;

  void _authorize(
    AuthorizationSubject subject,
    String permission, {
    String? parcelId,
  }) {
    if (!const AuthorizationService().can(
          subject: subject,
          permission: permission,
          resource: ResourceContext(farmId: subject.farmId, fieldId: parcelId),
        ) ||
        !subject.dataScopes.contains(DataScope.allFarm)) {
      throw StateError('Task work requires farm-wide access.');
    }
  }

  Future<void> record(
    AuthorizationSubject subject,
    String taskId,
    ParcelWorkEvent event,
  ) {
    _authorize(subject, PermissionCodes.taskView);
    _authorize(subject, PermissionCodes.fieldEdit, parcelId: event.parcelId);
    if (taskId.trim().isEmpty) {
      throw const FormatException('Task identity is required.');
    }
    if (event.farmId != subject.farmId ||
        event.actorMembershipId != subject.membershipId) {
      throw StateError('Work actor or farm does not match.');
    }
    event.validate();
    return repository.record(taskId, event);
  }

  Future<List<ParcelWorkEvent>> events(
    AuthorizationSubject subject,
    String taskId,
  ) {
    _authorize(subject, PermissionCodes.taskView);
    _authorize(subject, PermissionCodes.fieldView);
    if (taskId.trim().isEmpty) {
      throw const FormatException('Task identity is required.');
    }
    return repository.events(subject.farmId, taskId);
  }
}
