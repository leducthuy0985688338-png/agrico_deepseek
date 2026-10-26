import 'dart:convert';
import 'authorization.dart';

/// Revalidates the caller against the active session rather than a subject
/// captured when a page opened. This does not grant broader data scopes.
class LiveAuthorization {
  const LiveAuthorization(this.currentSubject);
  final AuthorizationSubject? Function() currentSubject;

  bool can(
    AuthorizationSubject opened,
    String permission, {
    ResourceContext? resource,
  }) {
    final live = currentSubject();
    return live != null &&
        live.userId == opened.userId &&
        live.membershipId == opened.membershipId &&
        live.farmId == opened.farmId &&
        const AuthorizationService().can(
          subject: live,
          permission: permission,
          resource: resource ?? ResourceContext(farmId: live.farmId),
        );
  }

  bool canEnter(AuthorizationSubject opened, String permission) {
    if (can(opened, permission)) return true;
    final s = currentSubject();
    if (s == null) return false;
    return [
      for (final id in s.assignedMachineIds)
        ResourceContext(farmId: s.farmId, machineId: id),
      for (final id in s.assignedWarehouseIds)
        ResourceContext(farmId: s.farmId, warehouseId: id),
      for (final id in s.departmentIds)
        ResourceContext(farmId: s.farmId, departmentId: id),
    ].any((r) => can(opened, permission, resource: r));
  }

  String _fingerprint(AuthorizationSubject opened) {
    final s = currentSubject();
    if (s == null ||
        s.userId != opened.userId ||
        s.membershipId != opened.membershipId ||
        s.farmId != opened.farmId)
      throw StateError('Session changed.');
    List<String> sorted(Iterable<Object> values) =>
        values.map((v) => v.toString()).toList()..sort();
    return jsonEncode([
      s.active,
      s.validUntil?.toIso8601String(),
      sorted(s.permissionCodes),
      sorted(s.dataScopes),
      sorted(s.assignedMachineIds),
      sorted(s.assignedWarehouseIds),
      sorted(s.departmentIds),
      [
        for (final key in s.permissionScopes.keys.toList()..sort())
          [key, sorted(s.permissionScopes[key]!)],
      ],
    ]);
  }

  String stamp(AuthorizationSubject opened) => _fingerprint(opened);
  void requireStamp(AuthorizationSubject opened, String expected) {
    final live = currentSubject();
    if (live == null ||
        !live.active ||
        (live.validUntil != null &&
            !DateTime.now().isBefore(live.validUntil!)) ||
        _fingerprint(opened) != expected)
      throw StateError('Session or scope changed.');
  }

  Future<T> readScoped<T>(
    AuthorizationSubject opened,
    List<String> permissions,
    Future<T> Function() load,
  ) {
    for (final p in permissions) {
      if (!canEnter(opened, p)) throw StateError('Scoped permission denied.');
    }
    final before = _fingerprint(opened);
    return load().then((v) {
      if (before != _fingerprint(opened) ||
          permissions.any((p) => !canEnter(opened, p)))
        throw StateError('Scope changed during read.');
      return v;
    });
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
