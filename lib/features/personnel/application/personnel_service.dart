import '../../../core/permissions/operation_scope.dart';
import '../../../core/permissions/live_authorization.dart';
import '../../../core/permissions/authorization.dart';
import '../domain/personnel.dart';
export '../domain/personnel.dart';

class PersonnelService {
  const PersonnelService(this.repository, {required this.currentSubject});
  final AuthorizationSubject? Function() currentSubject;
  LiveAuthorization get access => LiveAuthorization(currentSubject);
  final PersonnelRepository repository;
  PersonnelRepository store(AuthorizationSubject s, List<String> permissions) {
    final scope = OperationScope(s, access, permissions);
    final r = repository;
    if (r is ScopedOperationRepository<PersonnelRepository>)
      return (r as ScopedOperationRepository<PersonnelRepository>).scoped(
        scope,
      );
    if (!scope.farmWide)
      throw StateError('Scoped personnel repository required.');
    return r;
  }

  Future<List<PersonnelDepartment>> departments(AuthorizationSubject s) {
    authorize(s, PermissionCodes.employeeView);
    final r = store(s, [PermissionCodes.employeeView]);
    if (r is! PersonnelOrganizationRepository) return Future.value([]);
    return access.readScoped(s, [
      PermissionCodes.employeeView,
    ], () => (r as PersonnelOrganizationRepository).departments(s.farmId));
  }

  Future<void> createDepartment(AuthorizationSubject s, PersonnelDepartment d) {
    access.require(s, PermissionCodes.employeeEdit);
    return (repository as PersonnelOrganizationRepository).createDepartment(
      s.farmId,
      d,
      s.userId,
    );
  }

  PersonnelService exporting(AuthorizationSubject s) => PersonnelService(
    store(s, [
      PermissionCodes.employeeView,
      PermissionCodes.payrollView,
      PermissionCodes.reportPersonnel,
      PermissionCodes.dataExport,
    ]),
    currentSubject: currentSubject,
  );
  bool can(AuthorizationSubject s, String p) => access.canEnter(s, p);
  void authorize(AuthorizationSubject s, String p) {
    if (!can(s, p)) throw StateError('Personnel permission denied.');
  }

  Future<List<EmployeeCard>> employees(AuthorizationSubject s) {
    authorize(s, PermissionCodes.employeeView);
    final sensitive = can(s, PermissionCodes.employeeSensitiveView);
    return access.readScoped(
      s,
      [
        PermissionCodes.employeeView,
        if (sensitive) PermissionCodes.employeeSensitiveView,
      ],
      () => store(s, [
        PermissionCodes.employeeView,
      ]).employees(s.farmId, sensitive: sensitive),
    );
  }

  Future<void> saveProfile(AuthorizationSubject s, EmployeeProfile profile) {
    authorize(s, PermissionCodes.employeeEdit);
    if (profile.farmId != s.farmId) throw StateError('Wrong farm.');
    profile.validate();
    if (profile.details.keys.any(EmployeeProfile.sensitiveFields.contains) &&
        !access.can(
          s,
          PermissionCodes.employeeSensitiveView,
          resource: ResourceContext(
            farmId: s.farmId,
            departmentId: profile.departmentId,
          ),
        ))
      throw StateError('Private fields require explicit access.');
    return store(s, [
      PermissionCodes.employeeEdit,
    ]).saveProfile(profile, s.userId);
  }

  Future<List<PayRate>> rates(AuthorizationSubject s) {
    authorize(s, PermissionCodes.payrollView);
    return access.readScoped(s, [
      PermissionCodes.payrollView,
    ], () => store(s, [PermissionCodes.payrollView]).rates(s.farmId));
  }

  Future<void> createRate(AuthorizationSubject s, PayRate rate) {
    authorize(s, PermissionCodes.payrollManage);
    if (rate.farmId != s.farmId) throw StateError('Wrong farm.');
    rate.validate();
    return store(s, [PermissionCodes.payrollManage]).createRate(rate, s.userId);
  }

  Future<List<LaborEntryRecord>> entries(AuthorizationSubject s) {
    authorize(s, PermissionCodes.employeeView);
    final money = can(s, PermissionCodes.payrollView);
    return access.readScoped(
      s,
      [PermissionCodes.employeeView, if (money) PermissionCodes.payrollView],
      () => store(s, [
        PermissionCodes.employeeView,
      ]).entries(s.farmId, money: money),
    );
  }

  Future<void> createEntry(AuthorizationSubject s, LaborEntryDraft draft) {
    authorize(s, PermissionCodes.attendanceRecord);
    if (draft.farmId != s.farmId) throw StateError('Wrong farm.');
    draft.validate();
    return store(s, [
      PermissionCodes.attendanceRecord,
    ]).createEntry(draft, s.userId);
  }

  Future<void> approveEntry(AuthorizationSubject s, LaborEntryRecord e) {
    authorize(s, PermissionCodes.attendanceVerify);
    authorize(s, PermissionCodes.payrollView);
    return store(s, [
      PermissionCodes.attendanceVerify,
      PermissionCodes.payrollView,
    ]).approveEntry(s.farmId, e.id, e.revision, s.userId);
  }

  Future<void> voidEntry(
    AuthorizationSubject s,
    LaborEntryRecord e,
    String reason,
  ) {
    authorize(s, PermissionCodes.attendanceVerify);
    return store(s, [
      PermissionCodes.attendanceVerify,
    ]).voidEntry(s.farmId, e.id, e.revision, reason, s.userId);
  }

  Future<List<PayrollRecordV2>> payrolls(AuthorizationSubject s) {
    authorize(s, PermissionCodes.payrollView);
    return access.readScoped(s, [
      PermissionCodes.payrollView,
    ], () => store(s, [PermissionCodes.payrollView]).payrolls(s.farmId));
  }

  Future<void> createPayroll(AuthorizationSubject s, PayrollDraft d) {
    authorize(s, PermissionCodes.payrollManage);
    if (d.farmId != s.farmId) throw StateError('Wrong farm.');
    d.validate();
    return store(s, [PermissionCodes.payrollManage]).createPayroll(d, s.userId);
  }

  Future<void> approvePayroll(AuthorizationSubject s, String id) {
    authorize(s, PermissionCodes.payrollApprove);
    return store(s, [
      PermissionCodes.payrollApprove,
    ]).approvePayroll(s.farmId, id, s.userId);
  }

  Future<void> cancelPayroll(AuthorizationSubject s, String id, String reason) {
    authorize(s, PermissionCodes.payrollManage);
    return store(s, [
      PermissionCodes.payrollManage,
    ]).cancelPayroll(s.farmId, id, reason, s.userId);
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
    return store(s, [
      PermissionCodes.payrollApprove,
      PermissionCodes.cashRecord,
    ]).recordPayment(
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
    return access.readScoped(s, [
      PermissionCodes.employeeView,
    ], () => store(s, [PermissionCodes.employeeView]).planChoices(s.farmId));
  }

  Future<List<PersonnelTaskChoice>> taskChoices(AuthorizationSubject s) {
    authorize(s, PermissionCodes.employeeView);
    return access.readScoped(s, [
      PermissionCodes.employeeView,
    ], () => store(s, [PermissionCodes.employeeView]).taskChoices(s.farmId));
  }

  Future<List<SalaryPayment>> payments(AuthorizationSubject s) {
    authorize(s, PermissionCodes.payrollView);
    return access.readScoped(s, [
      PermissionCodes.payrollView,
    ], () => store(s, [PermissionCodes.payrollView]).payments(s.farmId));
  }

  Future<List<ProductionLaborCost>> laborCosts(AuthorizationSubject s) {
    authorize(s, PermissionCodes.payrollView);
    final r = store(s, [PermissionCodes.payrollView]);
    if (r is! ProductionLaborCostRepository) {
      throw StateError('Labor projection unavailable.');
    }
    return access.readScoped(
      s,
      [PermissionCodes.payrollView],
      () => (r as ProductionLaborCostRepository).productionLaborCosts(s.farmId),
    );
  }
}
