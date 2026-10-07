import 'authorization.dart';

enum CompanyRole {
  systemAdmin,
  director,
  operationsManager,
  departmentManager,
  teamLeader,
  agronomist,
  gisOfficer,
  machineOperator,
  fieldWorker,
  equipmentCoordinator,
  warehouseKeeper,
  purchasingOfficer,
  accountant,
  cashier,
  hrOfficer,
  officeStaff,
  auditor,
}

/// Role templates are responsibilities, not job seniority. Explicit grants are
/// added by trusted account management; a deny always overrides the union.
abstract final class CompanyRolePolicy {
  static Set<String> permissions(CompanyRole role) => Set.unmodifiable({
    PermissionCodes.catalogView,
    PermissionCodes.chatView,
    if (role != CompanyRole.auditor) PermissionCodes.chatSend,
    if (role != CompanyRole.auditor) PermissionCodes.catalogRequest,
    PermissionCodes.cloudSync,
    ...switch (role) {
      CompanyRole.systemAdmin => PermissionCodes.values,
      CompanyRole.director => const {
        PermissionCodes.fieldView,
        PermissionCodes.cropView,
        PermissionCodes.taskView,
        PermissionCodes.machineView,
        PermissionCodes.inventoryView,
        PermissionCodes.purchaseView,
        PermissionCodes.financeView,
        PermissionCodes.productionApprove,
        PermissionCodes.purchaseApprove,
        PermissionCodes.financeApprove,
        PermissionCodes.inventoryApprove,
        PermissionCodes.payrollApprove,
        PermissionCodes.reportOperations,
        PermissionCodes.reportFinance,
        PermissionCodes.reportPersonnel,
        PermissionCodes.auditView,
        PermissionCodes.dataExport,
      },
      CompanyRole.operationsManager => const {
        PermissionCodes.fieldView,
        PermissionCodes.cropView,
        PermissionCodes.taskView,
        PermissionCodes.taskCreate,
        PermissionCodes.taskEdit,
        PermissionCodes.taskAssign,
        PermissionCodes.taskVerify,
        PermissionCodes.productionPlan,
        PermissionCodes.productionApprove,
        PermissionCodes.machineView,
        PermissionCodes.machineAssign,
        PermissionCodes.inventoryView,
        PermissionCodes.inventoryRequest,
        PermissionCodes.purchaseRequest,
        PermissionCodes.attendanceVerify,
        PermissionCodes.reportOperations,
      },
      CompanyRole.departmentManager => const {
        PermissionCodes.taskView,
        PermissionCodes.taskCreate,
        PermissionCodes.taskEdit,
        PermissionCodes.taskAssign,
        PermissionCodes.taskVerify,
        PermissionCodes.attendanceVerify,
        PermissionCodes.officeView,
        PermissionCodes.officeEdit,
        PermissionCodes.purchaseRequest,
        PermissionCodes.reportOperations,
      },
      CompanyRole.teamLeader => const {
        PermissionCodes.fieldView,
        PermissionCodes.cropView,
        PermissionCodes.taskView,
        PermissionCodes.taskAssign,
        PermissionCodes.taskEdit,
        PermissionCodes.taskVerify,
        PermissionCodes.attendanceRecord,
        PermissionCodes.attendanceVerify,
        PermissionCodes.machineView,
        PermissionCodes.inventoryRequest,
      },
      CompanyRole.agronomist => const {
        PermissionCodes.fieldView,
        PermissionCodes.cropView,
        PermissionCodes.cropEdit,
        PermissionCodes.taskView,
        PermissionCodes.taskCreate,
        PermissionCodes.taskEdit,
        PermissionCodes.taskComplete,
        PermissionCodes.inventoryRequest,
        PermissionCodes.attendanceRecord,
      },
      CompanyRole.gisOfficer => const {
        PermissionCodes.fieldView,
        PermissionCodes.fieldCreate,
        PermissionCodes.fieldMeasure,
        PermissionCodes.fieldBoundaryEdit,
        PermissionCodes.fieldGoogleEarthImport,
        PermissionCodes.fieldGoogleEarthExport,
        PermissionCodes.taskView,
        PermissionCodes.taskComplete,
      },
      CompanyRole.machineOperator => const {
        PermissionCodes.taskView,
        PermissionCodes.taskComplete,
        PermissionCodes.fieldView,
        PermissionCodes.machineView,
        PermissionCodes.machineLog,
        PermissionCodes.attendanceRecord,
      },
      CompanyRole.fieldWorker => const {
        PermissionCodes.taskView,
        PermissionCodes.taskComplete,
        PermissionCodes.attendanceRecord,
      },
      CompanyRole.equipmentCoordinator => const {
        PermissionCodes.machineView,
        PermissionCodes.machineAssign,
        PermissionCodes.machineMaintain,
        PermissionCodes.machineVerify,
        PermissionCodes.taskView,
        PermissionCodes.taskCreate,
        PermissionCodes.taskAssign,
        PermissionCodes.taskVerify,
        PermissionCodes.inventoryRequest,
        PermissionCodes.reportOperations,
      },
      CompanyRole.warehouseKeeper => const {
        PermissionCodes.inventoryView,
        PermissionCodes.inventoryReceive,
        PermissionCodes.inventoryIssue,
        PermissionCodes.inventoryCount,
        PermissionCodes.taskView,
        PermissionCodes.taskComplete,
      },
      CompanyRole.purchasingOfficer => const {
        PermissionCodes.purchaseView,
        PermissionCodes.purchaseRequest,
        PermissionCodes.purchaseEdit,
        PermissionCodes.inventoryView,
        PermissionCodes.taskView,
        PermissionCodes.taskComplete,
      },
      CompanyRole.accountant => const {
        PermissionCodes.financeView,
        PermissionCodes.financeCreate,
        PermissionCodes.financePost,
        PermissionCodes.financeCorrect,
        PermissionCodes.reportFinance,
        PermissionCodes.purchaseView,
        PermissionCodes.inventoryView,
        PermissionCodes.cashView,
      },
      CompanyRole.cashier => const {
        PermissionCodes.cashView,
        PermissionCodes.cashRecord,
      },
      CompanyRole.hrOfficer => const {
        PermissionCodes.employeeView,
        PermissionCodes.employeeEdit,
        PermissionCodes.attendanceRecord,
        PermissionCodes.attendanceVerify,
        PermissionCodes.reportPersonnel,
        PermissionCodes.officeView,
        PermissionCodes.officeEdit,
      },
      CompanyRole.officeStaff => const {
        PermissionCodes.officeView,
        PermissionCodes.officeEdit,
        PermissionCodes.taskView,
        PermissionCodes.taskComplete,
        PermissionCodes.purchaseRequest,
        PermissionCodes.attendanceRecord,
      },
      CompanyRole.auditor => const {
        PermissionCodes.fieldView,
        PermissionCodes.cropView,
        PermissionCodes.taskView,
        PermissionCodes.machineView,
        PermissionCodes.inventoryView,
        PermissionCodes.purchaseView,
        PermissionCodes.financeView,
        PermissionCodes.cashView,
        PermissionCodes.reportOperations,
        PermissionCodes.reportFinance,
        PermissionCodes.auditView,
        PermissionCodes.auditReview,
      },
    },
  });

  static Set<DataScope> defaultScopes(CompanyRole role) => switch (role) {
    CompanyRole.systemAdmin ||
    CompanyRole.director => const {DataScope.allFarm},
    CompanyRole.operationsManager ||
    CompanyRole.gisOfficer => const {DataScope.project},
    CompanyRole.departmentManager ||
    CompanyRole.accountant ||
    CompanyRole.cashier ||
    CompanyRole.hrOfficer ||
    CompanyRole.purchasingOfficer => const {DataScope.department},
    CompanyRole.teamLeader => const {DataScope.team},
    CompanyRole.agronomist => const {
      DataScope.assignedFields,
      DataScope.assignedTasks,
      DataScope.own,
    },
    CompanyRole.machineOperator => const {
      DataScope.assignedMachines,
      DataScope.assignedTasks,
      DataScope.assignedFields,
      DataScope.own,
    },
    CompanyRole.equipmentCoordinator => const {
      DataScope.assignedMachines,
      DataScope.team,
    },
    CompanyRole.warehouseKeeper => const {DataScope.assignedWarehouses},
    CompanyRole.fieldWorker ||
    CompanyRole.officeStaff => const {DataScope.assignedTasks, DataScope.own},
    CompanyRole.auditor => const {DataScope.project},
  };

  /// A machine assignment must not grant access to every task on that machine.
  static Set<DataScope> scopesFor(
    CompanyRole role,
    String permission,
    Set<DataScope> assigned,
  ) {
    if (assigned.isEmpty) {
      return const {};
    }
    if (role == CompanyRole.systemAdmin) {
      return assigned;
    }
    if (permission == PermissionCodes.catalogView ||
        permission == PermissionCodes.cloudSync) {
      return const {DataScope.allFarm};
    }
    if (permission == PermissionCodes.catalogRequest) {
      return const {DataScope.own};
    }
    if (role == CompanyRole.machineOperator) {
      if (permission == PermissionCodes.taskView ||
          permission == PermissionCodes.taskComplete) {
        return const {DataScope.assignedTasks, DataScope.own};
      }
      if (permission == PermissionCodes.machineView ||
          permission == PermissionCodes.machineLog) {
        return const {DataScope.assignedMachines};
      }
      if (permission == PermissionCodes.fieldView) {
        return const {DataScope.assignedFields};
      }
      if (permission == PermissionCodes.attendanceRecord) {
        return const {DataScope.own};
      }
    }
    if ((role == CompanyRole.fieldWorker || role == CompanyRole.officeStaff) &&
        permission == PermissionCodes.attendanceRecord) {
      return const {DataScope.own};
    }
    return assigned;
  }
}

class RoleAssignment {
  RoleAssignment(this.role, {Set<DataScope>? scopes})
    : scopes = Set.unmodifiable(
        scopes ?? CompanyRolePolicy.defaultScopes(role),
      );
  final CompanyRole role;
  final Set<DataScope> scopes;
}

/// Pure authorization snapshot. This is not a login session, a password record
/// or proof that cached rights came from the company server.
class CompanyAccessProfile {
  CompanyAccessProfile({
    required this.userId,
    required this.membershipId,
    required this.farmId,
    required List<RoleAssignment> roles,
    this.active = true,
    Set<String> extraPermissions = const {},
    Set<String> deniedPermissions = const {},
    Set<DataScope> extraPermissionScopes = const {},
    Set<String> teamIds = const {},
    Set<String> fieldIds = const {},
    Set<String> taskIds = const {},
    Set<String> projectIds = const {},
    Set<String> departmentIds = const {},
    Set<String> machineIds = const {},
    Set<String> warehouseIds = const {},
    this.offlineValidUntil,
  }) : roles = List.unmodifiable(roles),
       extraPermissions = Set.unmodifiable(extraPermissions),
       deniedPermissions = Set.unmodifiable(deniedPermissions),
       extraPermissionScopes = Set.unmodifiable(extraPermissionScopes),
       teamIds = Set.unmodifiable(teamIds),
       fieldIds = Set.unmodifiable(fieldIds),
       taskIds = Set.unmodifiable(taskIds),
       projectIds = Set.unmodifiable(projectIds),
       departmentIds = Set.unmodifiable(departmentIds),
       machineIds = Set.unmodifiable(machineIds),
       warehouseIds = Set.unmodifiable(warehouseIds) {
    if ([userId, membershipId, farmId].any((v) => v.trim().isEmpty) ||
        !PermissionCodes.values.containsAll(extraPermissions) ||
        !PermissionCodes.values.containsAll(deniedPermissions)) {
      throw const FormatException('Invalid access profile.');
    }
  }
  final String userId, membershipId, farmId;
  final bool active;
  final List<RoleAssignment> roles;
  final Set<String> extraPermissions, deniedPermissions;
  final Set<DataScope> extraPermissionScopes;
  final Set<String> teamIds,
      fieldIds,
      taskIds,
      projectIds,
      departmentIds,
      machineIds,
      warehouseIds;
  final DateTime? offlineValidUntil;

  AuthorizationSubject subject({required DateTime now}) {
    final permissions = <String>{};
    final scoped = <String, Set<DataScope>>{};
    for (final assignment in roles) {
      for (final permission in CompanyRolePolicy.permissions(assignment.role)) {
        permissions.add(permission);
        scoped
            .putIfAbsent(permission, () => <DataScope>{})
            .addAll(
              CompanyRolePolicy.scopesFor(
                assignment.role,
                permission,
                assignment.scopes,
              ),
            );
      }
    }
    for (final permission in extraPermissions) {
      permissions.add(permission);
      scoped
          .putIfAbsent(permission, () => <DataScope>{})
          .addAll(extraPermissionScopes);
    }
    permissions.removeAll(deniedPermissions);
    final enabled =
        active &&
        (offlineValidUntil == null || now.isBefore(offlineValidUntil!));
    return AuthorizationSubject(
      userId: userId,
      membershipId: membershipId,
      farmId: farmId,
      active: enabled,
      permissionCodes: Set.unmodifiable(permissions),
      permissionScopes: Map.unmodifiable({
        for (final entry in scoped.entries)
          entry.key: Set<DataScope>.unmodifiable(entry.value),
      }),
      dataScopes: Set.unmodifiable({
        ...roles.expand((r) => r.scopes),
        ...extraPermissionScopes,
      }),
      teamIds: teamIds,
      assignedFieldIds: fieldIds,
      assignedTaskIds: taskIds,
      projectIds: projectIds,
      departmentIds: departmentIds,
      assignedMachineIds: machineIds,
      assignedWarehouseIds: warehouseIds,
    );
  }
}

/// Completion submission and approval are distinct operations. Only services
/// handling those workflows can supply the actual document author from storage.
abstract final class ApprovalPolicy {
  static bool canApprove({
    required AuthorizationSubject subject,
    required ResourceContext resource,
    required String createdByUserId,
    required String permission,
  }) {
    if (!approvalPermissions.contains(permission) ||
        createdByUserId.trim().isEmpty ||
        createdByUserId == subject.userId) {
      return false;
    }
    return const AuthorizationService().can(
      subject: subject,
      permission: permission,
      resource: resource,
    );
  }

  static const approvalPermissions = {
    PermissionCodes.taskVerify,
    PermissionCodes.productionApprove,
    PermissionCodes.financeApprove,
    PermissionCodes.purchaseApprove,
    PermissionCodes.inventoryApprove,
    PermissionCodes.payrollApprove,
    PermissionCodes.attendanceVerify,
    PermissionCodes.machineVerify,
  };
}
