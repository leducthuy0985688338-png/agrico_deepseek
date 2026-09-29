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

  Future<List<FarmTask>> list(AuthorizationSubject subject) {
    _authorize(subject, PermissionCodes.taskView);
    return repository.listByFarm(subject.farmId);
  }
}
