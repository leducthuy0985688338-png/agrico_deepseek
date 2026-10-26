import '../../../core/permissions/operation_scope.dart';
import '../../../core/permissions/live_authorization.dart';
import '../../../core/permissions/authorization.dart';
import '../domain/machines.dart';
export '../domain/machines.dart';

class MachineService {
  const MachineService(this.repository, {required this.currentSubject});
  final AuthorizationSubject? Function() currentSubject;
  LiveAuthorization get access => LiveAuthorization(currentSubject);
  final MachineRepository repository;
  MachineRepository store(AuthorizationSubject s, List<String> permissions) {
    final scope = OperationScope(s, access, permissions);
    final r = repository;
    if (r is ScopedOperationRepository<MachineRepository>)
      return (r as ScopedOperationRepository<MachineRepository>).scoped(scope);
    if (!scope.farmWide)
      throw StateError('Scoped machine repository required.');
    return r;
  }

  MachineService exporting(AuthorizationSubject s) => MachineService(
    store(s, [
      PermissionCodes.machineView,
      PermissionCodes.financeView,
      PermissionCodes.reportOperations,
      PermissionCodes.dataExport,
    ]),
    currentSubject: currentSubject,
  );
  bool can(AuthorizationSubject s, String permission) =>
      access.canEnter(s, permission);
  void authorize(AuthorizationSubject s, String permission) {
    if (!can(s, permission)) throw StateError('Machine permission denied.');
  }

  Future<List<MachineCard>> machines(AuthorizationSubject s) {
    authorize(s, PermissionCodes.machineView);
    return access.readScoped(s, [
      PermissionCodes.machineView,
    ], () => store(s, [PermissionCodes.machineView]).machines(s.farmId));
  }

  Future<void> profile(
    AuthorizationSubject s,
    MachineCard m,
    Map<String, String> v,
  ) {
    authorize(s, PermissionCodes.machineMaintain);
    return store(s, [
      PermissionCodes.machineMaintain,
    ]).profile(s.farmId, m.id, m.revision, v, s.userId);
  }

  Future<List<MachineRate>> rates(AuthorizationSubject s) {
    authorize(s, PermissionCodes.financeView);
    authorize(s, PermissionCodes.machineView);
    return access.readScoped(
      s,
      [PermissionCodes.financeView, PermissionCodes.machineView],
      () => store(s, [
        PermissionCodes.machineView,
        PermissionCodes.financeView,
      ]).rates(s.farmId),
    );
  }

  Future<void> addRate(AuthorizationSubject s, MachineRate rate) {
    authorize(s, PermissionCodes.machineAssign);
    authorize(s, PermissionCodes.financeApprove);
    return store(s, [
      PermissionCodes.machineAssign,
      PermissionCodes.financeApprove,
    ]).addRate(s.farmId, rate, s.userId);
  }

  Future<List<MachineRecord<MachineRun>>> runs(AuthorizationSubject s) {
    authorize(s, PermissionCodes.machineView);
    final money = can(s, PermissionCodes.financeView);
    return access.readScoped(
      s,
      [PermissionCodes.machineView, if (money) PermissionCodes.financeView],
      () =>
          store(s, [PermissionCodes.machineView]).runs(s.farmId, money: money),
    );
  }

  Future<void> addRun(AuthorizationSubject s, MachineRun run) {
    authorize(s, PermissionCodes.machineLog);
    return store(s, [
      PermissionCodes.machineLog,
    ]).addRun(s.farmId, run, s.userId);
  }

  Future<void> approveRun(AuthorizationSubject s, MachineRecord<MachineRun> r) {
    authorize(s, PermissionCodes.machineVerify);
    authorize(s, PermissionCodes.financeView);
    return store(s, [
      PermissionCodes.machineVerify,
      PermissionCodes.financeView,
    ]).approveRun(s.farmId, r.value.id, r.revision, s.userId);
  }

  Future<void> voidRun(
    AuthorizationSubject s,
    MachineRecord<MachineRun> r,
    String reason,
  ) {
    authorize(s, PermissionCodes.machineVerify);
    return store(s, [
      PermissionCodes.machineVerify,
    ]).voidRun(s.farmId, r.value.id, r.revision, reason, s.userId);
  }

  Future<List<MachineRecord<MachineExpense>>> expenses(AuthorizationSubject s) {
    authorize(s, PermissionCodes.machineView);
    authorize(s, PermissionCodes.financeView);
    return access.readScoped(
      s,
      [PermissionCodes.financeView, PermissionCodes.machineView],
      () => store(s, [
        PermissionCodes.machineView,
        PermissionCodes.financeView,
      ]).expenses(s.farmId),
    );
  }

  Future<void> addExpense(AuthorizationSubject s, MachineExpense e) {
    authorize(
      s,
      e.kind == 'maintenance'
          ? PermissionCodes.machineMaintain
          : PermissionCodes.machineLog,
    );
    authorize(s, PermissionCodes.financeView);
    return store(s, [
      e.kind == 'maintenance'
          ? PermissionCodes.machineMaintain
          : PermissionCodes.machineLog,
      PermissionCodes.financeView,
    ]).addExpense(s.farmId, e, s.userId);
  }

  Future<void> approveExpense(
    AuthorizationSubject s,
    MachineRecord<MachineExpense> e,
  ) {
    authorize(s, PermissionCodes.machineVerify);
    authorize(s, PermissionCodes.financeView);
    return store(s, [
      PermissionCodes.machineVerify,
      PermissionCodes.financeView,
    ]).approveExpense(s.farmId, e.value.id, e.revision, s.userId);
  }

  Future<void> voidExpense(
    AuthorizationSubject s,
    MachineRecord<MachineExpense> e,
    String reason,
  ) {
    authorize(s, PermissionCodes.machineVerify);
    authorize(s, PermissionCodes.financeView);
    return store(s, [
      PermissionCodes.machineVerify,
      PermissionCodes.financeView,
    ]).voidExpense(s.farmId, e.value.id, e.revision, reason, s.userId);
  }

  Future<List<Map<String, Object?>>> plans(AuthorizationSubject s) {
    authorize(s, PermissionCodes.machineView);
    return access.readScoped(s, [
      PermissionCodes.machineView,
    ], () => store(s, [PermissionCodes.machineView]).plans(s.farmId));
  }

  Future<List<Map<String, Object?>>> workers(AuthorizationSubject s) {
    authorize(s, PermissionCodes.machineView);
    return access.readScoped(s, [
      PermissionCodes.machineView,
    ], () => store(s, [PermissionCodes.machineView]).workers(s.farmId));
  }

  Future<List<ProductionMachineCost>> costs(AuthorizationSubject s) {
    authorize(s, PermissionCodes.machineView);
    authorize(s, PermissionCodes.financeView);
    return access.readScoped(
      s,
      [PermissionCodes.machineView, PermissionCodes.financeView],
      () => store(s, [
        PermissionCodes.machineView,
        PermissionCodes.financeView,
      ]).productionMachineCosts(s.farmId),
    );
  }

  void exportPermission(AuthorizationSubject s) {
    authorize(s, PermissionCodes.reportOperations);
    authorize(s, PermissionCodes.dataExport);
    authorize(s, PermissionCodes.financeView);
  }
}
