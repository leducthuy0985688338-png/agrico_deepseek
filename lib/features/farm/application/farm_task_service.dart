import '../../../core/permissions/authorization.dart';
import '../domain/entities/farm_task.dart';
import '../domain/repositories/farm_task_repository.dart';

class FarmTaskService {
  const FarmTaskService(this.repository);

  final FarmTaskRepository repository;

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
      throw StateError('Farm tasks require farm-wide access.');
    }
  }

  Future<void> create(AuthorizationSubject subject, FarmTask task) {
    _authorize(subject, PermissionCodes.taskCreate, parcelId: task.parcelId);
    if (task.farmId != subject.farmId) {
      throw StateError('Task is outside the current farm.');
    }
    task.validate();
    return repository.create(task);
  }

  Future<void> update(AuthorizationSubject subject, FarmTask task) {
    _authorize(subject, PermissionCodes.taskEdit, parcelId: task.parcelId);
    if (task.farmId != subject.farmId) {
      throw StateError('Task is outside the current farm.');
    }
    task.validate();
    return repository.update(task);
  }

  Future<List<FarmTask>> list(AuthorizationSubject subject) {
    _authorize(subject, PermissionCodes.taskView);
    return repository.listByFarm(subject.farmId);
  }

  Future<void> changeStatus(AuthorizationSubject subject, String taskId,
      FarmTaskStatus status) {
    _authorize(subject, PermissionCodes.taskEdit);
    if (taskId.trim().isEmpty ||
        (status != FarmTaskStatus.inProgress && status != FarmTaskStatus.delayed)) {
      throw const FormatException('Invalid task status transition.');
    }
    return repository.changeStatus(farmId: subject.farmId, id: taskId, status: status);
  }

  Future<void> complete(AuthorizationSubject subject, String taskId) {
    _authorize(subject, PermissionCodes.taskComplete);
    if (taskId.trim().isEmpty) {
      throw const FormatException('Task identity is required.');
    }
    return repository.complete(farmId: subject.farmId, id: taskId);
  }
}
