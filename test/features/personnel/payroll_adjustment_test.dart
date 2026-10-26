import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_restore_preflight.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_farm_task_repository.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/production_destination_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/production_plan.dart';
import 'package:agrico_deepseek/features/personnel/application/personnel_service.dart';
import 'package:agrico_deepseek/features/personnel/application/personnel_report.dart';
import 'package:agrico_deepseek/features/personnel/data/sqlite_personnel_repository.dart';
import 'package:agrico_deepseek/features/personnel/data/sqlite_payroll_adjustments.dart';
import 'package:agrico_deepseek/features/personnel/data/personnel_integrity.dart';
import 'package:agrico_deepseek/features/machines/data/sqlite_machine_repository.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:agrico_deepseek/features/trade/data/sqlite_trade_repository.dart';
import 'package:agrico_deepseek/features/integration/data/integration_repository.dart';
import 'package:agrico_deepseek/features/integration/data/integration_cash.dart';
import 'package:agrico_deepseek/features/integration/data/integration_integrity.dart';
import 'package:agrico_deepseek/features/integration/application/report20.dart';

void main() {
  late AuthorizationSubject live;
  sqfliteFfiInit();
  late Database db;
  late SqlitePersonnelRepository repo;
  late PersonnelService service;
  late SqliteInventoryRepository inventory;
  final admin = AuthorizationSubject(
    userId: 'admin',
    membershipId: 'm',
    farmId: 'f',
    permissionCodes: PermissionCodes.values,
    dataScopes: const {DataScope.allFarm},
  );
  PayRate rate({
    String id = 'rate',
    String day = '2026-10-01',
    PayBasis basis = PayBasis.daily,
    String amount = '80000',
    String? ot = '15000',
    String currency = 'VND',
    int scale = 0,
  }) => PayRate(
    id: id,
    farmId: 'f',
    workerId: 'w',
    effectiveOn: day,
    basis: basis,
    rate: amount,
    currency: currency,
    rounding: MoneyRounding.halfUp,
    moneyScale: scale,
    overtimeHourlyRate: ot,
    pieceUnit: basis == PayBasis.piece ? 'ha' : '',
  );
  LaborEntryDraft entry(
    String id, {
    int day = 25,
    int start = 8,
    int hours = 10,
    int breakMinutes = 0,
    int overtime = 120,
    String? quantity,
    String? machine,
    String plan = 'plan',
    bool allocate = true,
  }) {
    final begins = DateTime.utc(2026, 10, day, start - 7);
    final ends = begins.add(Duration(hours: hours));
    return LaborEntryDraft(
      id: id,
      farmId: 'f',
      workerId: 'w',
      startsAt: begins,
      endsAt: ends,
      breakMinutes: breakMinutes,
      overtimeMinutes: overtime,
      pieceQuantity: quantity,
      machineId: machine,
      allocations: allocate
          ? [
              LaborAllocationDraft(
                planId: plan,
                regularMinutes: hours * 60 - breakMinutes - overtime,
                overtimeMinutes: overtime,
              ),
            ]
          : [],
    );
  }

  Future<LaborEntryRecord> saved(String id) async =>
      (await service.entries(admin)).firstWhere((e) => e.id == id);
  Future<void> approve(LaborEntryDraft d) async {
    await service.createEntry(admin, d);
    await service.approveEntry(admin, await saved(d.id));
  }

  Future<void> addPlan(String id, {String currency = 'VND'}) async {
    await inventory.createProductionPlan(
      ProductionPlan(
        id: id,
        farmId: 'f',
        parcelId: 'p',
        seasonId: 's',
        name: id,
        crop: 'Peanut',
        startsOn: '2026-10-01',
        endsOn: '2026-10-31',
        currency: currency,
        materialBudget: '0',
        laborBudget: '1000000',
        machineBudget: '1000000',
        laborHours: '80',
        machineShifts: '1',
      ),
      'admin',
    );
    await inventory.changeProductionPlanStatus(
      'f',
      id,
      0,
      ProductionPlanStatus.active,
      'admin',
    );
  }

  setUp(() async {
    live = admin;
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys=ON');
    await db.execute(
      'CREATE TABLE land_parcels(id TEXT PRIMARY KEY,farm_id TEXT,parcel_code TEXT,active INTEGER,kind TEXT)',
    );
    await db.execute(
      'CREATE TABLE parcel_work_resources(id TEXT PRIMARY KEY,farm_id TEXT,kind TEXT,code TEXT,name TEXT,active INTEGER,UNIQUE(farm_id,kind,code))',
    );
    await SqliteFarmTaskRepository.createTaskTable(db);
    await SqliteInventoryRepository.createSchema(db);
    await SqliteCompanyCatalog.createSchema(db);
    await SqlitePersonnelRepository.createSchema(db);
    await SqliteMachineRepository.createSchema(db);
    await SqliteFinanceDocumentRepository.createSchema(db);
    await SqliteTradeRepository.createSchema(db);
    await IntegrationRepository.createSchema(db);

    await db.insert('land_parcels', {
      'id': 'p',
      'farm_id': 'f',
      'parcel_code': 'P001',
      'active': 1,
      'kind': 'fieldPlot',
    });
    final catalog = CompanyCatalogService(
      repository: SqliteCompanyCatalog(db),
      subject: admin,
    );
    await catalog.create(
      const CatalogEntry(
        id: 'unit-ha',
        farmId: 'f',
        kind: CatalogKind.unit,
        code: '',
        name: 'ha',
      ),
      reason: 'Shared unit',
    );
    await catalog.create(
      const CatalogEntry(
        id: 'w',
        farmId: 'f',
        kind: CatalogKind.worker,
        code: '',
        name: 'Nhân viên ລາວ',
      ),
      reason: 'New worker',
    );
    await catalog.create(
      const CatalogEntry(
        id: 'machine',
        farmId: 'f',
        kind: CatalogKind.machine,
        code: '',
        name: 'Tractor',
      ),
      reason: 'New machine',
    );
    inventory = SqliteInventoryRepository(db);
    await inventory.createProductionSeason(
      const ProductionSeason(
        id: 's',
        farmId: 'f',
        parcelId: 'p',
        name: 'Season',
        startsOn: '2026-10-01',
      ),
    );
    await addPlan('plan');
    repo = SqlitePersonnelRepository(db);
    service = PersonnelService(repo, currentSubject: () => live);
  });
  tearDown(() => db.close());

  Future<void> salaryReady() async {
    await service.createRate(admin, rate(amount: '1', ot: '1', scale: 2));
    await approve(entry('a', hours: 8, overtime: 0));
    await service.createPayroll(
      admin,
      const PayrollDraft(
        id: 'salary',
        farmId: 'f',
        workerId: 'w',
        period: '2026-10',
        currency: 'VND',
      ),
    );
    await service.approvePayroll(admin, 'salary');
  }

  Future<void> pay({
    String id = 'pay',
    String amount = '0.25',
    String day = '2026-10-25',
  }) => service.recordPayment(
    admin,
    id: id,
    payrollId: 'salary',
    amount: amount,
    currency: 'VND',
    day: day,
    note: 'Bank transfer',
  );
  IntegrationRepository bridge() => IntegrationRepository(db);
  PayrollAdjustmentDraft adjustment(
    String id, {
    String delta = '0.2',
    String currency = 'VND',
    String day = '2026-10-26',
    int revision = 0,
    PayrollAdjustmentKind kind = PayrollAdjustmentKind.earnings,
    List<PayrollCostAdjustment> allocations = const [],
    String payroll = 'salary',
    String reason = 'Điều chỉnh đã đối chiếu ລາວ',
  }) => PayrollAdjustmentDraft(
    id: id,
    farmId: 'f',
    payrollId: payroll,
    currency: currency,
    day: day,
    delta: delta,
    reason: reason,
    expectedRevision: revision,
    kind: kind,
    allocations: allocations,
  );
  Future<PayrollRecordV2> current() async =>
      (await service.payrolls(admin)).single;
  Future<void> adjust(PayrollAdjustmentDraft d) async {
    await service.createPayrollAdjustment(admin, d);
    await service.approvePayrollAdjustment(admin, d.id);
  }

  Future<void> refund({
    String id = 'refund',
    String amount = '0.1',
    String? reversesId,
  }) => service.refundPayroll(
    admin,
    id: id,
    payrollId: 'salary',
    amount: amount,
    currency: 'VND',
    day: '2026-10-26',
    reason: 'Refund reference',
    reversesId: reversesId,
  );
  Future<void> validate() => PersonnelIntegrity.validate(db);
  test(
    'draft has an automatic code, immutable base and no cost or cash effect before approval',
    () async {
      await salaryReady();
      final original = await db.query('personnel_payrolls_v1');
      final labor = await db.query('production_labor_costs_v1');
      final d = adjustment(
        'a',
        allocations: [const PayrollCostAdjustment('plan', '0.2')],
      );
      await service.createPayrollAdjustment(admin, d);
      await service.createPayrollAdjustment(admin, d);
      expect((await current()).effectiveNet, '1');
      expect(await db.query('personnel_payrolls_v1'), original);
      expect(await db.query('production_labor_costs_v1'), labor);
      expect(await db.query('finance_documents_v2'), isEmpty);
      final rows = await service.payrollAdjustments(admin);
      expect(rows.single.code, 'DCL-202610-001');
      expect(rows.single.creator, 'admin');
      expect(rows.single.status, 'draft');
      await service.approvePayrollAdjustment(admin, 'a');
      await service.approvePayrollAdjustment(admin, 'a');
      expect((await current()).net, '1');
      expect((await current()).effectiveNet, '1.2');
      expect((await current()).adjustmentRevision, 1);
      expect(await db.query('personnel_payrolls_v1'), original);
      expect(await db.query('production_labor_costs_v1'), labor);
      expect(
        LaborMoney.sum((await service.laborCosts(admin)).map((c) => c.amount)),
        '1.2',
      );
      expect(await db.query('finance_documents_v2'), isEmpty);
      await validate();
    },
  );
  test(
    'deduction changes payable but never production costs or cash',
    () async {
      await salaryReady();
      await adjust(
        adjustment('a', delta: '-0.3', kind: PayrollAdjustmentKind.deduction),
      );
      expect((await current()).effectiveNet, '0.7');
      expect((await current()).remaining, '0.7');
      expect(
        LaborMoney.sum((await service.laborCosts(admin)).map((c) => c.amount)),
        '1',
      );
      await validate();
    },
  );
  test(
    'partial overpayment refund creates exact THU and leaves salary, earnings and costs immutable',
    () async {
      await salaryReady();
      await pay(amount: '1');
      await adjust(
        adjustment('a', delta: '-0.4', kind: PayrollAdjustmentKind.deduction),
      );
      expect((await current()).overpaid, '0.4');
      expect((await current()).payable, '0');
      await refund(amount: '0.15');
      await refund(amount: '0.15');
      expect((await current()).paid, '0.85');
      expect((await current()).overpaid, '0.25');
      final cash = await db.query('finance_documents_v2', where: "kind='THU'");
      expect(cash.length, 1);
      expect(IntegrationCash.amount(cash.single), '0.15');
      expect((await db.query('personnel_payments_v1')).single['amount'], '1');
      expect(
        LaborMoney.sum((await service.laborCosts(admin)).map((c) => c.amount)),
        '1',
      );
      await validate();
      await IntegrationIntegrity.validate(db);
    },
  );
  test(
    'refund reversal appends CHI and restores the receivable without editing either source',
    () async {
      await salaryReady();
      await pay(amount: '1');
      await adjust(
        adjustment('a', delta: '-0.4', kind: PayrollAdjustmentKind.deduction),
      );
      await refund(amount: '0.15');
      final original = (await db.query(
        SqlitePayrollAdjustments.refunds,
      )).single;
      await refund(id: 'undo', amount: '0.15', reversesId: 'refund');
      await refund(id: 'undo', amount: '0.15', reversesId: 'refund');
      expect((await current()).overpaid, '0.4');
      expect((await current()).refunded, '0');
      expect(
        (await db.query(
          SqlitePayrollAdjustments.refunds,
          where: 'id=?',
          whereArgs: ['refund'],
        )).single,
        original,
      );
      expect((await db.query('finance_documents_v2')).length, 3);
      await validate();
      await IntegrationIntegrity.validate(db);
    },
  );
  test(
    'new payments honor the corrected balance and do not double count refunded money',
    () async {
      await salaryReady();
      await pay(amount: '1');
      await adjust(
        adjustment('a', delta: '-0.4', kind: PayrollAdjustmentKind.deduction),
      );
      await refund(amount: '0.4');
      await expectLater(
        pay(id: 'over', amount: '0.01', day: '2026-10-26'),
        throwsStateError,
      );
      await adjust(adjustment('b', delta: '0.2', revision: 1));
      await pay(id: 'extra', amount: '0.2', day: '2026-10-26');
      expect((await current()).remaining, '0');
      expect((await current()).paid, '0.8');
      await validate();
    },
  );
  test(
    'over-refund and original-payment reversal after a partial refund are rejected',
    () async {
      await salaryReady();
      await pay(amount: '1');
      await adjust(
        adjustment('a', delta: '-0.4', kind: PayrollAdjustmentKind.deduction),
      );
      await expectLater(refund(amount: '0.41'), throwsStateError);
      await refund(amount: '0.2');
      await expectLater(
        bridge().reverseSalary(
          'f',
          'pay',
          'reverse',
          '2026-10-26',
          'Mistake',
          'admin',
        ),
        throwsStateError,
      );
      expect((await current()).paid, '0.8');
      await validate();
    },
  );
  test(
    'dependent payment must be reversed before undoing an already-used refund',
    () async {
      await salaryReady();
      await pay(amount: '1');
      await adjust(
        adjustment('a', delta: '-0.4', kind: PayrollAdjustmentKind.deduction),
      );
      await refund(amount: '0.4');
      await adjust(adjustment('b', delta: '0.4', revision: 1));
      await pay(id: 'extra', amount: '0.4', day: '2026-10-26');
      await expectLater(
        refund(id: 'undo', amount: '0.4', reversesId: 'refund'),
        throwsStateError,
      );
      await bridge().reverseSalary(
        'f',
        'extra',
        'undo-extra',
        '2026-10-26',
        'Dependent reversal',
        'admin',
      );
      await refund(id: 'undo', amount: '0.4', reversesId: 'refund');
      await validate();
    },
  );
  test(
    'stale proposals and concurrent approvals cannot overwrite a newer correction',
    () async {
      await salaryReady();
      await service.createPayrollAdjustment(admin, adjustment('a'));
      await service.createPayrollAdjustment(admin, adjustment('b'));
      final outcomes = await Future.wait(
        ['a', 'b'].map(
          (id) => service
              .approvePayrollAdjustment(admin, id)
              .then((_) => true, onError: (_) => false),
        ),
      );
      expect(outcomes.where((v) => v).length, 1);
      expect((await current()).effectiveNet, '1.2');
      await adjust(adjustment('c', delta: '0.1', revision: 1));
      expect((await current()).effectiveNet, '1.3');
      await validate();
    },
  );
  test(
    'only draft corrections can be cancelled and approved corrections need an opposite entry',
    () async {
      await salaryReady();
      await service.createPayrollAdjustment(admin, adjustment('cancel'));
      await service.cancelPayrollAdjustment(admin, 'cancel');
      await service.cancelPayrollAdjustment(admin, 'cancel');
      await expectLater(
        service.approvePayrollAdjustment(admin, 'cancel'),
        throwsStateError,
      );
      await adjust(adjustment('a'));
      await expectLater(
        service.cancelPayrollAdjustment(admin, 'a'),
        throwsStateError,
      );
      await adjust(adjustment('opposite', delta: '-0.2', revision: 1));
      expect((await current()).effectiveNet, '1');
      await validate();
    },
  );
  test(
    'same adjustment identity with changed content is rejected without changing the counter',
    () async {
      await salaryReady();
      await service.createPayrollAdjustment(admin, adjustment('a'));
      await expectLater(
        service.createPayrollAdjustment(admin, adjustment('a', delta: '0.3')),
        throwsStateError,
      );
      expect(
        (await db.query(
          SqlitePayrollAdjustments.sequences,
        )).single['last_value'],
        1,
      );
    },
  );
  test(
    'invalid zero, exponent, excessive precision, missing reason and negative salary fail before writes',
    () async {
      await salaryReady();
      for (final value in ['0', '-0', '1e3', 'NaN', '0.0000001']) {
        expect(
          () => service.createPayrollAdjustment(
            admin,
            adjustment('bad', delta: value),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => service.createPayrollAdjustment(
          admin,
          adjustment('reason', reason: ''),
        ),
        throwsFormatException,
      );
      await expectLater(
        service.createPayrollAdjustment(
          admin,
          adjustment('negative', delta: '-2'),
        ),
        throwsStateError,
      );
      expect(await db.query(SqlitePayrollAdjustments.adjustments), isEmpty);
      expect(await db.query(SqlitePayrollAdjustments.sequences), isEmpty);
    },
  );
  test(
    'currency, foreign payroll, unrelated plans and excessive production reversal fail',
    () async {
      await salaryReady();
      await addPlan('other');
      await expectLater(
        service.createPayrollAdjustment(
          admin,
          adjustment('currency', currency: 'LAK'),
        ),
        throwsStateError,
      );
      await expectLater(
        service.createPayrollAdjustment(
          admin,
          adjustment('missing', payroll: 'outside'),
        ),
        throwsStateError,
      );
      await expectLater(
        service.createPayrollAdjustment(
          admin,
          adjustment(
            'plan',
            allocations: [const PayrollCostAdjustment('other', '0.2')],
          ),
        ),
        throwsStateError,
      );
      expect(
        () => service.createPayrollAdjustment(
          admin,
          adjustment(
            'deduction',
            kind: PayrollAdjustmentKind.deduction,
            allocations: [const PayrollCostAdjustment('plan', '0.2')],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => service.createPayrollAdjustment(
          admin,
          adjustment(
            'allocation',
            allocations: [const PayrollCostAdjustment('plan', '0.3')],
          ),
        ),
        throwsFormatException,
      );
      await adjust(adjustment('up', delta: '2'));
      await expectLater(
        service.createPayrollAdjustment(
          admin,
          adjustment(
            'excess',
            delta: '-2',
            revision: 1,
            allocations: [const PayrollCostAdjustment('plan', '-2')],
          ),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'approved correction can append to an original completed plan without reopening or rewriting it',
    () async {
      await salaryReady();
      await inventory.changeProductionPlanStatus(
        'f',
        'plan',
        1,
        ProductionPlanStatus.completed,
        'admin',
      );
      final before = await db.query('production_plans_v1');
      await adjust(
        adjustment(
          'a',
          delta: '-0.2',
          allocations: [const PayrollCostAdjustment('plan', '-0.2')],
        ),
      );
      expect(await db.query('production_plans_v1'), before);
      expect(
        LaborMoney.sum((await service.laborCosts(admin)).map((c) => c.amount)),
        '0.8',
      );
      await validate();
    },
  );
  test(
    'failure during correction creation rolls back code, cost lines and audit',
    () async {
      await salaryReady();
      await db.execute(
        "CREATE TRIGGER fail_correction BEFORE INSERT ON personnel_audit_v1 WHEN NEW.action='payroll.adjustment.create' BEGIN SELECT RAISE(ABORT,'fail'); END",
      );
      await expectLater(
        service.createPayrollAdjustment(
          admin,
          adjustment(
            'a',
            allocations: [const PayrollCostAdjustment('plan', '0.2')],
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query(SqlitePayrollAdjustments.adjustments), isEmpty);
      expect(await db.query(SqlitePayrollAdjustments.costs), isEmpty);
      expect(await db.query(SqlitePayrollAdjustments.sequences), isEmpty);
      await db.execute('DROP TRIGGER fail_correction');
      await service.createPayrollAdjustment(admin, adjustment('b'));
      expect(
        (await service.payrollAdjustments(admin)).single.code,
        'DCL-202610-001',
      );
    },
  );
  test(
    'failed approval cannot change effective payroll or cost projection',
    () async {
      await salaryReady();
      await service.createPayrollAdjustment(
        admin,
        adjustment(
          'a',
          allocations: [const PayrollCostAdjustment('plan', '0.2')],
        ),
      );
      await db.execute(
        "CREATE TRIGGER fail_approval BEFORE INSERT ON personnel_audit_v1 WHEN NEW.action='payroll.adjustment.approve' BEGIN SELECT RAISE(ABORT,'fail'); END",
      );
      await expectLater(
        service.approvePayrollAdjustment(admin, 'a'),
        throwsA(isA<DatabaseException>()),
      );
      expect((await current()).effectiveNet, '1');
      expect((await service.payrollAdjustments(admin)).single.status, 'draft');
      await validate();
    },
  );
  test(
    'failed refund cash insert rolls back every refund and monthly sequence change',
    () async {
      await salaryReady();
      await pay(amount: '1');
      await adjust(
        adjustment('a', delta: '-0.4', kind: PayrollAdjustmentKind.deduction),
      );
      final counters = await db.query('monthly_document_sequences');
      await db.execute(
        "CREATE TRIGGER fail_refund BEFORE INSERT ON finance_documents_v2 WHEN NEW.kind='THU' BEGIN SELECT RAISE(ABORT,'fail'); END",
      );
      await expectLater(refund(), throwsA(isA<DatabaseException>()));
      expect(await db.query(SqlitePayrollAdjustments.refunds), isEmpty);
      expect(await db.query('monthly_document_sequences'), counters);
      expect((await current()).overpaid, '0.4');
      await validate();
    },
  );
  test(
    'future and backdated postings do not rewrite a later payroll ledger',
    () async {
      await salaryReady();
      await expectLater(
        service.createPayrollAdjustment(
          admin,
          adjustment('before', day: '2026-10-24'),
        ),
        throwsStateError,
      );
      expect(
        () => service.createPayrollAdjustment(
          admin,
          adjustment('future', day: '2099-01-01'),
        ),
        throwsFormatException,
      );
      await adjust(adjustment('a'));
      await expectLater(
        pay(amount: '0.1', day: '2026-10-25'),
        throwsStateError,
      );
    },
  );
  test(
    'department grants and read-only grants cannot approve or refund outside scope',
    () async {
      await salaryReady();
      await service.createDepartment(
        admin,
        const PersonnelDepartment('dept', 'Other'),
      );
      await service.saveProfile(
        admin,
        EmployeeProfile(
          workerId: 'w',
          farmId: 'f',
          departmentId: 'dept',
          details: {},
        ),
      );
      live = AuthorizationSubject(
        userId: 'admin',
        membershipId: 'm',
        farmId: 'f',
        permissionCodes: PermissionCodes.values,
        dataScopes: const {DataScope.department},
        departmentIds: const {'assigned'},
      );
      expect(await service.payrollAdjustments(admin), isEmpty);
      await expectLater(
        service.createPayrollAdjustment(admin, adjustment('denied')),
        throwsStateError,
      );
      live = const AuthorizationSubject(
        userId: 'admin',
        membershipId: 'm',
        farmId: 'f',
        permissionCodes: {PermissionCodes.payrollView},
        dataScopes: {DataScope.allFarm},
      );
      expect(
        () => service.createPayrollAdjustment(admin, adjustment('read-only')),
        throwsStateError,
      );
      expect(() => refund(), throwsStateError);
    },
  );
  test(
    'reports keep original salary, correction postings, refund cash and VND LAK separate',
    () async {
      await salaryReady();
      await pay(amount: '1');
      await adjust(
        adjustment(
          'a',
          delta: '-0.4',
          allocations: [const PayrollCostAdjustment('plan', '-0.4')],
        ),
      );
      await refund(amount: '0.2');
      final snapshot = await bridge().snapshot('f', '2026-10');
      expect(snapshot.salaryNet('salary'), '0.6');
      expect(snapshot.salaryPaid('salary'), '0.8');
      expect(snapshot.laborCost('plan', 'VND'), '0.6');
      expect(snapshot.laborCost('plan', 'LAK'), '0');
      final workbook = Report20(snapshot).workbook();
      expect(workbook.tables.length, 20);
      expect(workbook['BANG LUONG'].rows.length, 3);
      final report = PersonnelReport(
        farmId: 'f',
        period: '2026-10',
        employees: await service.employees(admin),
        entries: await service.entries(admin),
        payrolls: await service.payrolls(admin),
        payments: await service.payments(admin),
        laborCosts: await service.laborCosts(admin),
        adjustments: await service.payrollAdjustments(admin),
        refunds: await service.payrollRefunds(admin),
      );
      final file = Excel.decodeBytes(report.bytes());
      expect(file['DIEU CHINH LUONG'].rows.length, 2);
      expect(file['THU HOAN LUONG'].rows.length, 2);
      await validate();
    },
  );
  test(
    'backup preflight accepts corrections and refunds but rejects altered delta or missing tables',
    () async {
      await salaryReady();
      await pay(amount: '1');
      await adjust(
        adjustment('a', delta: '-0.4', kind: PayrollAdjustmentKind.deduction),
      );
      await refund(amount: '0.2');
      final directory = await Directory.systemTemp.createTemp(
        'payroll-adjustment-',
      );
      final costs = await databaseFactoryFfi.openDatabase(
        '${directory.path}/costs.db',
      );
      await costs.execute('CREATE TABLE production_costs(id TEXT PRIMARY KEY)');
      try {
        final bytes = await LocalDatabaseSnapshot.create(
          db,
          costsDatabase: costs,
        );
        Future<Map<String, int>> check(Uint8List value) =>
            LocalRestorePreflight.validate(
              bytes: value,
              primary: db,
              costs: costs,
              factory: databaseFactoryFfi,
              temporaryDirectory: directory.path,
            );
        await check(bytes);
        Uint8List change(void Function(Map<String, dynamic>) edit) {
          final envelope =
              jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          final body =
              jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
          edit(
            ((body['databases'] as Map)['agrico.db'] as Map)['tables']
                as Map<String, dynamic>,
          );
          final text = jsonEncode(body);
          envelope['payload'] = text;
          envelope['sha256'] = sha256.convert(utf8.encode(text)).toString();
          return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
        }

        await expectLater(
          check(
            change((t) {
              ((t[SqlitePayrollAdjustments.adjustments] as List).single
                      as Map)['delta'] =
                  '-0.5';
            }),
          ),
          throwsA(isA<RestorePreflightException>()),
        );
        await expectLater(
          check(change((t) => t.remove(SqlitePayrollAdjustments.costs))),
          throwsA(isA<RestorePreflightException>()),
        );
        expect((await current()).effectiveNet, '0.6');
      } finally {
        await costs.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'earnings decreases must also reduce fully allocated costs and deductions cannot exceed gross pay',
    () async {
      await salaryReady();
      await expectLater(
        service.createPayrollAdjustment(
          admin,
          adjustment('unbalanced', delta: '-0.2'),
        ),
        throwsStateError,
      );
      await expectLater(
        service.createPayrollAdjustment(
          admin,
          adjustment('deduction-plus', kind: PayrollAdjustmentKind.deduction),
        ),
        throwsStateError,
      );
      await adjust(
        adjustment(
          'balanced',
          delta: '-0.2',
          allocations: [const PayrollCostAdjustment('plan', '-0.2')],
        ),
      );
      expect((await current()).effectiveNet, '0.8');
      await validate();
    },
  );
  test(
    'an earnings correction for machine-included labor cannot charge production labor a second time',
    () async {
      await service.createRate(admin, rate(amount: '1', ot: '1', scale: 2));
      await approve(
        entry('machine-entry', hours: 8, overtime: 0, machine: 'machine'),
      );
      await service.createPayroll(
        admin,
        const PayrollDraft(
          id: 'salary',
          farmId: 'f',
          workerId: 'w',
          period: '2026-10',
          currency: 'VND',
        ),
      );
      await service.approvePayroll(admin, 'salary');
      expect(await service.payrollAdjustmentPlans(admin, 'salary'), isEmpty);
      await expectLater(
        service.createPayrollAdjustment(
          admin,
          adjustment(
            'double',
            allocations: [const PayrollCostAdjustment('plan', '0.2')],
          ),
        ),
        throwsStateError,
      );
      await adjust(adjustment('pay-only'));
      expect((await current()).effectiveNet, '1.2');
      expect(
        LaborMoney.sum((await service.laborCosts(admin)).map((c) => c.amount)),
        '0',
      );
      await validate();
    },
  );
  test(
    'micro-unit corrections and refunds retain exact decimal amounts',
    () async {
      await salaryReady();
      await pay(amount: '1');
      await adjust(
        adjustment(
          'tiny',
          delta: '-0.000001',
          kind: PayrollAdjustmentKind.deduction,
        ),
      );
      await refund(amount: '0.000001');
      expect((await current()).paid, '0.999999');
      expect((await current()).remaining, '0');
      final cash = (await db.query(
        'finance_documents_v2',
        where: "kind='THU'",
      )).single;
      expect(cash['amount_scale'], 6);
      expect(IntegrationCash.amount(cash), '0.000001');
      await validate();
    },
  );
  test(
    'a correction to a previous month appears only as a correction flow in the posting month',
    () async {
      await service.createRate(
        admin,
        rate(day: '2026-09-01', amount: '1', ot: '1', scale: 2),
      );
      await approve(
        LaborEntryDraft(
          id: 'sept',
          allocations: [],
          farmId: 'f',
          workerId: 'w',
          startsAt: DateTime.utc(2026, 9, 25, 1),
          endsAt: DateTime.utc(2026, 9, 25, 9),
          breakMinutes: 0,
          overtimeMinutes: 0,
        ),
      );
      await service.createPayroll(
        admin,
        const PayrollDraft(
          id: 'salary',
          farmId: 'f',
          workerId: 'w',
          period: '2026-09',
          currency: 'VND',
        ),
      );
      await service.approvePayroll(admin, 'salary');
      await adjust(
        adjustment(
          'october',
          delta: '-0.2',
          kind: PayrollAdjustmentKind.deduction,
        ),
      );
      final report = Report20(
        await bridge().snapshot('f', '2026-10'),
      ).workbook();
      expect(report['BANG LUONG'].rows.length, 2);
      expect(report['BANG LUONG'].rows[1][9]!.value.toString(), '-0.2');
      final september = Report20(
        await bridge().snapshot('f', '2026-09'),
      ).workbook();
      expect(september['BANG LUONG'].rows.length, 2);
      expect(september['BANG LUONG'].rows[1][9]!.value.toString(), '1');
      await validate();
    },
  );
  test(
    'VND employee receivable and LAK salary payable never offset each other',
    () async {
      await salaryReady();
      await pay(amount: '1');
      await adjust(
        adjustment('vnd', delta: '-0.2', kind: PayrollAdjustmentKind.deduction),
      );
      await service.createRate(
        admin,
        rate(
          id: 'lak-rate',
          day: '2026-10-02',
          amount: '2',
          currency: 'LAK',
          scale: 2,
        ),
      );
      await approve(
        entry('lak-work', day: 24, hours: 8, overtime: 0, allocate: false),
      );
      await service.createPayroll(
        admin,
        const PayrollDraft(
          id: 'lak',
          farmId: 'f',
          workerId: 'w',
          period: '2026-10',
          currency: 'LAK',
        ),
      );
      await service.approvePayroll(admin, 'lak');
      await adjust(
        adjustment(
          'lak-correction',
          payroll: 'lak',
          currency: 'LAK',
          delta: '0.5',
        ),
      );
      final list = await service.payrolls(admin);
      expect(list.singleWhere((p) => p.id == 'salary').overpaid, '0.2');
      expect(list.singleWhere((p) => p.id == 'lak').payable, '2.5');
      final s = await bridge().snapshot('f', '2026-10');
      expect(s.salaryNet('salary'), '0.8');
      expect(s.salaryNet('lak'), '2.5');
      await validate();
    },
  );
  test(
    'refund cash cannot also be owner capital and tampered cash amounts fail reconciliation',
    () async {
      await salaryReady();
      await pay(amount: '1');
      await adjust(
        adjustment('a', delta: '-0.2', kind: PayrollAdjustmentKind.deduction),
      );
      await refund();
      await expectLater(
        bridge().metadata(
          'f',
          'capital',
          'integrated:salary-refund:refund',
          0,
          {
            'capitalKind': 'contribution',
            'reason': 'Cannot double-classify refund',
          },
          'admin',
        ),
        throwsStateError,
      );
      await db.update(
        'finance_documents_v2',
        {'amount_minor': 9},
        where: 'id=?',
        whereArgs: ['integrated:salary-refund:refund'],
      );
      await expectLater(validate(), throwsStateError);
    },
  );
  test(
    'a failed refund reversal leaves original refund, cash and employee debt unchanged',
    () async {
      await salaryReady();
      await pay(amount: '1');
      await adjust(
        adjustment('a', delta: '-0.2', kind: PayrollAdjustmentKind.deduction),
      );
      await refund();
      final before = await db.query('finance_documents_v2');
      await db.execute(
        "CREATE TRIGGER fail_refund_undo BEFORE INSERT ON finance_documents_v2 WHEN NEW.category='INTEGRATED_PAYROLL_REFUND_REVERSAL' BEGIN SELECT RAISE(ABORT,'fail'); END",
      );
      await expectLater(
        refund(id: 'undo', reversesId: 'refund'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('finance_documents_v2'), before);
      expect((await db.query(SqlitePayrollAdjustments.refunds)).length, 1);
      expect((await current()).overpaid, '0.1');
      await validate();
    },
  );
  test(
    'logout or a changed membership blocks correction and refund before any write',
    () async {
      await salaryReady();
      live = const AuthorizationSubject(
        userId: 'other',
        membershipId: 'other',
        farmId: 'f',
        permissionCodes: PermissionCodes.values,
        dataScopes: {DataScope.allFarm},
      );
      expect(
        () => service.createPayrollAdjustment(admin, adjustment('a')),
        throwsStateError,
      );
      expect(() => refund(), throwsStateError);
      expect(await db.query(SqlitePayrollAdjustments.adjustments), isEmpty);
    },
  );
  test(
    'pre-adjustment backups with approved salary remain compatible when all correction tables are absent',
    () async {
      await salaryReady();
      await pay();
      final directory = await Directory.systemTemp.createTemp(
        'payroll-old-backup-',
      );
      final costs = await databaseFactoryFfi.openDatabase(
        '${directory.path}/costs.db',
      );
      await costs.execute('CREATE TABLE production_costs(id TEXT PRIMARY KEY)');
      try {
        final envelope =
            jsonDecode(
                  utf8.decode(
                    await LocalDatabaseSnapshot.create(
                      db,
                      costsDatabase: costs,
                    ),
                  ),
                )
                as Map<String, dynamic>;
        final payload =
            jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
        final tables =
            ((payload['databases'] as Map)['agrico.db'] as Map)['tables']
                as Map;
        for (final name in SqlitePayrollAdjustments.tables) {
          tables.remove(name);
        }
        final body = jsonEncode(payload);
        envelope['payload'] = body;
        envelope['sha256'] = sha256.convert(utf8.encode(body)).toString();
        await LocalRestorePreflight.validate(
          bytes: Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
          primary: db,
          costs: costs,
          factory: databaseFactoryFfi,
          temporaryDirectory: directory.path,
        );
        expect((await current()).remaining, '0.75');
        expect(await service.payrollAdjustments(admin), isEmpty);
      } finally {
        await costs.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'historical financial corrections retain a cancelled source plan without reopening work',
    () async {
      await salaryReady();
      await inventory.changeProductionPlanStatus(
        'f',
        'plan',
        1,
        ProductionPlanStatus.paused,
        'admin',
      );
      await inventory.changeProductionPlanStatus(
        'f',
        'plan',
        2,
        ProductionPlanStatus.cancelled,
        'admin',
      );
      final before = await db.query('production_plans_v1');
      await adjust(
        adjustment(
          'cancelled-plan',
          delta: '-0.2',
          allocations: [const PayrollCostAdjustment('plan', '-0.2')],
        ),
      );
      expect(await db.query('production_plans_v1'), before);
      expect(
        LaborMoney.sum((await service.laborCosts(admin)).map((c) => c.amount)),
        '0.8',
      );
      await validate();
    },
  );
  test(
    'two concurrent refund requests cannot collect the same employee receivable twice',
    () async {
      await salaryReady();
      await pay(amount: '1');
      await adjust(
        adjustment('a', delta: '-0.2', kind: PayrollAdjustmentKind.deduction),
      );
      final outcomes = await Future.wait(
        ['first', 'second'].map(
          (id) => refund(
            id: id,
            amount: '0.2',
          ).then((_) => true, onError: (_) => false),
        ),
      );
      expect(outcomes.where((v) => v).length, 1);
      expect((await current()).overpaid, '0');
      expect(
        (await db.query('finance_documents_v2', where: "kind='THU'")).length,
        1,
      );
      await validate();
    },
  );
  test(
    'historical unlinked payments need reconciliation before they can support an employee refund',
    () async {
      await salaryReady();
      await pay(amount: '1');
      await db.delete(
        'integration_cash_links_v1',
        where: 'source_id=?',
        whereArgs: ['pay'],
      );
      await db.delete(
        'finance_documents_v2',
        where: 'id=?',
        whereArgs: ['integrated:salary:pay'],
      );
      await adjust(
        adjustment('a', delta: '-0.2', kind: PayrollAdjustmentKind.deduction),
      );
      await expectLater(refund(amount: '0.2'), throwsStateError);
      await bridge().linkSalary('f', 'pay', 'admin');
      await refund(amount: '0.2');
      expect((await current()).remaining, '0');
      await validate();
      await IntegrationIntegrity.validate(db);
    },
  );
}
