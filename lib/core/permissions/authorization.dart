/// Scope of business data visible to a farm membership.
enum DataScope {
  allFarm,
  team,
  assignedFields,
  assignedTasks,
  own,
  project,
  department,
  assignedMachines,
  assignedWarehouses,
}

/// Stable permission codes. UI and domain services share these identifiers,
/// but authorization decisions must be made below the presentation layer.
abstract final class PermissionCodes {
  static const fieldView = 'field.view';
  static const householdCreate = 'household.create';
  static const householdEdit = 'household.edit';
  static const fieldCreate = 'field.create';
  static const fieldEdit = 'field.edit';
  static const fieldDelete = 'field.delete';
  static const fieldMeasure = 'field.measure';
  static const fieldBoundaryEdit = 'field.boundary.edit';
  static const fieldBoundaryVerify = 'field.boundary.verify';
  static const fieldGoogleEarthImport = 'field.google_earth.import';
  static const fieldGoogleEarthExport = 'field.google_earth.export';
  static const taskView = 'task.view';
  static const taskCreate = 'task.create';
  static const taskEdit = 'task.edit';
  static const taskAssign = 'task.assign';
  static const taskComplete = 'task.complete';
  static const inventoryView = 'inventory.view';
  static const inventoryManage = 'inventory.manage';
  static const inventoryPrice = 'inventory.price';
  static const taskVerify = 'task.verify';
  static const chatView = 'chat.view';
  static const chatSend = 'chat.send';
  static const cloudSync = 'cloud.sync';
  static const cloudRestore = 'cloud.restore';
  static const administrativeCatalogManage = 'administrative_catalog.manage';
  static const localBackupExport = 'local_backup.export';

  static const accountView = 'account.view';
  static const accountManage = 'account.manage';
  static const roleManage = 'role.manage';
  static const catalogView = 'catalog.view';
  static const catalogManage = 'catalog.manage';
  static const catalogRequest = 'catalog.request';
  static const productionPlan = 'production.plan';
  static const productionApprove = 'production.approve';
  static const cropView = 'crop.view';
  static const cropEdit = 'crop.edit';
  static const machineView = 'machine.view';
  static const machineAssign = 'machine.assign';
  static const machineLog = 'machine.log';
  static const machineMaintain = 'machine.maintain';
  static const machineVerify = 'machine.verify';
  static const inventoryRequest = 'inventory.request';
  static const inventoryReceive = 'inventory.receive';
  static const inventoryIssue = 'inventory.issue';
  static const inventoryCount = 'inventory.count';
  static const inventoryAdjust = 'inventory.adjust';
  static const inventoryApprove = 'inventory.approve';
  static const purchaseView = 'purchase.view';
  static const purchaseRequest = 'purchase.request';
  static const purchaseEdit = 'purchase.edit';
  static const purchaseApprove = 'purchase.approve';
  static const financeView = 'finance.view';
  static const financeCreate = 'finance.create';
  static const financePost = 'finance.post';
  static const financeApprove = 'finance.approve';
  static const financeCorrect = 'finance.correct';
  static const cashView = 'cash.view';
  static const cashRecord = 'cash.record';
  static const employeeView = 'employee.view';
  static const employeeEdit = 'employee.edit';
  static const attendanceRecord = 'attendance.record';
  static const attendanceVerify = 'attendance.verify';
  static const payrollView = 'payroll.view';
  static const payrollManage = 'payroll.manage';
  static const payrollApprove = 'payroll.approve';
  static const officeView = 'office.view';
  static const officeEdit = 'office.edit';
  static const reportOperations = 'report.operations';
  static const reportFinance = 'report.finance';
  static const reportPersonnel = 'report.personnel';
  static const auditView = 'audit.view';
  static const auditReview = 'audit.review';
  static const dataExport = 'data.export';

  static const values = <String>{
    accountView,
    accountManage,
    roleManage,
    catalogView,
    catalogManage,
    catalogRequest,
    productionPlan,
    productionApprove,
    cropView,
    cropEdit,
    machineView,
    machineAssign,
    machineLog,
    machineMaintain,
    machineVerify,
    inventoryRequest,
    inventoryReceive,
    inventoryIssue,
    inventoryCount,
    inventoryAdjust,
    inventoryApprove,
    purchaseView,
    purchaseRequest,
    purchaseEdit,
    purchaseApprove,
    financeView,
    financeCreate,
    financePost,
    financeApprove,
    financeCorrect,
    cashView,
    cashRecord,
    employeeView,
    employeeEdit,
    attendanceRecord,
    attendanceVerify,
    payrollView,
    payrollManage,
    payrollApprove,
    officeView,
    officeEdit,
    reportOperations,
    reportFinance,
    reportPersonnel,
    auditView,
    auditReview,
    dataExport,
    fieldView,
    householdCreate,
    householdEdit,
    fieldCreate,
    fieldEdit,
    fieldDelete,
    fieldMeasure,
    fieldBoundaryEdit,
    fieldBoundaryVerify,
    fieldGoogleEarthImport,
    fieldGoogleEarthExport,
    taskView,
    taskCreate,
    taskEdit,
    taskAssign,
    taskComplete,
    inventoryView,
    inventoryManage,
    inventoryPrice,
    taskVerify,
    chatView,
    chatSend,
    cloudSync,
    cloudRestore,
    administrativeCatalogManage,
    localBackupExport,
  };
}

class AuthorizationSubject {
  const AuthorizationSubject({
    required this.userId,
    required this.membershipId,
    required this.farmId,
    required this.permissionCodes,
    required this.dataScopes,
    this.teamIds = const {},
    this.assignedFieldIds = const {},
    this.assignedTaskIds = const {},
    this.active = true,
    this.projectIds = const {},
    this.departmentIds = const {},
    this.assignedMachineIds = const {},
    this.assignedWarehouseIds = const {},
    this.permissionScopes = const {},
    this.validUntil,
  });

  final String userId;
  final String membershipId;
  final String farmId;
  final Set<String> permissionCodes;
  final Set<DataScope> dataScopes;
  final Set<String> teamIds;
  final Set<String> assignedFieldIds;
  final Set<String> assignedTaskIds;
  final bool active;

  /// Session deadline, checked again for every authorization decision.
  final DateTime? validUntil;
  final Set<String> projectIds;
  final Set<String> departmentIds;
  final Set<String> assignedMachineIds;
  final Set<String> assignedWarehouseIds;

  /// A present entry, including an empty set, overrides the legacy scope union.
  final Map<String, Set<DataScope>> permissionScopes;
}

class ResourceContext {
  const ResourceContext({
    required this.farmId,
    this.ownerUserId,
    this.teamId,
    this.fieldId,
    this.taskId,
    this.projectId,
    this.departmentId,
    this.machineId,
    this.warehouseId,
  });

  final String farmId;
  final String? ownerUserId;
  final String? teamId;
  final String? fieldId;
  final String? taskId;
  final String? projectId;
  final String? departmentId;
  final String? machineId;
  final String? warehouseId;
}

class AuthorizationService {
  const AuthorizationService({this.clock});
  final DateTime Function()? clock;

  bool can({
    required AuthorizationSubject subject,
    required String permission,
    required ResourceContext resource,
  }) {
    if (!subject.active ||
        (subject.validUntil != null &&
            !(clock ?? DateTime.now)().isBefore(subject.validUntil!)) ||
        subject.farmId != resource.farmId ||
        !subject.permissionCodes.contains(permission)) {
      return false;
    }

    final scopes = subject.permissionScopes[permission] ?? subject.dataScopes;
    return scopes.any((scope) {
      switch (scope) {
        case DataScope.allFarm:
          return true;
        case DataScope.team:
          return resource.teamId != null &&
              subject.teamIds.contains(resource.teamId);
        case DataScope.assignedFields:
          return resource.fieldId != null &&
              subject.assignedFieldIds.contains(resource.fieldId);
        case DataScope.assignedTasks:
          return resource.taskId != null &&
              subject.assignedTaskIds.contains(resource.taskId);
        case DataScope.own:
          return resource.ownerUserId != null &&
              resource.ownerUserId == subject.userId;
        case DataScope.project:
          return resource.projectId != null &&
              subject.projectIds.contains(resource.projectId);
        case DataScope.department:
          return resource.departmentId != null &&
              subject.departmentIds.contains(resource.departmentId);
        case DataScope.assignedMachines:
          return resource.machineId != null &&
              subject.assignedMachineIds.contains(resource.machineId);
        case DataScope.assignedWarehouses:
          return resource.warehouseId != null &&
              subject.assignedWarehouseIds.contains(resource.warehouseId);
      }
    });
  }
}
