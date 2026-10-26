import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/catalog/company_catalog.dart';
import '../../../core/catalog/company_catalog_screen.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/permissions/authorization.dart';
import '../../../services/report_file_saver.dart';
import '../application/personnel_service.dart';
import '../application/personnel_report.dart';

String _id(String kind) =>
    '$kind-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

class PersonnelWorkspaceScreen extends StatefulWidget {
  const PersonnelWorkspaceScreen({
    super.key,
    required this.service,
    required this.subject,
    this.catalog,
  });
  final PersonnelService service;
  final AuthorizationSubject subject;
  final CompanyCatalogService? catalog;
  @override
  State<PersonnelWorkspaceScreen> createState() => _PersonnelWorkspaceState();
}

class _PersonnelData {
  const _PersonnelData(
    this.employees,
    this.entries,
    this.rates,
    this.payrolls,
    this.payments,
    this.costs,
    this.plans,
    this.tasks,
    this.machines,
    this.workTypes,
    this.units,
    this.departments,
    this.adjustments,
    this.refunds,
  );
  final List<EmployeeCard> employees;
  final List<LaborEntryRecord> entries;
  final List<PayRate> rates;
  final List<PayrollRecordV2> payrolls;
  final List<SalaryPayment> payments;
  final List<ProductionLaborCost> costs;
  final List<PersonnelPlanChoice> plans;
  final List<PersonnelTaskChoice> tasks;
  final List<CatalogEntry> machines, workTypes, units;
  final List<PersonnelDepartment> departments;
  final List<PayrollAdjustmentRecord> adjustments;
  final List<PayrollRefund> refunds;
}

class _PersonnelWorkspaceState extends State<PersonnelWorkspaceScreen> {
  late Future<_PersonnelData> data;
  final period = TextEditingController(
    text: LaborMoney.day(DateTime.now()).substring(0, 7),
  );
  String? workerId;
  bool busy = false;
  bool can(String code) => widget.service.can(widget.subject, code);
  bool get salary => can(PermissionCodes.payrollView);
  @override
  void initState() {
    super.initState();
    data = load();
    data.ignore();
  }

  @override
  void dispose() {
    period.dispose();
    super.dispose();
  }

  Future<_PersonnelData> load({bool exporting = false}) async {
    final stamp = widget.service.access.stamp(widget.subject);
    final service = exporting
        ? widget.service.exporting(widget.subject)
        : widget.service;
    final people = await service.employees(widget.subject);
    final entries = await service.entries(widget.subject);
    final rates = salary ? await service.rates(widget.subject) : <PayRate>[];
    final payroll = salary
        ? await service.payrolls(widget.subject)
        : <PayrollRecordV2>[];
    final payments = salary
        ? await service.payments(widget.subject)
        : <SalaryPayment>[];
    final costs = salary
        ? await service.laborCosts(widget.subject)
        : <ProductionLaborCost>[];
    final plans = await service.planChoices(widget.subject);
    final tasks = await service.taskChoices(widget.subject);
    final catalog =
        widget.catalog == null ||
            !widget.service.access.can(
              widget.subject,
              PermissionCodes.catalogView,
            )
        ? <CatalogEntry>[]
        : await widget.catalog!.entries();
    final machines = catalog
        .where((c) => c.kind == CatalogKind.machine && c.active)
        .toList();
    final workTypes = catalog
        .where((c) => c.kind == CatalogKind.taskType && c.active)
        .toList();
    final departments = await service.departments(widget.subject);
    final adjustments = salary
        ? await service.payrollAdjustments(widget.subject)
        : <PayrollAdjustmentRecord>[];
    final refunds = salary
        ? await service.payrollRefunds(widget.subject)
        : <PayrollRefund>[];
    widget.service.access.requireStamp(widget.subject, stamp);
    return _PersonnelData(
      people,
      entries,
      rates,
      payroll,
      payments,
      costs,
      plans,
      tasks,
      machines,
      workTypes,
      catalog.where((c) => c.kind == CatalogKind.unit && c.active).toList(),
      departments,
      adjustments,
      refunds,
    );
  }

  void reload() {
    final next = load();
    setState(() {
      data = next;
    });
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_failure(context, e))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> form(
    String title,
    List<_Field> Function(Map<String, String>) fields,
    Future<void> Function(Map<String, String>) save, {
    Map<String, String> initial = const {},
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PersonnelForm(
        title: title,
        fields: fields,
        save: save,
        initial: initial,
      ),
    );
    if (mounted && saved == true) reload();
  }

  Map<String, String> people(_PersonnelData d, {bool activeOnly = true}) => {
    for (final e in d.employees.where((e) => !activeOnly || e.active))
      e.workerId: '${e.code} · ${e.name}',
  };
  Future<void> viewProfile(EmployeeCard selected) async {
    try {
      final records = await widget.service.employees(widget.subject);
      if (!mounted) return;
      final current = records
          .where((e) => e.workerId == selected.workerId)
          .firstOrNull;
      if (current == null) throw StateError('Profile unavailable.');
      final l = AppLocalizations.of(context);
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('${current.code} · ${current.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final key in EmployeeProfile.fields)
                  if ((current.profile?.details[key] ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: SelectableText(
                        '${l.text('hr.profile.$key')}: ${current.profile!.details[key]}',
                      ),
                    ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(l.text('hr.close')),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_failure(context, e))));
    }
  }

  bool employeeAccess(_PersonnelData d, String worker, String permission) =>
      widget.service.access.can(
        widget.subject,
        permission,
        resource: ResourceContext(
          farmId: widget.subject.farmId,
          departmentId: d.employees
              .where((e) => e.workerId == worker)
              .firstOrNull
              ?.profile
              ?.departmentId,
        ),
      );
  void profile(EmployeeCard e, _PersonnelData d) {
    form(
      'hr.profile',
      (_) => [
        for (final key in EmployeeProfile.fields.where(
          (k) =>
              k != 'department' &&
              (!EmployeeProfile.sensitiveFields.contains(k) ||
                  employeeAccess(
                    d,
                    e.workerId,
                    PermissionCodes.employeeSensitiveView,
                  )),
        ))
          _Field(key, 'hr.profile.$key'),
        _Field(
          'departmentId',
          'hr.profile.department',
          choices: {
            '': AppLocalizations.of(context).text('hr.none'),
            for (final dept in d.departments) dept.id: dept.name,
          },
        ),
      ],
      (v) => widget.service.saveProfile(
        widget.subject,
        EmployeeProfile(
          workerId: e.workerId,
          farmId: widget.subject.farmId,
          details: Map.from(v)..remove('departmentId'),
          departmentId: (v['departmentId'] ?? '').isEmpty
              ? null
              : v['departmentId'],
          revision: e.profile?.revision ?? 0,
        ),
      ),
      initial: {
        ...?e.profile?.details,
        'departmentId': e.profile?.departmentId ?? '',
      },
    );
  }

  void addDepartment() {
    form(
      'hr.department.create',
      (_) => [_Field('name', 'hr.profile.department')],
      (v) => widget.service.createDepartment(
        widget.subject,
        PersonnelDepartment(_id('department'), v['name'] ?? ''),
      ),
    );
  }

  void rate(_PersonnelData d) {
    final id = _id('pay-rate');
    form(
      'hr.addRate',
      (v) => [
        _Field('worker', 'hr.employee', choices: people(d)),
        _Field(
          'workType',
          'hr.workType',
          choices: {
            '': AppLocalizations.of(context).text('hr.none'),
            for (final t in d.workTypes) t.id: t.name,
          },
        ),
        _Field('effective', 'hr.effective'),
        _Field(
          'basis',
          'hr.basis',
          choices: {
            for (final b in PayBasis.values)
              b.name: AppLocalizations.of(context).text('hr.basis.${b.name}'),
          },
        ),
        const _Field('rate', 'hr.rate', number: true),
        const _Field(
          'currency',
          'hr.currency',
          choices: {'VND': 'VND', 'LAK': 'LAK'},
        ),
        const _Field('ot', 'hr.otRate', number: true),
        const _Field('standard', 'hr.standardMinutes', number: true),
        if (v['basis'] == 'piece')
          _Field(
            'unit',
            'hr.pieceUnit',
            choices: {for (final u in d.units) u.name: u.name},
          ),
        _Field(
          'round',
          'hr.rounding',
          choices: {
            'halfUp': AppLocalizations.of(context).text('hr.roundHalf'),
            'down': AppLocalizations.of(context).text('hr.roundDown'),
          },
        ),
        _Field(
          'scale',
          'hr.precision',
          choices: {for (var i = 0; i <= 6; i++) '$i': '$i'},
        ),
      ],
      (v) => widget.service.createRate(
        widget.subject,
        PayRate(
          id: id,
          farmId: widget.subject.farmId,
          workerId: v['worker'] ?? '',
          effectiveOn: v['effective'] ?? '',
          basis: PayBasis.values.byName(v['basis'] ?? ''),
          rate: v['rate'] ?? '',
          currency: v['currency'] ?? '',
          overtimeHourlyRate: (v['ot'] ?? '').isEmpty ? null : v['ot'],
          standardMinutes: int.parse(v['standard'] ?? ''),
          moneyScale: int.parse(v['scale'] ?? ''),
          rounding: MoneyRounding.values.byName(v['round'] ?? ''),
          pieceUnit: v['basis'] == 'piece' ? v['unit'] ?? '' : '',
          workTypeId: v['workType'] ?? '',
        ),
      ),
      initial: {
        'worker': workerId ?? '',
        'effective': LaborMoney.day(DateTime.now()),
        'standard': '480',
      },
    );
  }

  void attendance(_PersonnelData d) {
    final id = _id('attendance');
    final today = LaborMoney.day(DateTime.now());
    form(
      'hr.addEntry',
      (v) {
        final plans = {
          for (final p in d.plans.where(
            (p) =>
                (v['day'] ?? today).compareTo(p.startsOn) >= 0 &&
                (v['day'] ?? today).compareTo(p.endsOn) <= 0,
          ))
            p.id: '${p.label} (${p.currency})',
        };
        return [
          _Field('worker', 'hr.employee', choices: people(d)),
          _Field(
            'workType',
            'hr.workType',
            choices: {
              '': AppLocalizations.of(context).text('hr.none'),
              for (final t in d.workTypes) t.id: t.name,
            },
          ),
          const _Field('day', 'hr.startDay'),
          const _Field('start', 'hr.startTime'),
          const _Field('endDay', 'hr.endDay'),
          const _Field('end', 'hr.endTime'),
          const _Field('break', 'hr.break', number: true),
          const _Field('ot', 'hr.overtimeMinutes', number: true),
          _Field(
            'basis',
            'hr.basis',
            choices: {
              for (final b in PayBasis.values)
                b.name: AppLocalizations.of(context).text('hr.basis.${b.name}'),
            },
          ),
          const _Field('piece', 'hr.pieceQuantity', number: true),
          _Field(
            'pieceUnit',
            'hr.pieceUnit',
            choices: {
              '': AppLocalizations.of(context).text('hr.none'),
              for (final u in d.units) u.name: u.name,
            },
          ),
          const _Field('output', 'hr.outputQuantity', number: true),
          _Field(
            'outputUnit',
            'hr.outputUnit',
            choices: {
              '': AppLocalizations.of(context).text('hr.none'),
              for (final u in d.units) u.name: u.name,
            },
          ),
          _Field(
            'machine',
            'hr.machineIncluded',
            choices: {
              '': AppLocalizations.of(context).text('hr.none'),
              for (final m in d.machines) m.id: '${m.code} · ${m.name}',
            },
          ),
          _Field(
            'plan',
            'hr.plan1',
            choices: {
              '': AppLocalizations.of(context).text('hr.unallocated'),
              ...plans,
            },
          ),
          if ((v['plan'] ?? '').isNotEmpty) ...[
            const _Field('normal1', 'hr.normalAllocation', number: true),
            const _Field('ot1', 'hr.otAllocation', number: true),
            _Field(
              'task',
              'hr.task',
              choices: {
                '': AppLocalizations.of(context).text('hr.none'),
                for (final t in d.tasks.where(
                  (t) =>
                      t.planId == v['plan'] &&
                      (t.workerId == null || t.workerId == v['worker']),
                ))
                  t.id: t.label,
              },
            ),
          ],
          _Field(
            'plan2',
            'hr.plan2',
            choices: {
              '': AppLocalizations.of(context).text('hr.none'),
              ...plans,
            },
          ),
          if ((v['plan2'] ?? '').isNotEmpty) ...[
            const _Field('normal2', 'hr.normalAllocation2', number: true),
            const _Field('ot2', 'hr.otAllocation2', number: true),
          ],
          const _Field('note', 'hr.note'),
        ];
      },
      (v) {
        DateTime time(String day, String value) {
          if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(value)) {
            throw const FormatException('Invalid time.');
          }
          LaborMoney.date(day);
          final parts = value.split(':').map(int.parse).toList();
          if (parts[0] > 23 || parts[1] > 59) {
            throw const FormatException('Invalid time.');
          }
          return DateTime.parse('${day}T$value:00+07:00').toUtc();
        }

        final start = time(v['day'] ?? '', v['start'] ?? ''),
            end = time(v['endDay'] ?? '', v['end'] ?? '');
        final pause = int.parse(v['break'] ?? '0'),
            ot = int.parse(v['ot'] ?? '0');
        final normal = end.difference(start).inMinutes - pause - ot;
        int minutes(String key, int fallback) =>
            (v[key] ?? '').isEmpty ? fallback : int.parse(v[key]!);
        final plan = v['plan'] ?? '',
            plan2 = v['plan2'] ?? '',
            task = v['task'] ?? '',
            machine = v['machine'] ?? '';
        return widget.service.createEntry(
          widget.subject,
          LaborEntryDraft(
            id: id,
            farmId: widget.subject.farmId,
            workerId: v['worker'] ?? '',
            startsAt: start,
            endsAt: end,
            breakMinutes: pause,
            overtimeMinutes: ot,
            pieceQuantity: (v['piece'] ?? '').isEmpty ? null : v['piece'],
            requestedBasis: (v['basis'] ?? '').isEmpty
                ? null
                : PayBasis.values.byName(v['basis']!),
            requestedPieceUnit: v['pieceUnit'] ?? '',
            workTypeId: v['workType'] ?? '',
            outputQuantity: (v['output'] ?? '').isEmpty ? null : v['output'],
            outputUnit: (v['outputUnit'] ?? '').isEmpty
                ? null
                : v['outputUnit'],
            machineId: machine.isEmpty ? null : machine,
            notes: v['note'] ?? '',
            allocations: [
              if (plan.isNotEmpty)
                LaborAllocationDraft(
                  planId: plan,
                  regularMinutes: minutes('normal1', normal),
                  overtimeMinutes: minutes('ot1', ot),
                  taskId: task.isEmpty ? null : task,
                ),
              if (plan2.isNotEmpty)
                LaborAllocationDraft(
                  planId: plan2,
                  regularMinutes: minutes('normal2', 0),
                  overtimeMinutes: minutes('ot2', 0),
                ),
            ],
          ),
        );
      },
      initial: {
        'worker': workerId ?? '',
        'day': today,
        'endDay': today,
        'start': '08:00',
        'end': '17:00',
        'break': '60',
        'ot': '0',
      },
    );
  }

  void payroll(_PersonnelData d) {
    final id = _id('payroll');
    form(
      'hr.addPayroll',
      (v) => [
        _Field('worker', 'hr.employee', choices: people(d, activeOnly: false)),
        const _Field('period', 'hr.period'),
        const _Field(
          'currency',
          'hr.currency',
          choices: {'VND': 'VND', 'LAK': 'LAK'},
        ),
        for (final k in ['allowance', 'bonus', 'advance', 'deduction'])
          _Field(k, 'hr.$k', number: true),
        _Field(
          'plan',
          'hr.extraPlan',
          choices: {
            '': AppLocalizations.of(context).text('hr.unallocated'),
            for (final p in d.plans.where((p) => p.currency == v['currency']))
              p.id: p.label,
          },
        ),
        const _Field('note', 'hr.adjustmentNote'),
      ],
      (v) => widget.service.createPayroll(
        widget.subject,
        PayrollDraft(
          id: id,
          farmId: widget.subject.farmId,
          workerId: v['worker'] ?? '',
          period: v['period'] ?? '',
          currency: v['currency'] ?? '',
          allowance: v['allowance'] ?? '0',
          bonus: v['bonus'] ?? '0',
          advance: v['advance'] ?? '0',
          deduction: v['deduction'] ?? '0',
          note: v['note'] ?? '',
          adjustmentPlanId: (v['plan'] ?? '').isEmpty ? null : v['plan'],
        ),
      ),
      initial: {
        'worker': workerId ?? '',
        'period': period.text.trim(),
        'allowance': '0',
        'bonus': '0',
        'advance': '0',
        'deduction': '0',
      },
    );
  }

  Future<void> adjustment(PayrollRecordV2 p) async {
    try {
      final choices = await widget.service.payrollAdjustmentPlans(
        widget.subject,
        p.id,
      );
      if (!mounted) return;
      final adjustmentId = _id('payroll-adjustment');
      await form(
        'hr.adjustment.create',
        (v) => [
          _Field(
            'kind',
            'hr.adjustment.kind',
            choices: {
              'earnings': AppLocalizations.of(
                context,
              ).text('hr.adjustment.earnings'),
              'deduction': AppLocalizations.of(
                context,
              ).text('hr.adjustment.deduction'),
            },
          ),
          const _Field(
            'delta',
            'hr.adjustment.delta',
            number: true,
            signed: true,
          ),
          const _Field('day', 'hr.adjustment.day'),
          const _Field('reason', 'hr.reason'),
          if ((v['kind'] ?? 'earnings') == 'earnings') ...[
            _Field(
              'allocation',
              'hr.adjustment.treatment',
              choices: {
                'unallocated': AppLocalizations.of(
                  context,
                ).text('hr.unallocated'),
                'plans': AppLocalizations.of(
                  context,
                ).text('hr.adjustment.allocate'),
              },
            ),
            if (v['allocation'] == 'plans')
              for (final plan in choices)
                _Field(
                  'cost:${plan.id}',
                  plan.label,
                  number: true,
                  signed: true,
                  literalLabel: true,
                ),
          ],
        ],
        (v) => widget.service.createPayrollAdjustment(
          widget.subject,
          PayrollAdjustmentDraft(
            id: adjustmentId,
            farmId: widget.subject.farmId,
            payrollId: p.id,
            currency: p.currency,
            day: v['day'] ?? '',
            delta: v['delta'] ?? '',
            reason: v['reason'] ?? '',
            expectedRevision: p.adjustmentRevision,
            kind: PayrollAdjustmentKind.values.byName(v['kind'] ?? 'earnings'),
            allocations: [
              if (v['kind'] == 'earnings' && v['allocation'] == 'plans')
                for (final plan in choices)
                  if ((v['cost:${plan.id}'] ?? '').isNotEmpty &&
                      ExactDecimal.parse(v['cost:${plan.id}']!).coefficient !=
                          BigInt.zero)
                    PayrollCostAdjustment(plan.id, v['cost:${plan.id}']!),
            ],
          ),
        ),
        initial: {
          'kind': 'earnings',
          'allocation': 'unallocated',
          'day': LaborMoney.day(DateTime.now()),
        },
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_failure(context, e))));
    }
  }

  Future<void> approveAdjustment(PayrollAdjustmentRecord old) => run(() async {
    final fresh = (await widget.service.payrollAdjustments(
      widget.subject,
    )).singleWhere((a) => a.draft.id == old.draft.id);
    final p = (await widget.service.payrolls(
      widget.subject,
    )).singleWhere((p) => p.id == fresh.draft.payrollId);
    if (p.adjustmentRevision != fresh.draft.expectedRevision)
      throw StateError('Stale adjustment.');
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final after = LaborMoney.sum([p.effectiveNet, fresh.draft.delta]);
    final over = ExactDecimal.parse(LaborMoney.minus(p.paid, after));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.text('hr.adjustment.approve')),
        content: SingleChildScrollView(
          child: Text(
            '${p.code} · ${p.workerName}\n${l.text('hr.adjustment.before')}: ${p.effectiveNet} ${p.currency}\n${l.text('hr.adjustment.delta')}: ${fresh.draft.delta}\n${l.text('hr.adjustment.after')}: $after\n${l.text('hr.paid')}: ${p.paid}\n${l.text('hr.adjustment.overpaid')}: ${over.isNegative ? '0' : over}\n${l.text('hr.adjustment.cost')}: ${fresh.draft.costDelta}\n${fresh.draft.reason}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.text('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.text('hr.approve')),
          ),
        ],
      ),
    );
    if (confirmed == true)
      await widget.service.approvePayrollAdjustment(
        widget.subject,
        fresh.draft.id,
      );
  });
  void refund(PayrollRecordV2 p, {PayrollRefund? source}) {
    final id = _id(
      source == null ? 'payroll-refund' : 'payroll-refund-reversal',
    );
    form(
      source == null ? 'hr.adjustment.refund' : 'hr.adjustment.reverseRefund',
      (_) => [
        if (source == null) const _Field('amount', 'hr.amount', number: true),
        if (source != null)
          _Field(
            'source',
            'hr.adjustment.source',
            choices: {
              source.id: '${source.amount} ${source.currency} · ${source.day}',
            },
          ),
        const _Field('day', 'hr.adjustment.day'),
        const _Field('reason', 'hr.reason'),
      ],
      (v) => widget.service.refundPayroll(
        widget.subject,
        id: id,
        payrollId: p.id,
        amount: source?.amount ?? v['amount'] ?? '',
        currency: p.currency,
        day: v['day'] ?? '',
        reason: v['reason'] ?? '',
        reversesId: source?.id,
      ),
      initial: {
        'amount': p.overpaid,
        'day': LaborMoney.day(DateTime.now()),
        if (source != null) 'source': source.id,
      },
    );
  }

  void pay(PayrollRecordV2 p) {
    final id = _id('salary-payment');
    form(
      'hr.payment',
      (_) => [
        const _Field('amount', 'hr.amount', number: true),
        const _Field('day', 'hr.paymentDay'),
        const _Field('note', 'hr.paymentNote'),
      ],
      (v) => widget.service.recordPayment(
        widget.subject,
        id: id,
        payrollId: p.id,
        amount: v['amount'] ?? '',
        currency: p.currency,
        day: v['day'] ?? '',
        note: v['note'] ?? '',
      ),
      initial: {'amount': p.remaining, 'day': LaborMoney.day(DateTime.now())},
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.service.can(widget.subject, PermissionCodes.employeeView))
      return Scaffold(
        body: Center(
          child: Text(
            AppLocalizations.of(context).text('error.permissionDenied'),
          ),
        ),
      );
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: salary ? 4 : 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.text('hr.title')),
          actions: [
            if (widget.service.access.can(
              widget.subject,
              PermissionCodes.employeeEdit,
            ))
              IconButton(
                key: const Key('hr-department-create'),
                tooltip: l.text('hr.department.create'),
                onPressed: addDepartment,
                icon: const Icon(Icons.account_tree),
              ),
            if (widget.catalog != null)
              IconButton(
                key: const Key('hr-catalog'),
                icon: const Icon(Icons.people),
                tooltip: l.text('hr.sharedCatalog'),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CompanyCatalogScreen(
                        service: widget.catalog!,
                        initialKind: CatalogKind.worker,
                      ),
                    ),
                  );
                  if (mounted) reload();
                },
              ),
            IconButton(
              onPressed: busy ? null : reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: l.text('hr.employees')),
              Tab(text: l.text('hr.attendance')),
              if (salary) ...[
                Tab(text: l.text('hr.rates')),
                Tab(text: l.text('hr.payroll')),
              ],
            ],
          ),
        ),
        body: FutureBuilder<_PersonnelData>(
          future: data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(l.text('hr.loadFailed')));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final d = snapshot.data!;
            final peopleRows = d.employees
                .where((e) => workerId == null || e.workerId == workerId)
                .toList();
            final entries = d.entries
                .where(
                  (e) =>
                      (workerId == null || e.workerId == workerId) &&
                      e.businessDay.startsWith('${period.text.trim()}-'),
                )
                .toList();
            final payrolls = d.payrolls
                .where(
                  (p) =>
                      (workerId == null || p.workerId == workerId) &&
                      p.period == period.text.trim(),
                )
                .toList();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: const Key('hr-employee-filter'),
                          initialValue: workerId ?? '',
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l.text('hr.employee'),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(l.text('hr.all')),
                            ),
                            for (final e in d.employees)
                              DropdownMenuItem(
                                value: e.workerId,
                                child: Text('${e.code} · ${e.name}'),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => workerId = v == '' ? null : v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          key: const Key('hr-period-filter'),
                          controller: period,
                          decoration: InputDecoration(
                            labelText: l.text('hr.period'),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
                if (salary &&
                    can(PermissionCodes.reportPersonnel) &&
                    can(PermissionCodes.dataExport))
                  TextButton.icon(
                    key: const Key('hr-export'),
                    icon: const Icon(Icons.download),
                    label: Text(l.text('hr.export')),
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            final includeSensitive = can(
                              PermissionCodes.employeeSensitiveView,
                            );
                            final requestedPeriod = period.text.trim();
                            final stamp = widget.service.access.stamp(
                              widget.subject,
                            );
                            final fresh = await load(exporting: true);
                            widget.service.access.requireStamp(
                              widget.subject,
                              stamp,
                            );
                            for (final permission in [
                              PermissionCodes.employeeView,
                              PermissionCodes.payrollView,
                              PermissionCodes.reportPersonnel,
                              PermissionCodes.dataExport,
                              if (includeSensitive)
                                PermissionCodes.employeeSensitiveView,
                            ]) {
                              widget.service.authorize(
                                widget.subject,
                                permission,
                              );
                            }
                            final report = PersonnelReport(
                              farmId: widget.subject.farmId,
                              period: requestedPeriod,
                              workerId: workerId,
                              employees: fresh.employees,
                              entries: fresh.entries,
                              payrolls: fresh.payrolls,
                              payments: fresh.payments,
                              laborCosts: fresh.costs,
                              adjustments: fresh.adjustments,
                              refunds: fresh.refunds,
                            );
                            await saveExcelBytes(
                              report.bytes(),
                              'AGRICO-Personnel-${requestedPeriod}-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}.xlsx',
                            );
                          }),
                  ),
                Expanded(
                  child: TabBarView(
                    children: [
                      ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          Text(l.text('hr.identityNotice')),
                          if (d.employees.isEmpty)
                            Text(l.text('hr.emptyEmployees')),
                          for (final e in peopleRows)
                            Card(
                              child: ListTile(
                                key: Key('hr-profile-view-${e.workerId}'),
                                onTap: () => viewProfile(e),
                                title: Text('${e.code} · ${e.name}'),
                                subtitle: Text(
                                  '${e.profile?.details['position'] ?? ''} · ${e.profile?.details['department'] ?? ''}\n${e.profile?.details['phone'] ?? ''}',
                                ),
                                trailing:
                                    employeeAccess(
                                      d,
                                      e.workerId,
                                      PermissionCodes.employeeEdit,
                                    )
                                    ? IconButton(
                                        key: Key('hr-profile-${e.workerId}'),
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => profile(e, d),
                                      )
                                    : null,
                              ),
                            ),
                        ],
                      ),
                      ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          Text(l.text('hr.attendanceNotice')),
                          if (can(PermissionCodes.attendanceRecord))
                            FilledButton.icon(
                              key: const Key('hr-add-entry'),
                              onPressed: () => attendance(d),
                              icon: const Icon(Icons.add),
                              label: Text(l.text('hr.addEntry')),
                            ),
                          for (final e in entries)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${e.workerName} · ${e.businessDay}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(
                                      '${l.text('hr.regular')}: ${e.regularMinutes} min · ${l.text('hr.overtime')}: ${e.overtimeMinutes} min · ${l.text('hr.status.${e.status}')}',
                                    ),
                                    if (e.workTypeLabel != null)
                                      Text(e.workTypeLabel!),
                                    for (final label in e.planLabels)
                                      Text(label),
                                    if (e.pieceQuantity != null)
                                      Text(
                                        '${l.text('hr.piece')}: ${e.pieceQuantity} ${e.pieceUnit ?? ''}',
                                      ),
                                    if (e.total != null)
                                      Text(
                                        '${l.text('hr.earnings')}: ${e.total} ${e.currency}',
                                      ),
                                    if (e.machineId != null)
                                      Text(l.text('hr.machineExclusion')),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        if (e.status == 'draft' &&
                                            employeeAccess(
                                              d,
                                              e.workerId,
                                              PermissionCodes.attendanceVerify,
                                            ) &&
                                            employeeAccess(
                                              d,
                                              e.workerId,
                                              PermissionCodes.payrollView,
                                            ))
                                          TextButton(
                                            key: Key('hr-approve-${e.id}'),
                                            onPressed: busy
                                                ? null
                                                : () => run(
                                                    () => widget.service
                                                        .approveEntry(
                                                          widget.subject,
                                                          e,
                                                        ),
                                                  ),
                                            child: Text(l.text('hr.approve')),
                                          ),
                                        if (e.status != 'void' &&
                                            employeeAccess(
                                              d,
                                              e.workerId,
                                              PermissionCodes.attendanceVerify,
                                            ))
                                          TextButton(
                                            onPressed: () => form(
                                              'hr.void',
                                              (_) => [
                                                const _Field(
                                                  'reason',
                                                  'hr.reason',
                                                ),
                                              ],
                                              (v) => widget.service.voidEntry(
                                                widget.subject,
                                                e,
                                                v['reason'] ?? '',
                                              ),
                                            ),
                                            child: Text(l.text('hr.void')),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (salary)
                        ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            Text(l.text('hr.rateNotice')),
                            if (can(PermissionCodes.payrollManage))
                              FilledButton.icon(
                                key: const Key('hr-add-rate'),
                                onPressed: () => rate(d),
                                icon: const Icon(Icons.add),
                                label: Text(l.text('hr.addRate')),
                              ),
                            for (final r in d.rates.where(
                              (r) => workerId == null || r.workerId == workerId,
                            ))
                              ListTile(
                                title: Text(
                                  '${d.employees.where((e) => e.workerId == r.workerId).first.name} · ${r.effectiveOn} · #${r.revision}',
                                ),
                                subtitle: Text(
                                  '${l.text('hr.basis.${r.basis.name}')}: ${r.rate} ${r.currency} · ${r.standardMinutes} min\n${l.text('hr.otRate')}: ${r.overtimeHourlyRate ?? l.text('hr.notConfigured')} · ${l.text(r.rounding == MoneyRounding.halfUp ? 'hr.roundHalf' : 'hr.roundDown')} · ${r.moneyScale}',
                                ),
                              ),
                          ],
                        ),
                      if (salary)
                        ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            Text(l.text('hr.payrollNotice')),
                            if (can(PermissionCodes.payrollManage))
                              FilledButton.icon(
                                key: const Key('hr-add-payroll'),
                                onPressed: () => payroll(d),
                                icon: const Icon(Icons.add),
                                label: Text(l.text('hr.addPayroll')),
                              ),
                            for (final p in payrolls)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${p.code} · ${p.workerName} · ${p.period} · ${l.text('hr.status.${p.status}')}',
                                      ),
                                      Text(
                                        '${l.text('hr.adjustment.original')}: ${p.net} ${p.currency} · ${l.text('hr.adjustment.total')}: ${p.adjustmentTotal} · ${l.text('hr.net')}: ${p.effectiveNet} · ${l.text('hr.paid')}: ${p.paid} · ${l.text('hr.remaining')}: ${p.payable} · ${l.text('hr.adjustment.overpaid')}: ${p.overpaid}',
                                      ),
                                      if (p.adjustmentPlanId == null &&
                                          ExactDecimal.parse(
                                                LaborMoney.sum([
                                                  p.allowance,
                                                  p.bonus,
                                                ]),
                                              ).coefficient >
                                              BigInt.zero)
                                        Text(l.text('hr.extraUnallocated')),
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          if (p.status == 'draft' &&
                                              can(
                                                PermissionCodes.payrollApprove,
                                              ))
                                            TextButton(
                                              onPressed: busy
                                                  ? null
                                                  : () => run(
                                                      () => widget.service
                                                          .approvePayroll(
                                                            widget.subject,
                                                            p.id,
                                                          ),
                                                    ),
                                              child: Text(l.text('hr.approve')),
                                            ),
                                          if (p.status == 'draft' &&
                                              can(
                                                PermissionCodes.payrollManage,
                                              ))
                                            TextButton(
                                              onPressed: () => form(
                                                'hr.cancelPayroll',
                                                (_) => [
                                                  const _Field(
                                                    'reason',
                                                    'hr.reason',
                                                  ),
                                                ],
                                                (v) => widget.service
                                                    .cancelPayroll(
                                                      widget.subject,
                                                      p.id,
                                                      v['reason'] ?? '',
                                                    ),
                                              ),
                                              child: Text(
                                                l.text('hr.cancelPayroll'),
                                              ),
                                            ),
                                          if (p.status == 'approved' &&
                                              ExactDecimal.parse(
                                                    p.remaining,
                                                  ).coefficient >
                                                  BigInt.zero &&
                                              can(
                                                PermissionCodes.payrollApprove,
                                              ) &&
                                              can(PermissionCodes.cashRecord))
                                            TextButton(
                                              onPressed: () => pay(p),
                                              child: Text(l.text('hr.payment')),
                                            ),
                                        ],
                                      ),
                                      if (p.status == 'approved' &&
                                          employeeAccess(
                                            d,
                                            p.workerId,
                                            PermissionCodes.payrollManage,
                                          ))
                                        TextButton(
                                          key: Key(
                                            'hr-adjustment-create-${p.id}',
                                          ),
                                          onPressed: busy
                                              ? null
                                              : () => adjustment(p),
                                          child: Text(
                                            l.text('hr.adjustment.create'),
                                          ),
                                        ),
                                      for (final a in d.adjustments.where(
                                        (a) => a.draft.payrollId == p.id,
                                      ))
                                        Card(
                                          child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${a.code} · ${a.draft.day} · ${a.draft.delta} ${a.draft.currency} · ${l.text('hr.status.${a.status}')}',
                                                ),
                                                Text(a.draft.reason),
                                                Text(
                                                  '${l.text('hr.adjustment.creator')}: ${a.creator} · ${l.text('hr.adjustment.approver')}: ${a.approver ?? ''}',
                                                ),
                                                Text(
                                                  '${l.text('hr.adjustment.cost')}: ${a.draft.costDelta}',
                                                ),
                                                if (a.draft.kind ==
                                                        PayrollAdjustmentKind
                                                            .earnings &&
                                                    a.draft.delta !=
                                                        a.draft.costDelta)
                                                  Text(
                                                    l.text(
                                                      'hr.adjustment.unallocated',
                                                    ),
                                                  ),
                                                if (a.status == 'draft')
                                                  Wrap(
                                                    children: [
                                                      if (employeeAccess(
                                                        d,
                                                        p.workerId,
                                                        PermissionCodes
                                                            .payrollApprove,
                                                      ))
                                                        TextButton(
                                                          key: Key(
                                                            'hr-adjustment-approve-${a.draft.id}',
                                                          ),
                                                          onPressed: busy
                                                              ? null
                                                              : () =>
                                                                    approveAdjustment(
                                                                      a,
                                                                    ),
                                                          child: Text(
                                                            l.text(
                                                              'hr.adjustment.approve',
                                                            ),
                                                          ),
                                                        ),
                                                      if (employeeAccess(
                                                        d,
                                                        p.workerId,
                                                        PermissionCodes
                                                            .payrollManage,
                                                      ))
                                                        TextButton(
                                                          onPressed: busy
                                                              ? null
                                                              : () => run(
                                                                  () => widget
                                                                      .service
                                                                      .cancelPayrollAdjustment(
                                                                        widget
                                                                            .subject,
                                                                        a
                                                                            .draft
                                                                            .id,
                                                                      ),
                                                                ),
                                                          child: Text(
                                                            l.text(
                                                              'common.cancel',
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      if (ExactDecimal.parse(
                                                p.overpaid,
                                              ).coefficient >
                                              BigInt.zero &&
                                          employeeAccess(
                                            d,
                                            p.workerId,
                                            PermissionCodes.payrollApprove,
                                          ) &&
                                          employeeAccess(
                                            d,
                                            p.workerId,
                                            PermissionCodes.cashRecord,
                                          ))
                                        TextButton(
                                          key: Key('hr-payroll-refund-${p.id}'),
                                          onPressed: busy
                                              ? null
                                              : () => refund(p),
                                          child: Text(
                                            l.text('hr.adjustment.refund'),
                                          ),
                                        ),
                                      for (final r in d.refunds.where(
                                        (r) => r.payrollId == p.id,
                                      ))
                                        ListTile(
                                          title: Text(
                                            '${l.text(r.reversesId == null ? 'hr.adjustment.refund' : 'hr.adjustment.reverseRefund')}: ${r.amount} ${r.currency} · ${r.day}',
                                          ),
                                          subtitle: Text(
                                            '${r.reason} · ${r.actor}',
                                          ),
                                          trailing:
                                              r.reversesId == null &&
                                                  !d.refunds.any(
                                                    (s) => s.reversesId == r.id,
                                                  ) &&
                                                  employeeAccess(
                                                    d,
                                                    p.workerId,
                                                    PermissionCodes
                                                        .payrollApprove,
                                                  ) &&
                                                  employeeAccess(
                                                    d,
                                                    p.workerId,
                                                    PermissionCodes.cashRecord,
                                                  )
                                              ? TextButton(
                                                  onPressed: busy
                                                      ? null
                                                      : () => refund(
                                                          p,
                                                          source: r,
                                                        ),
                                                  child: Text(
                                                    l.text(
                                                      'hr.adjustment.reverseRefund',
                                                    ),
                                                  ),
                                                )
                                              : null,
                                        ),
                                      for (final payment in d.payments.where(
                                        (v) => v.payrollId == p.id,
                                      ))
                                        Text(
                                          '${payment.reversed ? (l.locale.languageCode == 'vi'
                                                    ? 'ĐÃ ĐẢO · '
                                                    : l.locale.languageCode == 'lo'
                                                    ? 'ກັບລາຍການ · '
                                                    : 'REVERSED · ') : ''}${payment.day} · ${payment.amount} ${payment.currency} · ${payment.note}',
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Field {
  const _Field(
    this.id,
    this.label, {
    this.choices,
    this.number = false,
    this.signed = false,
    this.literalLabel = false,
  });
  final String id, label;
  final Map<String, String>? choices;
  final bool number, signed, literalLabel;
}

class _PersonnelForm extends StatefulWidget {
  const _PersonnelForm({
    required this.title,
    required this.fields,
    required this.save,
    required this.initial,
  });
  final String title;
  final List<_Field> Function(Map<String, String>) fields;
  final Future<void> Function(Map<String, String>) save;
  final Map<String, String> initial;
  @override
  State<_PersonnelForm> createState() => _PersonnelFormState();
}

class _PersonnelFormState extends State<_PersonnelForm> {
  late final values = Map<String, String>.from(widget.initial);
  final controllers = <String, TextEditingController>{};
  bool saving = false;
  String? error;
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.save(Map.from(values));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = _failure(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fields = widget.fields(values);
    for (final f in fields) {
      if (f.choices != null &&
          values.containsKey(f.id) &&
          !f.choices!.containsKey(values[f.id])) {
        values[f.id] = '';
      }
    }

    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(l.text(widget.title)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final f in fields)
                  if (f.choices != null)
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'hr-field-${f.id}-${f.choices!.keys.join(':')}',
                      ),
                      initialValue: f.choices!.containsKey(values[f.id])
                          ? values[f.id]
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: f.literalLabel ? f.label : l.text(f.label),
                      ),
                      items: [
                        for (final e in f.choices!.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: saving
                          ? null
                          : (v) => setState(() {
                              values[f.id] = v ?? '';
                              if ([
                                'worker',
                                'plan',
                                'currency',
                                'day',
                              ].contains(f.id)) {
                                values['task'] = '';
                              }
                            }),
                    )
                  else
                    TextField(
                      key: Key('hr-field-${f.id}'),
                      controller: controllers.putIfAbsent(
                        f.id,
                        () => TextEditingController(text: values[f.id] ?? ''),
                      ),
                      enabled: !saving,
                      keyboardType: f.number
                          ? TextInputType.numberWithOptions(
                              decimal: true,
                              signed: f.signed,
                            )
                          : TextInputType.text,
                      decoration: InputDecoration(
                        labelText: f.literalLabel ? f.label : l.text(f.label),
                      ),
                      onChanged: (v) {
                        values[f.id] = f.number
                            ? v.trim().replaceAll(',', '.')
                            : v.trim();
                        if (f.id == 'day') setState(() {});
                      },
                    ),
                if (error != null)
                  Text(error!, key: const Key('hr-save-error')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
            child: Text(l.text('common.cancel')),
          ),
          FilledButton(
            key: const Key('hr-form-save'),
            onPressed: saving ? null : save,
            child: Text(l.text('common.save')),
          ),
        ],
      ),
    );
  }
}

String _failure(BuildContext context, Object error) {
  final text = error.toString();
  final l = AppLocalizations.of(context);
  if (text.contains('Link original salary'))
    return l.text('hr.adjustment.errorCashLink');
  if (text.contains('Reverse dependent') ||
      text.contains('Original refund cannot'))
    return l.text('hr.adjustment.errorDependency');
  if (text.contains('Approved corrections'))
    return l.text('hr.adjustment.errorImmutable');
  if (text.toLowerCase().contains('stale payroll') ||
      text.toLowerCase().contains('stale adjustment'))
    return l.text('hr.adjustment.errorStale');
  if (text.contains('Refund exceeds') || text.contains('overpayment'))
    return l.text('hr.adjustment.errorRefund');
  if (text.contains('Allocation') ||
      text.contains('allocation') ||
      text.contains('attributed production') ||
      text.contains('original payroll plan'))
    return l.text('hr.adjustment.errorAllocation');
  if (text.contains('salary components') ||
      text.contains('cannot be negative') ||
      text.contains('Negative payroll'))
    return l.text('hr.adjustment.errorNet');
  if (text.contains('posting date') ||
      text.contains('Future posting') ||
      text.contains('date precedes'))
    return l.text('hr.adjustment.errorDate');
  if (text.contains('Overtime rate')) return l.text('hr.errorOvertime');
  if (text.contains('No effective pay rate')) return l.text('hr.errorRate');
  if (text.contains('overlap')) return l.text('hr.errorOverlap');
  if (text.contains('Regular time exceeds')) return l.text('hr.errorCap');
  if (text.contains('locked')) return l.text('hr.errorLocked');
  if (text.contains('matching currency') ||
      text.contains('plan in this farm')) {
    return l.text('hr.errorPlan');
  }
  return l.text('hr.saveFailed');
}
