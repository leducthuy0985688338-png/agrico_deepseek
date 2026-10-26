import 'authorization.dart';

/// Revalidates the caller against the active session rather than a subject
/// captured when a page opened. This does not grant broader data scopes.
class LiveAuthorization {
  const LiveAuthorization(this.currentSubject);
  final AuthorizationSubject? Function() currentSubject;

  bool can(AuthorizationSubject opened, String permission) {
    final live = currentSubject();
    return live != null &&
        live.userId == opened.userId &&
        live.membershipId == opened.membershipId &&
        live.farmId == opened.farmId &&
        live.dataScopes.contains(DataScope.allFarm) &&
        const AuthorizationService().can(
          subject: live,
          permission: permission,
          resource: ResourceContext(farmId: live.farmId),
        );
  }

  void require(AuthorizationSubject opened, String permission) {
    if (!can(opened, permission)) {
      throw StateError('Active session permission denied.');
    }
  }

  /// Preserve synchronous preflight failures, and discard an in-flight read if
  /// its grants or session identity change before the result is returned.
  Future<T> read<T>(
    AuthorizationSubject opened,
    List<String> permissions,
    Future<T> Function() load,
  ) {
    for (final permission in permissions) {
      require(opened, permission);
    }
    return load().then((value) {
      for (final permission in permissions) {
        require(opened, permission);
      }
      return value;
    });
  }
}
