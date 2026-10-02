import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/permissions/company_roles.dart';

final now = DateTime.utc(2026, 10, 2);
CompanyAccessProfile profile(
  List<CompanyRole> roles, {
  Set<String> denied = const {},
  Set<String> extra = const {},
  Set<DataScope> extraScopes = const {},
  DateTime? deadline,
  bool active = true,
}) => CompanyAccessProfile(
  userId: 'user',
  membershipId: 'member',
  farmId: 'farm',
  roles: roles.map((r) => RoleAssignment(r)).toList(),
  deniedPermissions: denied,
  extraPermissions: extra,
  extraPermissionScopes: extraScopes,
  active: active,
  offlineValidUntil: deadline,
  projectIds: {'project'},
  departmentIds: {'department'},
  teamIds: {'team'},
  fieldIds: {'field'},
  taskIds: {'task'},
  machineIds: {'machine'},
  warehouseIds: {'warehouse'},
);
bool allowed(
  CompanyAccessProfile p,
  String permission,
  ResourceContext resource,
) => const AuthorizationService().can(
  subject: p.subject(now: now),
  permission: permission,
  resource: resource,
);
const farm = ResourceContext(farmId: 'farm');
void main() {
  for (final role in CompanyRole.values) {
    test('$role only uses registered permissions', () {
      expect(
        PermissionCodes.values.containsAll(CompanyRolePolicy.permissions(role)),
        isTrue,
      );
      expect(CompanyRolePolicy.defaultScopes(role), isNotEmpty);
    });
    if (role != CompanyRole.systemAdmin) {
      test('$role cannot manage catalogs by default', () {
        expect(
          CompanyRolePolicy.permissions(role),
          isNot(contains(PermissionCodes.catalogManage)),
        );
        expect(
          CompanyRolePolicy.permissions(role),
          isNot(contains(PermissionCodes.accountManage)),
        );
      });
    }
  }
  test('admin catalog access does not grant business approval', () {
    final p = profile([CompanyRole.systemAdmin]);
    expect(allowed(p, PermissionCodes.catalogManage, farm), isTrue);
    expect(allowed(p, PermissionCodes.financeApprove, farm), isFalse);
  });
  test('combining admin and operator does not broaden task access', () {
    final p = profile([CompanyRole.systemAdmin, CompanyRole.machineOperator]);
    expect(
      allowed(
        p,
        PermissionCodes.taskComplete,
        const ResourceContext(farmId: 'farm', taskId: 'task'),
      ),
      isTrue,
    );
    expect(
      allowed(
        p,
        PermissionCodes.taskComplete,
        const ResourceContext(
          farmId: 'farm',
          taskId: 'other',
          machineId: 'machine',
        ),
      ),
      isFalse,
    );
    expect(
      allowed(
        p,
        PermissionCodes.machineLog,
        const ResourceContext(farmId: 'farm', machineId: 'machine'),
      ),
      isTrue,
    );
    expect(
      allowed(
        p,
        PermissionCodes.machineLog,
        const ResourceContext(farmId: 'farm', machineId: 'other'),
      ),
      isFalse,
    );
  });
  test('worker attendance is personal', () {
    final p = profile([CompanyRole.fieldWorker]);
    expect(
      allowed(
        p,
        PermissionCodes.attendanceRecord,
        const ResourceContext(farmId: 'farm', ownerUserId: 'user'),
      ),
      isTrue,
    );
    expect(
      allowed(
        p,
        PermissionCodes.attendanceRecord,
        const ResourceContext(
          farmId: 'farm',
          ownerUserId: 'other',
          taskId: 'task',
        ),
      ),
      isFalse,
    );
  });
  test('warehouse is restricted to assigned warehouse', () {
    final p = profile([CompanyRole.warehouseKeeper]);
    expect(
      allowed(
        p,
        PermissionCodes.inventoryReceive,
        const ResourceContext(farmId: 'farm', warehouseId: 'warehouse'),
      ),
      isTrue,
    );
    expect(
      allowed(
        p,
        PermissionCodes.inventoryReceive,
        const ResourceContext(farmId: 'farm', warehouseId: 'other'),
      ),
      isFalse,
    );
    expect(
      allowed(
        p,
        PermissionCodes.inventoryAdjust,
        const ResourceContext(farmId: 'farm', warehouseId: 'warehouse'),
      ),
      isFalse,
    );
  });
  test('project and department scopes require matching identifiers', () {
    expect(
      allowed(
        profile([CompanyRole.gisOfficer]),
        PermissionCodes.fieldView,
        const ResourceContext(farmId: 'farm', projectId: 'project'),
      ),
      isTrue,
    );
    expect(
      allowed(
        profile([CompanyRole.gisOfficer]),
        PermissionCodes.fieldView,
        farm,
      ),
      isFalse,
    );
    expect(
      allowed(
        profile([CompanyRole.accountant]),
        PermissionCodes.financePost,
        const ResourceContext(farmId: 'farm', departmentId: 'department'),
      ),
      isTrue,
    );
    expect(
      allowed(
        profile([CompanyRole.accountant]),
        PermissionCodes.financePost,
        const ResourceContext(farmId: 'farm', departmentId: 'other'),
      ),
      isFalse,
    );
  });
  test('accountant cannot approve, pay or read payroll by default', () {
    final permissions = CompanyRolePolicy.permissions(CompanyRole.accountant);
    for (final code in [
      PermissionCodes.financeApprove,
      PermissionCodes.cashRecord,
      PermissionCodes.payrollView,
    ]) {
      expect(permissions, isNot(contains(code)));
    }
  });
  test('deny overrides both role and explicit grant', () {
    final p = profile(
      [CompanyRole.systemAdmin],
      extra: {PermissionCodes.catalogManage},
      extraScopes: {DataScope.allFarm},
      denied: {PermissionCodes.catalogManage},
    );
    expect(allowed(p, PermissionCodes.catalogManage, farm), isFalse);
  });
  test('extra grants require a scope', () {
    expect(
      allowed(
        profile([], extra: {PermissionCodes.catalogManage}),
        PermissionCodes.catalogManage,
        farm,
      ),
      isFalse,
    );
    expect(
      allowed(
        profile(
          [],
          extra: {PermissionCodes.catalogManage},
          extraScopes: {DataScope.allFarm},
        ),
        PermissionCodes.catalogManage,
        farm,
      ),
      isTrue,
    );
  });
  test('cross farm and inactive membership are denied', () {
    expect(
      allowed(
        profile([CompanyRole.systemAdmin]),
        PermissionCodes.catalogManage,
        const ResourceContext(farmId: 'other'),
      ),
      isFalse,
    );
    expect(
      allowed(
        profile([CompanyRole.systemAdmin], active: false),
        PermissionCodes.catalogManage,
        farm,
      ),
      isFalse,
    );
  });
  test('offline deadline expires exactly at boundary', () {
    expect(
      allowed(
        profile([CompanyRole.systemAdmin], deadline: now),
        PermissionCodes.catalogManage,
        farm,
      ),
      isFalse,
    );
    expect(
      allowed(
        profile([
          CompanyRole.systemAdmin,
        ], deadline: now.add(const Duration(seconds: 1))),
        PermissionCodes.catalogManage,
        farm,
      ),
      isTrue,
    );
  });
  test('approval rejects author and requires approval permission', () {
    final subject = profile([CompanyRole.director]).subject(now: now);
    bool approve(String author, String code) => ApprovalPolicy.canApprove(
      subject: subject,
      resource: farm,
      createdByUserId: author,
      permission: code,
    );
    expect(approve('user', PermissionCodes.financeApprove), isFalse);
    expect(approve('', PermissionCodes.financeApprove), isFalse);
    expect(approve('other', PermissionCodes.financeView), isFalse);
    expect(approve('other', PermissionCodes.financeApprove), isTrue);
  });
  test('empty assignment and explicit empty scope fail closed', () {
    final p = CompanyAccessProfile(
      userId: 'u',
      membershipId: 'm',
      farmId: 'farm',
      roles: [RoleAssignment(CompanyRole.systemAdmin, scopes: {})],
    );
    expect(allowed(p, PermissionCodes.catalogManage, farm), isFalse);
    const subject = AuthorizationSubject(
      userId: 'u',
      membershipId: 'm',
      farmId: 'farm',
      permissionCodes: {PermissionCodes.fieldView},
      dataScopes: {DataScope.allFarm},
      permissionScopes: {PermissionCodes.fieldView: {}},
    );
    expect(
      const AuthorizationService().can(
        subject: subject,
        permission: PermissionCodes.fieldView,
        resource: farm,
      ),
      isFalse,
    );
  });
  test('legacy subjects retain scope behavior', () {
    const subject = AuthorizationSubject(
      userId: 'u',
      membershipId: 'm',
      farmId: 'farm',
      permissionCodes: {PermissionCodes.fieldView},
      dataScopes: {DataScope.allFarm},
    );
    expect(
      const AuthorizationService().can(
        subject: subject,
        permission: PermissionCodes.fieldView,
        resource: farm,
      ),
      isTrue,
    );
  });
  test(
    'profile copies mutable input and rejects invalid identities or permissions',
    () {
      final roles = [RoleAssignment(CompanyRole.systemAdmin)];
      final denied = <String>{};
      final p = CompanyAccessProfile(
        userId: 'u',
        membershipId: 'm',
        farmId: 'farm',
        roles: roles,
        deniedPermissions: denied,
      );
      roles.clear();
      denied.add(PermissionCodes.catalogManage);
      expect(allowed(p, PermissionCodes.catalogManage, farm), isTrue);
      expect(() => p.roles.clear(), throwsUnsupportedError);
      expect(
        () => CompanyAccessProfile(
          userId: '',
          membershipId: 'm',
          farmId: 'farm',
          roles: [],
        ),
        throwsFormatException,
      );
      expect(() => profile([], extra: {'unknown'}), throwsFormatException);
    },
  );
}
