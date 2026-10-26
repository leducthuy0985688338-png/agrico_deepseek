import '../../../core/permissions/live_authorization.dart';
import '../../../core/permissions/authorization.dart';
import '../domain/machines.dart';
export '../domain/machines.dart';

class MachineService {
  const MachineService(this.repository, {required this.currentSubject});
  final AuthorizationSubject? Function() currentSubject;
  LiveAuthorization get access => LiveAuthorization(currentSubject);
  final MachineRepository repository;
  bool can(AuthorizationSubject s, String permission) =>
      access.can(s, permission);
  void authorize(AuthorizationSubject s, String permission) {
    if (!can(s, permission)) throw StateError('Machine permission denied.');
  }

  Future<List<MachineCard>> machines(AuthorizationSubject s) {
    authorize(s, PermissionCodes.machineView);
    return access.read(s, [
      PermissionCodes.machineView,
    ], () => repository.machines(s.farmId));
  }

  Future<void> profile(
    AuthorizationSubject s,
    MachineCard m,
    Map<String, String> v,
  ) {
    authorize(s, PermissionCodes.machineMaintain);
    return repository.profile(s.farmId, m.id, m.revision, v, s.userId);
  }

  Future<List<MachineRate>> rates(AuthorizationSubject s) {
    authorize(s, PermissionCodes.financeView);
    authorize(s, PermissionCodes.machineView);
    return access.read(s, [
      PermissionCodes.financeView,
      PermissionCodes.machineView,
    ], () => repository.rates(s.farmId));
  }

  Future<void> addRate(AuthorizationSubject s, MachineRate rate) {
    authorize(s, PermissionCodes.machineAssign);
    authorize(s, PermissionCodes.financeApprove);
    return repository.addRate(s.farmId, rate, s.userId);
  }

  Future<List<MachineRecord<MachineRun>>> runs(AuthorizationSubject s) {
    authorize(s, PermissionCodes.machineView);
    final money = can(s, PermissionCodes.financeView);
    return access.read(s, [
      PermissionCodes.machineView,
      if (money) PermissionCodes.financeView,
    ], () => repository.runs(s.farmId, money: money));
  }

  Future<void> addRun(AuthorizationSubject s, MachineRun run) {
    authorize(s, PermissionCodes.machineLog);
    return repository.addRun(s.farmId, run, s.userId);
  }

  Future<void> approveRun(AuthorizationSubject s, MachineRecord<MachineRun> r) {
    authorize(s, PermissionCodes.machineVerify);
    authorize(s, PermissionCodes.financeView);
    return repository.approveRun(s.farmId, r.value.id, r.revision, s.userId);
  }

  Future<void> voidRun(
    AuthorizationSubject s,
    MachineRecord<MachineRun> r,
    String reason,
  ) {
    authorize(s, PermissionCodes.machineVerify);
    return repository.voidRun(
      s.farmId,
      r.value.id,
      r.revision,
      reason,
      s.userId,
    );
  }

  Future<List<MachineRecord<MachineExpense>>> expenses(AuthorizationSubject s) {
    authorize(s, PermissionCodes.machineView);
    authorize(s, PermissionCodes.financeView);
    return access.read(s, [
      PermissionCodes.financeView,
      PermissionCodes.machineView,
    ], () => repository.expenses(s.farmId));
  }

  Future<void> addExpense(AuthorizationSubject s, MachineExpense e) {
    authorize(
      s,
      e.kind == 'maintenance'
          ? PermissionCodes.machineMaintain
          : PermissionCodes.machineLog,
    );
    authorize(s, PermissionCodes.financeView);
    return repository.addExpense(s.farmId, e, s.userId);
  }

  Future<void> approveExpense(
    AuthorizationSubject s,
    MachineRecord<MachineExpense> e,
  ) {
    authorize(s, PermissionCodes.machineVerify);
    authorize(s, PermissionCodes.financeView);
    return repository.approveExpense(
      s.farmId,
      e.value.id,
      e.revision,
      s.userId,
    );
  }

  Future<void> voidExpense(
    AuthorizationSubject s,
    MachineRecord<MachineExpense> e,
    String reason,
  ) {
    authorize(s, PermissionCodes.machineVerify);
    authorize(s, PermissionCodes.financeView);
    return repository.voidExpense(
      s.farmId,
      e.value.id,
      e.revision,
      reason,
      s.userId,
    );
  }

  Future<List<Map<String, Object?>>> plans(AuthorizationSubject s) {
    authorize(s, PermissionCodes.machineView);
    return access.read(s, [
      PermissionCodes.machineView,
    ], () => repository.plans(s.farmId));
  }

  Future<List<Map<String, Object?>>> workers(AuthorizationSubject s) {
    authorize(s, PermissionCodes.machineView);
    return access.read(s, [
      PermissionCodes.machineView,
    ], () => repository.workers(s.farmId));
  }

  Future<List<ProductionMachineCost>> costs(AuthorizationSubject s) {
    authorize(s, PermissionCodes.machineView);
    authorize(s, PermissionCodes.financeView);
    return access.read(s, [
      PermissionCodes.machineView,
      PermissionCodes.financeView,
    ], () => repository.productionMachineCosts(s.farmId));
  }

  void exportPermission(AuthorizationSubject s) {
    authorize(s, PermissionCodes.reportOperations);
    authorize(s, PermissionCodes.dataExport);
    authorize(s, PermissionCodes.financeView);
  }
}
