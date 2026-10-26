import '../../../core/permissions/live_authorization.dart';
import '../../../core/permissions/authorization.dart';
import '../domain/personnel.dart';
export '../domain/personnel.dart';

class PersonnelService {
  const PersonnelService(this.repository, {required this.currentSubject});
  final AuthorizationSubject? Function() currentSubject;
  LiveAuthorization get access => LiveAuthorization(currentSubject);
  final PersonnelRepository repository;
  bool can(AuthorizationSubject s, String p) => access.can(s, p);
  void authorize(AuthorizationSubject s, String p) {
    if (!can(s, p)) throw StateError('Personnel permission denied.');
  }

  Future<List<EmployeeCard>> employees(AuthorizationSubject s) {
    authorize(s, PermissionCodes.employeeView);
    final sensitive = can(s, PermissionCodes.employeeEdit);
    return access.read(s, [
      PermissionCodes.employeeView,
      if (sensitive) PermissionCodes.employeeEdit,
    ], () => repository.employees(s.farmId, sensitive: sensitive));
  }

  Future<void> saveProfile(AuthorizationSubject s, EmployeeProfile profile) {
    authorize(s, PermissionCodes.employeeEdit);
    if (profile.farmId != s.farmId) throw StateError('Wrong farm.');
    profile.validate();
    return repository.saveProfile(profile, s.userId);
  }

  Future<List<PayRate>> rates(AuthorizationSubject s) {
    authorize(s, PermissionCodes.payrollView);
    return access.read(s, [
      PermissionCodes.payrollView,
    ], () => repository.rates(s.farmId));
  }

  Future<void> createRate(AuthorizationSubject s, PayRate rate) {
    authorize(s, PermissionCodes.payrollManage);
    if (rate.farmId != s.farmId) throw StateError('Wrong farm.');
    rate.validate();
    return repository.createRate(rate, s.userId);
  }

  Future<List<LaborEntryRecord>> entries(AuthorizationSubject s) {
    authorize(s, PermissionCodes.employeeView);
    final money = can(s, PermissionCodes.payrollView);
    return access.read(s, [
      PermissionCodes.employeeView,
      if (money) PermissionCodes.payrollView,
    ], () => repository.entries(s.farmId, money: money));
  }

  Future<void> createEntry(AuthorizationSubject s, LaborEntryDraft draft) {
    authorize(s, PermissionCodes.attendanceRecord);
    if (draft.farmId != s.farmId) throw StateError('Wrong farm.');
    draft.validate();
    return repository.createEntry(draft, s.userId);
  }

  Future<void> approveEntry(AuthorizationSubject s, LaborEntryRecord e) {
    authorize(s, PermissionCodes.attendanceVerify);
    authorize(s, PermissionCodes.payrollView);
    return repository.approveEntry(s.farmId, e.id, e.revision, s.userId);
  }

  Future<void> voidEntry(
    AuthorizationSubject s,
    LaborEntryRecord e,
    String reason,
  ) {
    authorize(s, PermissionCodes.attendanceVerify);
    return repository.voidEntry(s.farmId, e.id, e.revision, reason, s.userId);
  }

  Future<List<PayrollRecordV2>> payrolls(AuthorizationSubject s) {
    authorize(s, PermissionCodes.payrollView);
    return access.read(s, [
      PermissionCodes.payrollView,
    ], () => repository.payrolls(s.farmId));
  }

  Future<void> createPayroll(AuthorizationSubject s, PayrollDraft d) {
    authorize(s, PermissionCodes.payrollManage);
    if (d.farmId != s.farmId) throw StateError('Wrong farm.');
    d.validate();
    return repository.createPayroll(d, s.userId);
  }

  Future<void> approvePayroll(AuthorizationSubject s, String id) {
    authorize(s, PermissionCodes.payrollApprove);
    return repository.approvePayroll(s.farmId, id, s.userId);
  }

  Future<void> cancelPayroll(AuthorizationSubject s, String id, String reason) {
    authorize(s, PermissionCodes.payrollManage);
    return repository.cancelPayroll(s.farmId, id, reason, s.userId);
  }

  Future<void> recordPayment(
    AuthorizationSubject s, {
    required String id,
    required String payrollId,
    required String amount,
    required String currency,
    required String day,
    required String note,
  }) {
    authorize(s, PermissionCodes.payrollApprove);
    authorize(s, PermissionCodes.cashRecord);
    return repository.recordPayment(
      s.farmId,
      id,
      payrollId,
      amount,
      currency,
      day,
      note,
      s.userId,
    );
  }

  Future<List<PersonnelPlanChoice>> planChoices(AuthorizationSubject s) {
    authorize(s, PermissionCodes.employeeView);
    return access.read(s, [
      PermissionCodes.employeeView,
    ], () => repository.planChoices(s.farmId));
  }

  Future<List<PersonnelTaskChoice>> taskChoices(AuthorizationSubject s) {
    authorize(s, PermissionCodes.employeeView);
    return access.read(s, [
      PermissionCodes.employeeView,
    ], () => repository.taskChoices(s.farmId));
  }

  Future<List<SalaryPayment>> payments(AuthorizationSubject s) {
    authorize(s, PermissionCodes.payrollView);
    return access.read(s, [
      PermissionCodes.payrollView,
    ], () => repository.payments(s.farmId));
  }

  Future<List<ProductionLaborCost>> laborCosts(AuthorizationSubject s) {
    authorize(s, PermissionCodes.payrollView);
    final r = repository;
    if (r is! ProductionLaborCostRepository) {
      throw StateError('Labor projection unavailable.');
    }
    return access.read(
      s,
      [PermissionCodes.payrollView],
      () => (r as ProductionLaborCostRepository).productionLaborCosts(s.farmId),
    );
  }
}
