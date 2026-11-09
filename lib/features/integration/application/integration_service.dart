import '../domain/integration_store.dart';
import '../../../core/approval/approval_administration.dart';
import '../../../core/approval/approval_policy.dart';
import '../domain/production_cost_workflow.dart';
import '../../../core/permissions/authorization.dart';
import '../domain/integration_snapshot.dart';
import '../../trade/domain/trade.dart' show MoneyRounding;
export '../domain/integration_snapshot.dart';

class IntegrationService {
  const IntegrationService({
    required this.repository,
    required this.subject,
    required this.currentSubject,
    this.productionCosts,
    this.approvalPolicies,
  });
  final IntegrationStore repository;
  final ProductionCostWorkflowStore? productionCosts;
  final ApprovalAdministration? approvalPolicies;
  final AuthorizationSubject subject;
  final AuthorizationSubject? Function() currentSubject;
  static const readPermissions = {
    PermissionCodes.financeView,
    PermissionCodes.cashView,
    PermissionCodes.catalogView,
    PermissionCodes.employeeView,
    PermissionCodes.employeeEdit,
    PermissionCodes.payrollView,
    PermissionCodes.machineView,
    PermissionCodes.fieldView,
    PermissionCodes.inventoryView,
    PermissionCodes.reportFinance,
    PermissionCodes.reportPersonnel,
    PermissionCodes.reportOperations,
  };
  bool can(String permission) {
    final s = currentSubject();
    return s != null &&
        s.userId == subject.userId &&
        s.membershipId == subject.membershipId &&
        s.farmId == subject.farmId &&
        s.dataScopes.contains(DataScope.allFarm) &&
        const AuthorizationService().can(
          subject: s,
          permission: permission,
          resource: ResourceContext(farmId: s.farmId),
        );
  }

  void require(String p) {
    if (!can(p)) throw StateError('Integrated report permission denied.');
  }

  bool get canAdministerApproval =>
      approvalPolicies != null &&
      [
        ApprovalRules.policyManage,
        ApprovalRules.policyActivate,
        ApprovalRules.auditView,
      ].any(can);
  bool get canView => readPermissions.every(can);
  void readAccess() {
    for (final p in readPermissions) require(p);
  }

  void exportAccess() {
    readAccess();
    require(PermissionCodes.dataExport);
  }

  Future<IntegrationSnapshot> snapshot(String period) async {
    readAccess();
    final result = await repository.snapshot(subject.farmId, period);
    readAccess();
    return result;
  }

  Future<List<String>> reconcile() async {
    readAccess();
    final result = await repository.reconcile(subject.farmId);
    readAccess();
    return result;
  }

  Future<void> linkSalary(String id, {String? cashId}) {
    require(PermissionCodes.cashRecord);
    require(PermissionCodes.payrollApprove);
    readAccess();
    return repository.linkSalary(
      subject.farmId,
      id,
      subject.userId,
      existingFinanceId: cashId,
    );
  }

  Future<void> reverseSalary(
    String payment,
    String id,
    String day,
    String reason,
  ) {
    require(PermissionCodes.payrollApprove);
    require(PermissionCodes.cashRecord);
    require(PermissionCodes.financeCorrect);
    readAccess();
    return repository.reverseSalary(
      subject.farmId,
      payment,
      id,
      day,
      reason,
      subject.userId,
    );
  }

  Future<void> machinePayable(
    String expense,
    String supplier,
    String reference,
    MoneyRounding rounding, {
    String? document,
  }) {
    require(PermissionCodes.financeApprove);
    require(PermissionCodes.financePost);
    require(PermissionCodes.financeCreate);
    require(PermissionCodes.machineVerify);
    readAccess();
    return repository.machinePayable(
      subject.farmId,
      expense,
      supplier,
      reference,
      rounding,
      subject.userId,
      existingDocumentId: document,
    );
  }

  Future<void> fuelIssue(
    String expense,
    String item,
    String price,
    bool zero, {
    String? movement,
  }) {
    require(PermissionCodes.inventoryIssue);
    require(PermissionCodes.inventoryPrice);
    require(PermissionCodes.machineVerify);
    readAccess();
    return repository.fuelIssue(
      subject.farmId,
      expense,
      item,
      price,
      zero,
      subject.userId,
      existingMovementId: movement,
    );
  }

  Future<void> reverseFuel(String expense, String day, String reason) {
    require(PermissionCodes.inventoryAdjust);
    require(PermissionCodes.inventoryPrice);
    require(PermissionCodes.machineVerify);
    readAccess();
    return repository.reverseFuel(
      subject.farmId,
      expense,
      day,
      reason,
      subject.userId,
    );
  }

  Future<void> metadata(
    String kind,
    String id,
    int revision,
    Map<String, String> values,
  ) {
    require(
      kind == 'stock'
          ? PermissionCodes.inventoryManage
          : kind == 'capital'
          ? PermissionCodes.financeCorrect
          : kind == 'run'
          ? PermissionCodes.machineVerify
          : kind == 'worker'
          ? PermissionCodes.employeeEdit
          : kind == 'machine' || kind == 'maintenance'
          ? PermissionCodes.machineMaintain
          : kind == 'payroll'
          ? PermissionCodes.payrollManage
          : PermissionCodes.financeApprove,
    );
    readAccess();
    return repository.metadata(
      subject.farmId,
      kind,
      id,
      revision,
      values,
      subject.userId,
    );
  }
}
