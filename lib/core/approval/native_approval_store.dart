import 'approval_policy.dart';

enum NativeApprovalType {
  finance,
  material,
  machineRun,
  machineExpense,
  fieldWork,
  payroll,
  payrollAdjustment,
  trade,
  expenseAllocation,
  command,
}

class NativeApprovalRef {
  const NativeApprovalRef(this.type, this.id);
  final NativeApprovalType type;
  final String id;
  String get key => '${type.name}:$id';
}

class NativeApprovalView {
  const NativeApprovalView(this.ref, this.source, this.decision, this.request);
  final NativeApprovalRef ref;
  final ApprovalContext source;
  final ApprovalDecision decision;
  final Map<String, Object?>? request;
}

abstract interface class NativeApprovalStore {
  String get actorId;
  bool canView([NativeApprovalView? item]);
  Future<List<NativeApprovalView>> list(Set<NativeApprovalType> types);
  Future<void> submit(NativeApprovalRef ref);
  Future<ApprovalDecision> approve(NativeApprovalRef ref, String reason);
  Future<void> reject(NativeApprovalRef ref, String reason);
  Future<List<Map<String, Object?>>> history(NativeApprovalRef ref);
  Future<void> proposeCommand({
    required String id,
    required String operation,
    required NativeApprovalRef target,
    required Map<String, Object?> payload,
  });
}
