import '../permissions/authorization.dart';

class LocalBackupPermissionException implements Exception {
  const LocalBackupPermissionException();
}

/// The snapshot includes the whole local database, so narrow scopes cannot
/// authorize it. Resolve the live session again at each execution boundary.
class LocalBackupAccess {
  const LocalBackupAccess({required this.currentSubject});
  final AuthorizationSubject? Function() currentSubject;

  bool can(String permission) {
    final subject = currentSubject();
    return subject != null &&
        subject.farmId == 'local-farm' &&
        subject.validUntil != null &&
        const AuthorizationService().can(
          subject: subject,
          permission: permission,
          resource: const ResourceContext(farmId: 'local-farm'),
        );
  }

  bool get canOpen => can(PermissionCodes.localBackupExport) ||
      can(PermissionCodes.cloudRestore);

  void require(String permission) {
    if (!can(permission)) throw const LocalBackupPermissionException();
  }

  void requireOpen() {
    if (!canOpen) throw const LocalBackupPermissionException();
  }

  Future<T> execute<T>(String permission, Future<T> Function() operation) {
    require(permission);
    return operation();
  }
}
