import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/approval/native_approval_store.dart';
import 'package:agrico_deepseek/core/approval/native_approval_guard.dart';
import 'package:agrico_deepseek/core/approval/sqlite_approval_policy_store.dart';
import 'package:agrico_deepseek/core/approval/sqlite_document_approval.dart';
import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_farm_task_repository.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/production_plan.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/production_destination_repository.dart';
import 'package:agrico_deepseek/features/personnel/data/sqlite_personnel_repository.dart';
import 'package:agrico_deepseek/features/personnel/domain/personnel.dart' as hr;
import 'package:agrico_deepseek/features/machines/data/sqlite_machine_repository.dart';
import 'package:agrico_deepseek/features/machines/domain/machines.dart' as mc;
import 'package:agrico_deepseek/features/trade/data/sqlite_trade_repository.dart';
import 'package:agrico_deepseek/features/trade/domain/trade.dart';
import 'package:agrico_deepseek/features/integration/data/integration_repository.dart';
import 'package:agrico_deepseek/features/integration/data/production_cost_workflow_repository.dart';
import 'package:agrico_deepseek/features/integration/domain/production_cost_workflow.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import '../../support/approval_b_test_support.dart';
import 'package:agrico_deepseek/features/integration/data/native_approval_repository.dart';
import 'package:agrico_deepseek/features/integration/application/production_cost_projection.dart';
import 'package:agrico_deepseek/features/integration/domain/integration_snapshot.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late AuthorizationSubject live;
  late SyntheticApprovalAuthority authority;
  NativeApprovalRepository flow() => NativeApprovalRepository(
    SqliteApprovalPolicyStore(
      db,
      opened: live,
      currentSubject: () => live,
      authority: authority,
    ),
  );
  SqlitePersonnelRepository getHr() => SqlitePersonnelRepository(db);
  SqliteMachineRepository machines() => SqliteMachineRepository(db);
  SqliteInventoryRepository stock() => SqliteInventoryRepository(db);
  Future<void> approve(
    NativeApprovalType type,
    String id, {
    String maker = 'maker',
    String reviewer = 'reviewer',
  }) async {
    final ref = NativeApprovalRef(type, id);
    live = approvalUser(maker);
    await flow().submit(ref);
    live = approvalUser(reviewer);
    final result = await flow().approve(
      ref,
      'Synthetic independently reviewed native source',
    );
    expect(result.allowed, isTrue, reason: result.reason);
  }

  mc.MachineRun run({String id = 'run', int day = 20}) => mc.MachineRun(
    id: id,
    machineId: 'machine',
    operatorId: 'w',
    startsAt: DateTime.utc(2026, 10, day, 1),
    endsAt: DateTime.utc(2026, 10, day, 9),
    idleMinutes: 0,
    meterStart: '100',
    meterEnd: '108',
    allocations: const [
      mc.MachineAllocation('a', 240),
      mc.MachineAllocation('b', 240),
    ],
    segments: const [
      mc.MachineAllocation('a', 120),
      mc.MachineAllocation('b', 240),
      mc.MachineAllocation('a', 120),
    ],
  );
  Future<void> attendance({String id = 'entry'}) => getHr().createEntry(
    hr.LaborEntryDraft(
      id: id,
      farmId: 'f',
      workerId: 'w',
      startsAt: DateTime.utc(2026, 10, 21, 1),
      endsAt: DateTime.utc(2026, 10, 21, 9),
      breakMinutes: 0,
      overtimeMinutes: 0,
      allocations: const [
        hr.LaborAllocationDraft(
          planId: 'a',
          regularMinutes: 240,
          overtimeMinutes: 0,
        ),
        hr.LaborAllocationDraft(
          planId: 'b',
          regularMinutes: 240,
          overtimeMinutes: 0,
        ),
      ],
    ),
    'maker',
  );
  Future<void> payrollReady() async {
    await attendance();
    await approve(NativeApprovalType.fieldWork, 'entry');
    await getHr().createPayroll(
      const hr.PayrollDraft(
        id: 'payroll',
        farmId: 'f',
        workerId: 'w',
        period: '2026-10',
        currency: 'VND',
        allowance: '10',
        bonus: '5',
        adjustmentPlanId: 'a',
        note: 'Synthetic documented allowance and bonus',
      ),
      'maker',
    );
    await approve(NativeApprovalType.payroll, 'payroll');
  }

  Future<void> expense({
    String id = 'expense',
    String treatment = 'commonProduction',
  }) => SqliteTradeRepository(db).create(
    'f',
    TradeDraft(
      id: id,
      kind: TradeKind.expense,
      day: '2026-10-20',
      currency: 'VND',
      rounding: MoneyRounding.halfUp,
      partyId: 'vendor',
      planId: treatment == 'directProduction' ? 'a' : null,
      dueOn: '2026-10-25',
      reference: 'REF-$id',
      expenseTreatment: treatment,
      lines: const [
        TradeLine(
          ref: '',
          quantity: '1',
          price: '100',
          label: 'Synthetic service',
        ),
      ],
    ),
    'maker',
  );
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys=ON');
    live = approvalUser('maker');
    authority = SyntheticApprovalAuthority();
    authority.partyUsers.addAll({
      'w': {'worker-account'},
      'vendor': {},
    });
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
    final catalog = CompanyCatalogService(
      repository: SqliteCompanyCatalog(db),
      subject: approvalUser('setup'),
    );
    for (final pair in [
      ('unit', CatalogKind.unit),
      ('w', CatalogKind.worker),
      ('machine', CatalogKind.machine),
      ('vendor', CatalogKind.supplier),
      ('material', CatalogKind.material),
    ]) {
      await catalog.create(
        CatalogEntry(
          id: pair.$1,
          farmId: 'f',
          kind: pair.$2,
          code: '',
          name: pair.$1,
          unitId: pair.$2 == CatalogKind.material ? 'unit' : null,
        ),
        reason: 'Synthetic native catalog setup',
      );
    }
    await db.insert('land_parcels', {
      'id': 'land',
      'farm_id': 'f',
      'parcel_code': 'LO-TEST',
      'active': 1,
      'kind': 'fieldPlot',
    });
    await stock().createProductionSeason(
      const ProductionSeason(
        id: 'season',
        farmId: 'f',
        parcelId: 'land',
        name: 'Synthetic season',
        startsOn: '2026-10-01',
      ),
    );
    for (final id in ['a', 'b']) {
      await stock().createProductionPlan(
        ProductionPlan(
          id: id,
          farmId: 'f',
          parcelId: 'land',
          seasonId: 'season',
          name: id,
          crop: 'Peanut',
          startsOn: '2026-10-01',
          endsOn: '2026-10-31',
          currency: 'VND',
          materialBudget: '1000000',
          laborBudget: '1000000',
          machineBudget: '1000000',
          laborHours: '100',
          machineShifts: '5',
        ),
        'setup',
      );
      await stock().changeProductionPlanStatus(
        'f',
        id,
        0,
        ProductionPlanStatus.active,
        'setup',
      );
    }
    await machines().profile('f', 'machine', 0, {'meterUnit': 'hour'}, 'setup');
    await machines().addRate(
      'f',
      const mc.MachineRate(
        id: 'machine-rate',
        machineId: 'machine',
        effectiveOn: '2026-10-01',
        amount: '800000',
        currency: 'VND',
        shiftMinutes: 480,
        scale: 0,
        rounding: mc.MoneyRounding.halfUp,
      ),
      'setup',
    );
    await getHr().createRate(
      const hr.PayRate(
        id: 'labor-rate',
        farmId: 'f',
        workerId: 'w',
        effectiveOn: '2026-10-01',
        basis: hr.PayBasis.daily,
        rate: '80000',
        currency: 'VND',
        rounding: hr.MoneyRounding.halfUp,
        moneyScale: 0,
      ),
      'setup',
    );
    for (final kind in [
      ApprovalKind.machineRun,
      ApprovalKind.fieldWork,
      ApprovalKind.payroll,
      ApprovalKind.payrollAdjustment,
      ApprovalKind.directExpense,
      ApprovalKind.overheadAllocation,
      ApprovalKind.purchase,
      ApprovalKind.tradePosting,
      ApprovalKind.materialIssue,
      ApprovalKind.settlement,
      ApprovalKind.correction,
    ]) {
      await syntheticPolicy(db, authority, kind, 'VND', selfLimit: '1000000');
    }
    await NativeApprovalGuard.install(db);
  });
  tearDown(() async => db.close());
  test(
    'native machine approval blocks raw bypass then posts exact A B A cost once',
    () async {
      await machines().addRun('f', run(), 'maker');
      await expectLater(
        machines().approveRun('f', 'run', 0, 'maker'),
        throwsA(isA<DatabaseException>()),
      );
      expect((await db.query('machine_runs_v1')).single['status'], 'draft');
      expect(
        (await db.query('machine_costs_v1')).every((r) => r['amount'] == null),
        isTrue,
      );
      await approve(NativeApprovalType.machineRun, 'run');
      final costs = await db.query('machine_costs_v1', orderBy: 'plan_id');
      expect(costs.map((r) => r['amount']), ['400000', '400000']);
      expect(costs.map((r) => r['minutes']), [240, 240]);
      expect((await db.query('machine_runs_v1')).single['amount'], '800000');
      expect(
        (await flow().approve(
          const NativeApprovalRef(NativeApprovalType.machineRun, 'run'),
          'Unknown-outcome retry',
        )).allowed,
        isTrue,
      );
      expect((await db.query('machine_costs_v1')), hasLength(2));
    },
  );
  test(
    'native supervisor self approval is explicit and within verified limit',
    () async {
      await machines().addRun('f', run(), 'maker');
      await approve(NativeApprovalType.machineRun, 'run', reviewer: 'maker');
      expect(
        (await db.query(SqliteDocumentApproval.requests)).single['decided_by'],
        'maker',
      );
    },
  );
  test(
    'native machine beneficiary cannot approve and split related runs require independent review',
    () async {
      await machines().addRun('f', run(), 'maker');
      live = approvalUser('maker');
      await flow().submit(
        const NativeApprovalRef(NativeApprovalType.machineRun, 'run'),
      );
      live = approvalUser('worker-account');
      expect(
        (await flow().approve(
          const NativeApprovalRef(NativeApprovalType.machineRun, 'run'),
          'Operator conflict',
        )).reason,
        'conflictOfInterest',
      );
      live = approvalUser('maker');
      await expectLater(
        machines().addRun('f', run(id: 'overlap', day: 20), 'maker'),
        throwsStateError,
      );
      // The native overlap assertion remains enforced independently of policy B.
      expect((await db.query('machine_runs_v1')), hasLength(1));
      await machines().addRun(
        'f',
        mc.MachineRun(
          id: 'run-2',
          machineId: 'machine',
          operatorId: 'w',
          startsAt: DateTime.utc(2026, 10, 20, 9),
          endsAt: DateTime.utc(2026, 10, 20, 13),
          idleMinutes: 0,
          meterStart: '108',
          meterEnd: '112',
          allocations: const [
            mc.MachineAllocation('a', 120),
            mc.MachineAllocation('b', 120),
          ],
        ),
        'maker',
      );
      expect(
        (await flow().approve(
          const NativeApprovalRef(NativeApprovalType.machineRun, 'run'),
          'Two related runs',
        )).reason,
        'relatedDocumentsRequireIndependentReview',
      );
    },
  );
  test(
    'field work uses actual native rate, creator, revision and allocations',
    () async {
      await attendance();
      await expectLater(
        getHr().approveEntry('f', 'entry', 0, 'maker'),
        throwsA(isA<DatabaseException>()),
      );
      await approve(NativeApprovalType.fieldWork, 'entry');
      expect(
        (await db.query('personnel_entries_v1')).single['total_amount'],
        '80000',
      );
      expect(
        (await db.query(
          'production_labor_costs_v1',
          orderBy: 'plan_id',
        )).map((r) => r['amount']),
        ['40000', '40000'],
      );
    },
  );
  test(
    'official payroll and bonuses cannot self approve, native independent approval succeeds',
    () async {
      await attendance();
      await approve(NativeApprovalType.fieldWork, 'entry');
      await getHr().createPayroll(
        const hr.PayrollDraft(
          id: 'payroll',
          farmId: 'f',
          workerId: 'w',
          period: '2026-10',
          currency: 'VND',
          allowance: '10',
          bonus: '5',
          adjustmentPlanId: 'a',
          note: 'Synthetic documented allowance and bonus',
        ),
        'maker',
      );
      live = approvalUser('maker');
      await flow().submit(
        const NativeApprovalRef(NativeApprovalType.payroll, 'payroll'),
      );
      expect(
        (await flow().approve(
          const NativeApprovalRef(NativeApprovalType.payroll, 'payroll'),
          'Creator owns payroll draft',
        )).allowed,
        isFalse,
      );
      live = approvalUser('reviewer');
      expect(
        (await flow().approve(
          const NativeApprovalRef(NativeApprovalType.payroll, 'payroll'),
          'Independent payroll review',
        )).allowed,
        isTrue,
      );
      expect((await db.query('personnel_payrolls_v1')).single['net'], '80015');
    },
  );
  test(
    'native payroll payment command is pending until independent atomic cash posting',
    () async {
      await payrollReady();
      live = approvalUser('maker');
      await flow().proposeCommand(
        id: 'salary-payment',
        operation: 'payrollPay',
        target: const NativeApprovalRef(NativeApprovalType.payroll, 'payroll'),
        payload: {
          'amount': '80015',
          'day': '2026-10-22',
          'reason': 'Synthetic bank payment',
        },
      );
      expect(await db.query('finance_documents_v2'), isEmpty);
      expect(await db.query('personnel_payments_v1'), isEmpty);
      await approve(NativeApprovalType.command, 'salary-payment');
      expect((await db.query('finance_documents_v2')), hasLength(1));
      expect((await db.query('personnel_payments_v1')), hasLength(1));
      expect((await db.query('integration_cash_links_v1')), hasLength(1));
    },
  );
  test(
    'native payroll adjustment preserves exact delta and independent source approval',
    () async {
      await payrollReady();
      await getHr().createPayrollAdjustment(
        const hr.PayrollAdjustmentDraft(
          id: 'adjustment',
          farmId: 'f',
          payrollId: 'payroll',
          currency: 'VND',
          day: '2026-10-23',
          delta: '5',
          reason: 'Synthetic approved earnings correction',
          expectedRevision: 0,
          allocations: [hr.PayrollCostAdjustment('a', '5')],
        ),
        'maker',
      );
      await expectLater(
        getHr().approvePayrollAdjustment('f', 'adjustment', 'maker'),
        throwsA(isA<DatabaseException>()),
      );
      await approve(NativeApprovalType.payrollAdjustment, 'adjustment');
      expect(
        (await db.query('personnel_payroll_adjustments_v1')).single['status'],
        'approved',
      );
      expect(
        (await db.query(
          'personnel_payroll_adjustment_costs_v1',
        )).single['amount'],
        '5',
      );
    },
  );
  test(
    'native expense posting, overhead allocation and settlement all require B',
    () async {
      await expense();
      await expectLater(
        SqliteTradeRepository(db).post('f', 'expense', 0, 'maker'),
        throwsA(isA<DatabaseException>()),
      );
      await approve(NativeApprovalType.trade, 'expense');
      await ProductionCostWorkflowRepository(db).proposeExpense(
        'f',
        ExpenseAllocationProposal(
          expenseId: 'expense',
          driver: CostAllocationDriver.approvedWeights,
          baseUnits: 2,
          moneyScale: 0,
          weights: const [
            CostAllocationWeight('a', 1, 'Synthetic approved basis'),
            CostAllocationWeight('b', 1, 'Synthetic approved basis'),
          ],
        ),
        'maker',
        () {},
      );
      await expectLater(
        ProductionCostWorkflowRepository(
          db,
        ).approveExpense('f', 'expense', 1, 'maker', () {}),
        throwsA(isA<DatabaseException>()),
      );
      await approve(NativeApprovalType.expenseAllocation, 'expense');
      expect(
        (await db.query(
          ProductionCostWorkflowRepository.costs,
          orderBy: 'plan_id',
        )).map((r) => r['amount']),
        ['50', '50'],
      );
      live = approvalUser('maker');
      await flow().proposeCommand(
        id: 'settlement',
        operation: 'tradeSettle',
        target: const NativeApprovalRef(NativeApprovalType.trade, 'expense'),
        payload: {
          'amount': '100',
          'day': '2026-10-22',
          'reference': 'NATIVE-REF',
          'reason': 'Approved vendor payment',
        },
      );
      await approve(NativeApprovalType.command, 'settlement');
      expect((await db.query('finance_documents_v2')), hasLength(1));
    },
  );
  test(
    'native direct-production expense uses B independently from allocation, without duplicate cost',
    () async {
      await expense(treatment: 'directProduction');
      await approve(NativeApprovalType.trade, 'expense');
      await ProductionCostWorkflowRepository(db).proposeExpense(
        'f',
        ExpenseAllocationProposal(
          expenseId: 'expense',
          driver: CostAllocationDriver.direct,
          baseUnits: 1,
          moneyScale: 0,
          weights: const [CostAllocationWeight('a', 1, 'Direct plan binding')],
        ),
        'maker',
        () {},
      );
      await approve(NativeApprovalType.expenseAllocation, 'expense');
      expect(
        (await db.query(
          ProductionCostWorkflowRepository.costs,
        )).single['amount'],
        '100',
      );
    },
  );
  test(
    'native material issue cost cannot be recognized by calling old metadata approval directly',
    () async {
      await stock().record(
        InventoryMovement(
          id: 'receipt',
          farmId: 'f',
          itemId: 'material',
          kind: InventoryMovementKind.receipt,
          quantity: 10,
          occurredAt: DateTime(2026, 10, 19),
          unitPriceText: '2',
          currency: 'VND',
          pricedBy: 'maker',
        ),
      );
      await stock().recordProductionIssue(
        InventoryMovement(
          id: 'issue',
          farmId: 'f',
          itemId: 'material',
          kind: InventoryMovementKind.issue,
          quantity: 2,
          occurredAt: DateTime(2026, 10, 20),
          unitPriceText: '2',
          currency: 'VND',
          pricedBy: 'maker',
        ),
        parcelId: 'land',
        seasonId: 'season',
        planId: 'a',
      );
      await expectLater(
        ProductionCostWorkflowRepository(
          db,
        ).approveMaterial('f', 'issue', 1, 'maker', () {}),
        throwsA(isA<DatabaseException>()),
      );
      await approve(NativeApprovalType.material, 'issue');
      expect(
        (await db.query(
          'production_source_versions_v2',
          where: "source_type='material'",
        )).single['approver'],
        'reviewer',
      );
      expect(
        (await db.query('production_material_costs_v2')).single['amount_text'],
        '4',
      );
    },
  );
  test(
    'native machine B proof is present in projection and cannot be omitted',
    () async {
      await machines().addRun('f', run(), 'maker');
      await approve(NativeApprovalType.machineRun, 'run');
      final snapshot = await IntegrationRepository(db).snapshot('f', '2026-10');
      final projection = ProductionCostProjection(snapshot);
      expect(
        projection.entries.where((e) => e.sourceType == 'machine'),
        hasLength(2),
      );
      expect(
        projection.entries
            .where((e) => e.sourceType == 'machine')
            .every((e) => !e.issues.contains('missingNativeBApproval')),
        isTrue,
      );
      final tampered = IntegrationSnapshot(
        farm: 'f',
        period: '2026-10',
        tables: {...snapshot.tables, SqliteDocumentApproval.requests: []},
        machineAudit: snapshot.machineAudit,
        sourceAudit: snapshot.sourceAudit,
        sourceCoverageVerified: true,
      );
      expect(
        ProductionCostProjection(tampered).entries
            .where((e) => e.sourceType == 'machine')
            .every((e) => e.issues.contains('missingNativeBApproval')),
        isTrue,
      );
    },
  );
  test(
    'machine correction command preserves independent approval and voids native source',
    () async {
      await machines().addRun('f', run(), 'maker');
      await approve(NativeApprovalType.machineRun, 'run');
      live = approvalUser('maker');
      await flow().proposeCommand(
        id: 'void-run',
        operation: 'machineVoid',
        target: const NativeApprovalRef(NativeApprovalType.machineRun, 'run'),
        payload: {'day': '2026-10-22', 'reason': 'Synthetic run correction'},
      );
      await approve(NativeApprovalType.command, 'void-run');
      expect((await db.query('machine_runs_v1')).single['status'], 'void');
      expect(
        (await flow().approve(
          const NativeApprovalRef(NativeApprovalType.command, 'void-run'),
          'Retry void',
        )).allowed,
        isTrue,
      );
    },
  );
  test('field correction uses native void and keeps audit', () async {
    await attendance();
    await approve(NativeApprovalType.fieldWork, 'entry');
    live = approvalUser('maker');
    await flow().proposeCommand(
      id: 'void-entry',
      operation: 'fieldVoid',
      target: const NativeApprovalRef(NativeApprovalType.fieldWork, 'entry'),
      payload: {'day': '2026-10-22', 'reason': 'Synthetic work correction'},
    );
    await approve(NativeApprovalType.command, 'void-entry');
    expect((await db.query('personnel_entries_v1')).single['status'], 'void');
  });
  test(
    'trade settlement reversal posts opposite cash only after B approval',
    () async {
      await expense();
      await approve(NativeApprovalType.trade, 'expense');
      live = approvalUser('maker');
      await flow().proposeCommand(
        id: 'paid',
        operation: 'tradeSettle',
        target: const NativeApprovalRef(NativeApprovalType.trade, 'expense'),
        payload: {
          'amount': '100',
          'day': '2026-10-22',
          'reference': 'SYNTHETIC-PAYMENT',
        },
      );
      await approve(NativeApprovalType.command, 'paid');
      live = approvalUser('maker');
      await flow().proposeCommand(
        id: 'reverse-paid',
        operation: 'tradeReverse',
        target: const NativeApprovalRef(NativeApprovalType.trade, 'expense'),
        payload: {
          'paymentId': 'paid',
          'day': '2026-10-23',
          'reason': 'Synthetic reversal',
        },
      );
      expect(await db.query('finance_documents_v2'), hasLength(1));
      await approve(NativeApprovalType.command, 'reverse-paid');
      expect(await db.query('finance_documents_v2'), hasLength(2));
      expect(await db.query('trade_reversals_v1'), hasLength(1));
      await NativeApprovalGuard.validate(db);
    },
  );
  test(
    'trade void creates real reversal provenance authored by proposer and independently approved',
    () async {
      await expense(treatment: 'directProduction');
      await approve(NativeApprovalType.trade, 'expense');
      live = approvalUser('maker');
      await flow().proposeCommand(
        id: 'void-expense',
        operation: 'tradeVoid',
        target: const NativeApprovalRef(NativeApprovalType.trade, 'expense'),
        payload: {'day': '2026-10-23', 'reason': 'Synthetic expense void'},
      );
      await approve(NativeApprovalType.command, 'void-expense');
      expect((await db.query('trade_documents_v1')).single['status'], 'void');
      await NativeApprovalGuard.validate(db);
    },
  );
  test('salary reversal requires B before opposite cash posting', () async {
    await payrollReady();
    live = approvalUser('maker');
    await flow().proposeCommand(
      id: 'paid-salary',
      operation: 'payrollPay',
      target: const NativeApprovalRef(NativeApprovalType.payroll, 'payroll'),
      payload: {
        'amount': '80015',
        'day': '2026-10-22',
        'reason': 'Synthetic salary',
      },
    );
    await approve(NativeApprovalType.command, 'paid-salary');
    live = approvalUser('maker');
    await flow().proposeCommand(
      id: 'reverse-salary',
      operation: 'salaryReverse',
      target: const NativeApprovalRef(NativeApprovalType.payroll, 'payroll'),
      payload: {
        'paymentId': 'paid-salary',
        'day': '2026-10-23',
        'reason': 'Synthetic salary reversal',
      },
    );
    await approve(NativeApprovalType.command, 'reverse-salary');
    expect(await db.query('finance_documents_v2'), hasLength(2));
    expect(await db.query('integration_salary_reversals_v1'), hasLength(1));
    await NativeApprovalGuard.validate(db);
  });
  test(
    'scoped reviewer only lists assigned native machines and clears access on revocation',
    () async {
      await machines().addRun('f', run(), 'maker');
      live = const AuthorizationSubject(
        userId: 'scoped',
        membershipId: 'scoped',
        farmId: 'f',
        permissionCodes: {
          PermissionCodes.machineView,
          PermissionCodes.financeView,
        },
        dataScopes: {DataScope.assignedMachines},
        assignedMachineIds: {'machine'},
      );
      final store = flow();
      expect(store.canView(), isTrue);
      expect(await store.list({NativeApprovalType.machineRun}), hasLength(1));
      live = const AuthorizationSubject(
        userId: 'scoped',
        membershipId: 'scoped',
        farmId: 'f',
        permissionCodes: {
          PermissionCodes.machineView,
          PermissionCodes.financeView,
        },
        dataScopes: {DataScope.assignedMachines},
        assignedMachineIds: {'other'},
      );
      expect(await store.list({NativeApprovalType.machineRun}), isEmpty);
      live = approvalUser('other-account');
      expect(store.canView(), isFalse);
      await expectLater(
        store.list({NativeApprovalType.machineRun}),
        throwsStateError,
      );
    },
  );
  test(
    'native maintenance approval and payable command do not duplicate all-inclusive machine cost',
    () async {
      await machines().addExpense(
        'f',
        const mc.MachineExpense(
          id: 'maintenance',
          machineId: 'machine',
          kind: 'maintenance',
          day: '2026-10-20',
          amount: '100',
          currency: 'VND',
          reference: 'TEST-MAINT',
          note: 'Synthetic maintenance',
          partyId: 'vendor',
        ),
        'maker',
      );
      await approve(NativeApprovalType.machineExpense, 'maintenance');
      expect(await db.query('machine_costs_v1'), isEmpty);
      live = approvalUser('maker');
      await flow().proposeCommand(
        id: 'machine-payable',
        operation: 'machinePayable',
        target: const NativeApprovalRef(
          NativeApprovalType.machineExpense,
          'maintenance',
        ),
        payload: {
          'day': '2026-10-22',
          'reference': 'TEST-PAYABLE',
          'rounding': 'halfUp',
        },
      );
      await approve(NativeApprovalType.command, 'machine-payable');
      expect(await db.query('integration_machine_links_v1'), hasLength(1));
      expect(await db.query('trade_documents_v1'), hasLength(1));
      expect(await db.query('machine_costs_v1'), isEmpty);
      expect(await db.query('finance_documents_v2'), isEmpty);
    },
  );
  test(
    'purchase posts inventory exactly once only with independent B approval',
    () async {
      await SqliteTradeRepository(db).create(
        'f',
        const TradeDraft(
          id: 'purchase',
          kind: TradeKind.purchase,
          day: '2026-10-20',
          currency: 'VND',
          rounding: MoneyRounding.down,
          partyId: 'vendor',
          reference: 'SYNTHETIC-PO',
          dueOn: '2026-10-25',
          lines: [TradeLine(ref: 'material', quantity: '3', price: '7')],
        ),
        'maker',
      );
      live = approvalUser('maker');
      const ref = NativeApprovalRef(NativeApprovalType.trade, 'purchase');
      await flow().submit(ref);
      expect(
        (await flow().approve(ref, 'Self purchase rejected')).allowed,
        isFalse,
      );
      live = approvalUser('reviewer');
      expect(
        (await flow().approve(ref, 'Independent purchase')).allowed,
        isTrue,
      );
      expect((await flow().approve(ref, 'Retry purchase')).allowed, isTrue);
      expect((await db.query('trade_documents_v1')).single['status'], 'posted');
      expect(await db.query('trade_stock_links_v1'), hasLength(1));
      expect(await db.query('finance_documents_v2'), isEmpty);
    },
  );
  test(
    'payroll recovery and recovery reversal preserve approved exact correction and cash',
    () async {
      await payrollReady();
      live = approvalUser('maker');
      const target = NativeApprovalRef(NativeApprovalType.payroll, 'payroll');
      await flow().proposeCommand(
        id: 'salary-for-refund',
        operation: 'payrollPay',
        target: target,
        payload: {
          'amount': '80015',
          'day': '2026-10-22',
          'reason': 'Synthetic salary',
        },
      );
      await approve(NativeApprovalType.command, 'salary-for-refund');
      await getHr().createPayrollAdjustment(
        const hr.PayrollAdjustmentDraft(
          id: 'negative-adjustment',
          farmId: 'f',
          payrollId: 'payroll',
          currency: 'VND',
          day: '2026-10-23',
          delta: '-15',
          reason: 'Synthetic overpayment correction',
          expectedRevision: 0,
          allocations: [hr.PayrollCostAdjustment('a', '-15')],
        ),
        'maker',
      );
      await approve(
        NativeApprovalType.payrollAdjustment,
        'negative-adjustment',
      );
      live = approvalUser('maker');
      await flow().proposeCommand(
        id: 'refund',
        operation: 'payrollRefund',
        target: target,
        payload: {
          'amount': '15',
          'day': '2026-10-24',
          'reason': 'Synthetic overpayment recovered',
        },
      );
      await approve(NativeApprovalType.command, 'refund');
      expect(await db.query('finance_documents_v2'), hasLength(2));
      live = approvalUser('maker');
      await flow().proposeCommand(
        id: 'refund-reversal',
        operation: 'payrollRefundReverse',
        target: target,
        payload: {
          'amount': '15',
          'refundId': 'refund',
          'day': '2026-10-25',
          'reason': 'Synthetic refund reversal',
        },
      );
      await approve(NativeApprovalType.command, 'refund-reversal');
      expect(await db.query('finance_documents_v2'), hasLength(3));
      expect(await db.query('personnel_payroll_refunds_v1'), hasLength(2));
      expect((await db.query('personnel_payrolls_v1')).single['net'], '80015');
      await NativeApprovalGuard.validate(db);
    },
  );
  test(
    'fuel linkage and reversal require native B and raw writers roll back stock',
    () async {
      await stock().record(
        InventoryMovement(
          id: 'fuel-stock',
          farmId: 'f',
          itemId: 'material',
          kind: InventoryMovementKind.receipt,
          quantity: 10,
          occurredAt: DateTime(2026, 10, 19),
          unitPriceText: '10',
          currency: 'VND',
          pricedBy: 'maker',
        ),
      );
      // Synthetic fixture unit is litres; no implicit business unit conversion.
      await db.update(
        'inventory_items_v2',
        {'unit': 'l'},
        where: 'id=?',
        whereArgs: ['material'],
      );
      await machines().addExpense(
        'f',
        const mc.MachineExpense(
          id: 'fuel',
          machineId: 'machine',
          kind: 'fuel',
          day: '2026-10-20',
          amount: '100',
          currency: 'VND',
          reference: 'FUEL-TEST',
          note: 'Synthetic fuel',
          litres: '2',
          partyId: 'vendor',
        ),
        'maker',
      );
      await approve(NativeApprovalType.machineExpense, 'fuel');
      await expectLater(
        IntegrationRepository(
          db,
        ).fuelIssue('f', 'fuel', 'material', '10', false, 'reviewer'),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await db.query('inventory_items_v2')).single['stock_units'],
        10000000,
      );
      live = approvalUser('maker');
      await flow().proposeCommand(
        id: 'fuel-issue',
        operation: 'fuelIssue',
        target: const NativeApprovalRef(
          NativeApprovalType.machineExpense,
          'fuel',
        ),
        payload: {
          'day': '2026-10-20',
          'itemId': 'material',
          'price': '10',
          'reason': 'Synthetic internal fuel',
        },
      );
      await approve(NativeApprovalType.command, 'fuel-issue');
      expect(
        (await db.query('inventory_items_v2')).single['stock_units'],
        8000000,
      );
      expect(await db.query('machine_costs_v1'), isEmpty);
      await expectLater(
        IntegrationRepository(
          db,
        ).reverseFuel('f', 'fuel', '2026-10-22', 'Raw bypass', 'reviewer'),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await db.query('inventory_items_v2')).single['stock_units'],
        8000000,
      );
      live = approvalUser('maker');
      await flow().proposeCommand(
        id: 'fuel-reverse',
        operation: 'fuelReverse',
        target: const NativeApprovalRef(
          NativeApprovalType.machineExpense,
          'fuel',
        ),
        payload: {'day': '2026-10-22', 'reason': 'Synthetic fuel return'},
      );
      await approve(NativeApprovalType.command, 'fuel-reverse');
      expect(
        (await db.query('inventory_items_v2')).single['stock_units'],
        10000000,
      );
      expect(
        (await flow().approve(
          const NativeApprovalRef(NativeApprovalType.command, 'fuel-reverse'),
          'Retry fuel reversal',
        )).allowed,
        isTrue,
      );
      expect(await db.query('finance_documents_v2'), isEmpty);
      await NativeApprovalGuard.validate(db);
    },
  );
  test(
    'audit: repeated schema bootstrap preserves approved rows and denies raw writers',
    () async {
      await machines().addRun('f', run(), 'maker');
      await approve(NativeApprovalType.machineRun, 'run');
      final before = await db.query('machine_runs_v1');
      final costs = await db.query('machine_costs_v1');
      for (var i = 0; i < 2; i++) {
        await SqliteInventoryRepository.createSchema(db);
        await SqlitePersonnelRepository.createSchema(db);
        await SqliteMachineRepository.createSchema(db);
        await SqliteFinanceDocumentRepository.createSchema(db);
        await SqliteTradeRepository.createSchema(db);
        await IntegrationRepository.createSchema(db);
        await NativeApprovalGuard.install(db);
      }
      expect(await db.query('machine_runs_v1'), before);
      expect(await db.query('machine_costs_v1'), costs);
      await NativeApprovalGuard.validate(db);
      await SqliteDocumentApproval.validate(db);
      await expectLater(
        machines().voidRun(
          'f',
          'run',
          1,
          'Raw bypass after bootstrap',
          'reviewer',
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
  test(
    'audit: salary link command acknowledges existing native cash without duplication',
    () async {
      await payrollReady();
      live = approvalUser('maker');
      const target = NativeApprovalRef(NativeApprovalType.payroll, 'payroll');
      await flow().proposeCommand(
        id: 'audit-pay',
        operation: 'payrollPay',
        target: target,
        payload: {
          'amount': '80015',
          'day': '2026-10-22',
          'reason': 'Synthetic payroll paid',
        },
      );
      await approve(NativeApprovalType.command, 'audit-pay');
      live = approvalUser('maker');
      await flow().proposeCommand(
        id: 'audit-link',
        operation: 'salaryLink',
        target: target,
        payload: {
          'paymentId': 'audit-pay',
          'day': '2026-10-23',
          'reason': 'Verify existing salary linkage',
        },
      );
      await approve(NativeApprovalType.command, 'audit-link');
      expect(await db.query('finance_documents_v2'), hasLength(1));
      expect(await db.query('integration_cash_links_v1'), hasLength(1));
      await NativeApprovalGuard.validate(db);
    },
  );
  test(
    'audit: harvest and sale use native B posting with exact stock and no payment duplication',
    () async {
      final catalog = CompanyCatalogService(
        repository: SqliteCompanyCatalog(db),
        subject: approvalUser('setup'),
      );
      await catalog.create(
        const CatalogEntry(
          id: 'product',
          farmId: 'f',
          kind: CatalogKind.product,
          code: '',
          name: 'Synthetic product',
          unitId: 'unit',
        ),
        reason: 'Audit native harvest fixture',
      );
      await catalog.create(
        const CatalogEntry(
          id: 'customer',
          farmId: 'f',
          kind: CatalogKind.customer,
          code: '',
          name: 'Synthetic customer',
        ),
        reason: 'Audit native sale fixture',
      );
      authority.partyUsers['customer'] = {};
      await SqliteTradeRepository(db).create(
        'f',
        const TradeDraft(
          id: 'harvest',
          kind: TradeKind.harvest,
          day: '2026-10-20',
          currency: 'VND',
          rounding: MoneyRounding.halfUp,
          planId: 'a',
          lines: [TradeLine(ref: 'product', quantity: '10', price: '5')],
        ),
        'maker',
      );
      await approve(NativeApprovalType.trade, 'harvest');
      await SqliteTradeRepository(db).create(
        'f',
        const TradeDraft(
          id: 'sale',
          kind: TradeKind.sale,
          day: '2026-10-21',
          currency: 'VND',
          rounding: MoneyRounding.halfUp,
          partyId: 'customer',
          dueOn: '2026-10-25',
          lines: [
            TradeLine(
              ref: 'harvest:0',
              quantity: '4',
              price: '10',
              issuePrice: '5',
            ),
          ],
        ),
        'maker',
      );
      await approve(NativeApprovalType.trade, 'sale');
      expect((await db.query('trade_lots_v1')).single['stock_units'], 6000000);
      expect(await db.query('finance_documents_v2'), isEmpty);
      expect(
        (await flow().approve(
          const NativeApprovalRef(NativeApprovalType.trade, 'sale'),
          'Retry same posted sale',
        )).allowed,
        isTrue,
      );
      expect(await db.query('finance_documents_v2'), isEmpty);
    },
  );
}
