import 'integration_service.dart';
import '../domain/production_cost_workflow.dart';
import '../../../core/permissions/authorization.dart';

class ProductionCostWorkflowService {
  const ProductionCostWorkflowService(this.store, this.access);
  final ProductionCostWorkflowStore store;
  final IntegrationService access;
  void require(String permission) {
    access.readAccess();
    access.require(permission);
  }

  Future<void> approveMaterial(String id, int revision) async {
    void check() {
      require(PermissionCodes.inventoryPrice);
      require(PermissionCodes.financeApprove);
    }

    check();
    return store.approveMaterial(
      access.subject.farmId,
      id,
      revision,
      access.subject.userId,
      check,
    );
  }

  Future<void> proposeExpense(ExpenseAllocationProposal proposal) async {
    void check() => require(PermissionCodes.financeCreate);
    check();
    proposal.validate();
    return store.proposeExpense(
      access.subject.farmId,
      proposal,
      access.subject.userId,
      check,
    );
  }

  Future<void> approveExpense(String id, int revision) async {
    void check() => require(PermissionCodes.financeApprove);
    check();
    return store.approveExpense(
      access.subject.farmId,
      id,
      revision,
      access.subject.userId,
      check,
    );
  }
}
