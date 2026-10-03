import '../permissions/authorization.dart';
import '../permissions/company_roles.dart';

/// Only the server adapter may provide memberships used to open a session.
class CompanyMembership {
  CompanyMembership({required this.profile, required this.offlineUntil});
  final CompanyAccessProfile profile;
  final DateTime offlineUntil;

  factory CompanyMembership.fromJson(Map<String, dynamic> json) {
    String identity(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Invalid membership $key.');
      }
      return value;
    }

    Set<String> strings(String key) {
      final value = json[key] ?? <String>[];
      if (value is! List ||
          value.any((v) => v is! String || v.trim().isEmpty)) {
        throw FormatException('Invalid membership $key.');
      }
      return value.cast<String>().toSet();
    }

    Set<DataScope> scopes(dynamic raw) {
      if (raw is! List || raw.any((v) => v is! String)) {
        throw const FormatException('Invalid membership scopes.');
      }
      return raw
          .map(
            (v) => DataScope.values.firstWhere(
              (s) => s.name == v,
              orElse: () => throw const FormatException('Unknown scope.'),
            ),
          )
          .toSet();
    }

    final rawRoles = json['roles'];
    if (json['schemaVersion'] != 1 ||
        json['active'] is! bool ||
        rawRoles is! List) {
      throw const FormatException('Invalid membership schema.');
    }
    final deadline = DateTime.tryParse(identity('offlineUntil'));
    if (deadline == null || !deadline.isUtc) {
      throw const FormatException('Offline deadline must be UTC.');
    }
    final roles = <RoleAssignment>[];
    for (final raw in rawRoles) {
      if (raw is! Map || raw['role'] is! String) {
        throw const FormatException('Invalid role assignment.');
      }
      final role = CompanyRole.values.firstWhere(
        (r) => r.name == raw['role'],
        orElse: () => throw const FormatException('Unknown role.'),
      );
      roles.add(
        RoleAssignment(
          role,
          scopes: raw.containsKey('scopes') ? scopes(raw['scopes']) : null,
        ),
      );
    }
    return CompanyMembership(
      profile: CompanyAccessProfile(
        userId: identity('userId'),
        membershipId: identity('membershipId'),
        farmId: identity('farmId'),
        roles: roles,
        active: json['active'] as bool,
        extraPermissions: strings('extraPermissions'),
        deniedPermissions: strings('deniedPermissions'),
        extraPermissionScopes: scopes(
          json['extraPermissionScopes'] ?? <String>[],
        ),
        teamIds: strings('teamIds'),
        fieldIds: strings('fieldIds'),
        taskIds: strings('taskIds'),
        projectIds: strings('projectIds'),
        departmentIds: strings('departmentIds'),
        machineIds: strings('machineIds'),
        warehouseIds: strings('warehouseIds'),
        offlineValidUntil: deadline,
      ),
      offlineUntil: deadline,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'userId': profile.userId,
    'membershipId': profile.membershipId,
    'farmId': profile.farmId,
    'active': profile.active,
    'offlineUntil': offlineUntil.toUtc().toIso8601String(),
    'roles': [
      for (final r in profile.roles)
        {'role': r.role.name, 'scopes': r.scopes.map((s) => s.name).toList()},
    ],
    'extraPermissions': profile.extraPermissions.toList(),
    'deniedPermissions': profile.deniedPermissions.toList(),
    'extraPermissionScopes': profile.extraPermissionScopes
        .map((s) => s.name)
        .toList(),
    'teamIds': profile.teamIds.toList(),
    'fieldIds': profile.fieldIds.toList(),
    'taskIds': profile.taskIds.toList(),
    'projectIds': profile.projectIds.toList(),
    'departmentIds': profile.departmentIds.toList(),
    'machineIds': profile.machineIds.toList(),
    'warehouseIds': profile.warehouseIds.toList(),
  };
}
