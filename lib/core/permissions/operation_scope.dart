import 'authorization.dart';
import 'live_authorization.dart';

/// An immutable request identity with live, per-permission resource grants.
/// SQL identifiers below are internal constants; user IDs are quoted as values.
class OperationScope {
  const OperationScope(this.opened, this.live, this.permissions);
  final AuthorizationSubject opened;
  final LiveAuthorization live;
  final List<String> permissions;
  AuthorizationSubject get subject {
    final s = live.currentSubject();
    if (s == null ||
        s.userId != opened.userId ||
        s.membershipId != opened.membershipId ||
        s.farmId != opened.farmId ||
        !s.active ||
        (s.validUntil != null && !DateTime.now().isBefore(s.validUntil!))) {
      throw StateError('Active session required.');
    }
    return s;
  }

  bool allows(ResourceContext resource) {
    final s = subject;
    return permissions.every(
      (p) => const AuthorizationService().can(
        subject: s,
        permission: p,
        resource: resource,
      ),
    );
  }

  void require(ResourceContext resource) {
    if (!allows(resource)) throw StateError('Resource scope denied.');
  }

  static String quote(String v) => "'${v.replaceAll("'", "''")}'";
  String sql({String? machine, String? warehouse, String? department}) {
    final s = subject;
    String ids(String column, Set<String> values) =>
        values.isEmpty ? '0' : '$column IN (${values.map(quote).join(',')})';
    return permissions
        .map((p) {
          if (!s.permissionCodes.contains(p)) return '0';
          final grants = s.permissionScopes[p] ?? s.dataScopes;
          if (grants.contains(DataScope.allFarm)) return '1';
          final parts = <String>[
            if (machine != null && grants.contains(DataScope.assignedMachines))
              ids(machine, s.assignedMachineIds),
            if (warehouse != null &&
                grants.contains(DataScope.assignedWarehouses))
              ids(warehouse, s.assignedWarehouseIds),
            if (department != null && grants.contains(DataScope.department))
              ids(department, s.departmentIds),
          ];
          return parts.isEmpty ? '0' : '(${parts.join(' OR ')})';
        })
        .map((v) => '($v)')
        .join(' AND ');
  }

  bool get farmWide => sql() == permissions.map((_) => '(1)').join(' AND ');
}

/// Data repositories opt in explicitly. A non-scoped test/legacy repository
/// can only be used with farm-wide grants.
abstract interface class ScopedOperationRepository<T> {
  T scoped(OperationScope scope);
}
