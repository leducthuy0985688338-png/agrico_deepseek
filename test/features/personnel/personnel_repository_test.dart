import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:crypto/crypto.dart';
import 'package:agrico_deepseek/features/personnel/application/personnel_report.dart';
import 'package:agrico_deepseek/features/inventory/application/production_plan_report.dart';
import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_restore_preflight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_farm_task_repository.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/production_destination_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/production_plan.dart';
import 'package:agrico_deepseek/features/personnel/application/personnel_service.dart';
import 'package:agrico_deepseek/features/personnel/data/sqlite_personnel_repository.dart';
import 'package:agrico_deepseek/features/personnel/data/personnel_integrity.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqlitePersonnelRepository repo;
  late PersonnelService service;
  late AuthorizationSubject live;
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
    live = admin;
    service = PersonnelService(repo, currentSubject: () => live);
  });
  tearDown(() => db.close());
  test(
    'employee profile extends shared worker identity and enforces revisions',
    () async {
      final first = (await service.employees(admin)).single;
      expect(first.workerId, 'w');
      expect(first.code, isNotEmpty);
      await service.saveProfile(
        admin,
        EmployeeProfile(
          workerId: 'w',
          farmId: 'f',
          details: {'phone': '123', 'bankAccount': 'secret'},
        ),
      );
      final saved = (await service.employees(admin)).single;
      expect(saved.profile!.revision, 1);
      await expectLater(
        service.saveProfile(
          admin,
          EmployeeProfile(
            workerId: 'w',
            farmId: 'f',
            details: {'phone': '456'},
          ),
        ),
        throwsStateError,
      );
      expect((await service.employees(admin)).single.code, first.code);
      expect(
        await db.query('company_catalog_entries_v1', where: "kind='worker'"),
        hasLength(1),
      );
    },
  );
  test(
    'ordinary eight hours and approved overtime are separate exact amounts',
    () async {
      await service.createRate(admin, rate());
      await approve(entry('a'));
      final e = await saved('a');
      expect(e.regularMinutes, 480);
      expect(e.overtimeMinutes, 120);
      expect(e.regularAmount, '80000');
      expect(e.overtimeAmount, '30000');
      expect(e.total, '110000');
      expect((await repo.productionLaborCosts('f')).single.amount, '110000');
      await PersonnelIntegrity.validate(db);
    },
  );
  test(
    'missing effective rate or missing overtime rate does not partly approve',
    () async {
      await service.createEntry(admin, entry('a'));
      await expectLater(
        service.approveEntry(admin, await saved('a')),
        throwsStateError,
      );
      await service.createRate(admin, rate(ot: null));
      await expectLater(
        service.approveEntry(admin, await saved('a')),
        throwsStateError,
      );
      expect((await saved('a')).status, 'draft');
      expect(await repo.productionLaborCosts('f'), isEmpty);
    },
  );
  test(
    'hourly and piece pay use selected rates and preserve historical snapshots',
    () async {
      await service.createRate(
        admin,
        rate(basis: PayBasis.hourly, amount: '10000'),
      );
      await approve(entry('a', hours: 4, overtime: 0));
      expect((await saved('a')).total, '40000');
      await service.createRate(
        admin,
        rate(
          id: 'piece',
          day: '2026-10-26',
          basis: PayBasis.piece,
          amount: '50000',
        ),
      );
      await approve(
        entry('b', day: 26, hours: 4, overtime: 0, quantity: '2.5'),
      );
      expect((await saved('b')).pieceAmount, '125000');
      expect((await saved('b')).regularAmount, '0');
      expect((await saved('a')).total, '40000');
      await PersonnelIntegrity.validate(db);
    },
  );
  test('overnight shift uses Laos start day and deducts breaks', () async {
    await service.createRate(admin, rate());
    await approve(
      entry('night', start: 22, hours: 9, breakMinutes: 60, overtime: 0),
    );
    final e = await saved('night');
    expect(e.businessDay, '2026-10-25');
    expect(e.regularMinutes, 480);
    expect(e.total, '80000');
  });
  test(
    'overlapping time and time-versus-piece double counting are blocked',
    () async {
      await service.createEntry(admin, entry('a', hours: 4, overtime: 0));
      await expectLater(
        service.createEntry(
          admin,
          entry('b', start: 10, hours: 4, overtime: 0, quantity: '1'),
        ),
        throwsStateError,
      );
      expect(await service.entries(admin), hasLength(1));
    },
  );
  test('two shifts share the daily regular-time cap', () async {
    await service.createRate(admin, rate());
    await approve(entry('a', hours: 5, overtime: 0));
    await service.createEntry(
      admin,
      entry('b', start: 14, hours: 5, overtime: 0),
    );
    await expectLater(
      service.approveEntry(admin, await saved('b')),
      throwsStateError,
    );
    expect((await saved('b')).status, 'draft');
  });
  test(
    'allocation shares balance smallest money units without duplicating earnings',
    () async {
      await service.createRate(admin, rate(amount: '2'));
      for (final id in ['p2', 'p3', 'p4']) {
        await addPlan(id);
      }
      final draft = LaborEntryDraft(
        id: 'split',
        farmId: 'f',
        workerId: 'w',
        startsAt: DateTime.utc(2026, 10, 25, 1),
        endsAt: DateTime.utc(2026, 10, 25, 9),
        breakMinutes: 0,
        overtimeMinutes: 0,
        allocations: [
          for (final p in ['plan', 'p2', 'p3', 'p4'])
            LaborAllocationDraft(
              planId: p,
              regularMinutes: 120,
              overtimeMinutes: 0,
            ),
        ],
      );
      await approve(draft);
      final costs = await repo.productionLaborCosts('f');
      expect(LaborMoney.sum(costs.map((c) => c.amount)), '2');
      expect(costs.map((c) => c.amount).toList(), ['1', '1', '0', '0']);
      await PersonnelIntegrity.validate(db);
    },
  );
  test(
    'partial allocation leaves a visible remainder without inventing costs',
    () async {
      await service.createRate(admin, rate());
      final d = LaborEntryDraft(
        id: 'partial',
        farmId: 'f',
        workerId: 'w',
        startsAt: DateTime.utc(2026, 10, 25, 1),
        endsAt: DateTime.utc(2026, 10, 25, 9),
        breakMinutes: 0,
        overtimeMinutes: 0,
        allocations: const [
          LaborAllocationDraft(
            planId: 'plan',
            regularMinutes: 240,
            overtimeMinutes: 0,
          ),
        ],
      );
      await approve(d);
      expect((await repo.productionLaborCosts('f')).single.amount, '40000');
      expect((await saved('partial')).total, '80000');
    },
  );
  test(
    'all-inclusive machine labor is paid but not charged to production again',
    () async {
      await service.createRate(admin, rate());
      await approve(entry('driver', hours: 8, overtime: 0, machine: 'machine'));
      expect((await saved('driver')).total, '80000');
      expect((await repo.productionLaborCosts('f')).single.amount, '0');
      await PersonnelIntegrity.validate(db);
    },
  );
  test(
    'foreign worker plan currency and stale approval are rejected',
    () async {
      await service.createRate(admin, rate(currency: 'LAK'));
      await service.createEntry(admin, entry('a'));
      await expectLater(
        service.approveEntry(admin, await saved('a')),
        throwsStateError,
      );
      expect(await repo.productionLaborCosts('f'), isEmpty);
      await expectLater(
        service.saveProfile(
          admin,
          EmployeeProfile(workerId: 'machine', farmId: 'f', details: {}),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'approval rollback is atomic when labor snapshot insert/update fails',
    () async {
      await service.createRate(admin, rate());
      await service.createEntry(admin, entry('a'));
      await db.execute(
        "CREATE TRIGGER fail_labor BEFORE UPDATE ON production_labor_costs_v1 BEGIN SELECT RAISE(ABORT,'test'); END",
      );
      await expectLater(
        service.approveEntry(admin, await saved('a')),
        throwsA(isA<DatabaseException>()),
      );
      expect((await saved('a')).status, 'draft');
      expect(await repo.productionLaborCosts('f'), isEmpty);
    },
  );
  test(
    'payroll groups approved period/currency and payment never creates costs twice',
    () async {
      await service.createRate(admin, rate());
      await approve(entry('a'));
      await service.createPayroll(
        admin,
        const PayrollDraft(
          id: 'salary',
          farmId: 'f',
          workerId: 'w',
          period: '2026-10',
          currency: 'VND',
          allowance: '5000',
          advance: '10000',
          note: 'Approved adjustment',
          adjustmentPlanId: 'plan',
        ),
      );
      final before = await repo.productionLaborCosts('f');
      expect(before.single.amount, '110000');
      final payroll = (await service.payrolls(admin)).single;
      expect(payroll.net, '105000');
      await service.approvePayroll(admin, 'salary');
      expect(
        LaborMoney.sum(
          (await repo.productionLaborCosts('f')).map((c) => c.amount),
        ),
        '115000',
      );
      await service.recordPayment(
        admin,
        id: 'pay',
        payrollId: 'salary',
        amount: '40000',
        currency: 'VND',
        day: '2026-10-31',
        note: 'Cash voucher CHI-001',
      );
      await service.recordPayment(
        admin,
        id: 'pay',
        payrollId: 'salary',
        amount: '40000',
        currency: 'VND',
        day: '2026-10-31',
        note: 'Cash voucher CHI-001',
      );
      expect((await service.payrolls(admin)).single.remaining, '65000');
      expect(
        LaborMoney.sum(
          (await repo.productionLaborCosts('f')).map((c) => c.amount),
        ),
        '115000',
      );
      await expectLater(
        service.recordPayment(
          admin,
          id: 'over',
          payrollId: 'salary',
          amount: '65001',
          currency: 'VND',
          day: '2026-10-31',
          note: 'Overpay',
        ),
        throwsStateError,
      );
      await PersonnelIntegrity.validate(db);
    },
  );
  test(
    'payroll locks sources; cancelling draft releases them with audit history',
    () async {
      await service.createRate(admin, rate());
      await approve(entry('a'));
      await service.createPayroll(
        admin,
        const PayrollDraft(
          id: 's1',
          farmId: 'f',
          workerId: 'w',
          period: '2026-10',
          currency: 'VND',
        ),
      );
      await expectLater(
        service.voidEntry(admin, await saved('a'), 'Correction'),
        throwsStateError,
      );
      await service.cancelPayroll(admin, 's1', 'Rebuild');
      await service.createPayroll(
        admin,
        const PayrollDraft(
          id: 's2',
          farmId: 'f',
          workerId: 'w',
          period: '2026-10',
          currency: 'VND',
        ),
      );
      expect(
        (await service.payrolls(admin)).where((p) => p.status == 'draft'),
        hasLength(1),
      );
      await PersonnelIntegrity.validate(db);
    },
  );
  test(
    'voiding approved attendance reverses production projection and keeps history',
    () async {
      await service.createRate(admin, rate());
      await approve(entry('a'));
      final old = await saved('a');
      await service.voidEntry(admin, old, 'Incorrect attendance');
      expect(await repo.productionLaborCosts('f'), isEmpty);
      expect((await saved('a')).status, 'void');
      await expectLater(service.approveEntry(admin, old), throwsStateError);
      await PersonnelIntegrity.validate(db);
    },
  );
  test('attendance user cannot read salaries or approve prices', () async {
    await service.createRate(admin, rate());
    await approve(entry('a'));
    const clerk = AuthorizationSubject(
      userId: 'clerk',
      membershipId: 'c',
      farmId: 'f',
      permissionCodes: {
        PermissionCodes.employeeView,
        PermissionCodes.attendanceRecord,
      },
      dataScopes: {DataScope.allFarm},
    );
    live = clerk;
    expect((await service.entries(clerk)).single.total, isNull);
    expect(() => service.rates(clerk), throwsStateError);
    expect(
      () => service.approveEntry(
        clerk,
        LaborEntryRecord(
          id: 'a',
          workerId: 'w',
          workerName: '',
          businessDay: '2026-10-25',
          startsAt: DateTime.utc(2026, 10, 25),
          endsAt: DateTime.utc(2026, 10, 25),
          breakMinutes: 0,
          regularMinutes: 0,
          overtimeMinutes: 0,
          status: 'draft',
          revision: 0,
        ),
      ),
      throwsStateError,
    );
  });
  test('pending labor blocks plan completion', () async {
    await service.createEntry(admin, entry('a'));
    await expectLater(
      inventory.changeProductionPlanStatus(
        'f',
        'plan',
        1,
        ProductionPlanStatus.completed,
        'admin',
      ),
      throwsStateError,
    );
  });
  test('integrity detects changed salary/cost snapshot', () async {
    await service.createRate(admin, rate());
    await approve(entry('a'));
    await db.update('production_labor_costs_v1', {'amount': '1'});
    await expectLater(PersonnelIntegrity.validate(db), throwsStateError);
  });
  test(
    'time and piece rates coexist for distinct work on the same day',
    () async {
      await service.createRate(
        admin,
        rate(basis: PayBasis.hourly, amount: '10000'),
      );
      await service.createRate(
        admin,
        rate(id: 'piece-same-day', basis: PayBasis.piece, amount: '50000'),
      );
      await approve(entry('time', hours: 2, overtime: 0));
      await approve(
        entry('piece', start: 11, hours: 2, overtime: 0, quantity: '1.5'),
      );
      expect((await saved('time')).total, '20000');
      expect((await saved('piece')).total, '75000');
      await PersonnelIntegrity.validate(db);
    },
  );
  test(
    'VND and LAK payrolls remain independent across effective rate changes',
    () async {
      await service.createRate(admin, rate());
      await approve(entry('vnd', hours: 8, overtime: 0));
      await service.createRate(
        admin,
        rate(id: 'lak', day: '2026-10-26', amount: '40000', currency: 'LAK'),
      );
      await addPlan('lak-plan', currency: 'LAK');
      await approve(
        entry('lak', day: 26, hours: 8, overtime: 0, plan: 'lak-plan'),
      );
      await service.createPayroll(
        admin,
        const PayrollDraft(
          id: 'vnd-salary',
          farmId: 'f',
          workerId: 'w',
          period: '2026-10',
          currency: 'VND',
        ),
      );
      await service.createPayroll(
        admin,
        const PayrollDraft(
          id: 'lak-salary',
          farmId: 'f',
          workerId: 'w',
          period: '2026-10',
          currency: 'LAK',
        ),
      );
      final rows = await service.payrolls(admin);
      expect(rows.firstWhere((p) => p.currency == 'VND').net, '80000');
      expect(rows.firstWhere((p) => p.currency == 'LAK').net, '40000');
      await PersonnelIntegrity.validate(db);
    },
  );
  test(
    'personnel workbook opens with complete sheets and numeric productivity',
    () async {
      await service.createRate(
        admin,
        rate(basis: PayBasis.piece, amount: '50000'),
      );
      await approve(entry('piece', hours: 8, overtime: 0, quantity: '2'));
      final report = PersonnelReport(
        farmId: 'f',
        period: '2026-10',
        employees: await service.employees(admin),
        entries: await service.entries(admin),
        payrolls: [],
        payments: [],
        laborCosts: await repo.productionLaborCosts('f'),
      );
      final workbook = Excel.decodeBytes(report.bytes());
      expect(
        workbook.tables.keys,
        containsAll([
          'DANH SACH NV',
          'CHAM CONG',
          'BANG LUONG',
          'NANG SUAT LD',
          'CHI TRA LUONG',
          'PHAN BO NHAN CONG',
          'TONG HOP',
          'THONG TIN',
        ]),
      );
      expect(workbook['NANG SUAT LD'].rows[1][7]!.value.toString(), '0.25');
      final production = ProductionPlanReport(
        farmId: 'f',
        plans: await inventory.productionPlans('f'),
        tasks: [],
        costs: [],
        laborActualsAvailable: true,
        laborCosts: await repo.productionLaborCosts('f'),
      );
      expect(production.laborActual('plan').toString(), '100000');
      expect(
        Excel.decodeBytes(production.bytes()).tables.keys,
        contains('NHAN CONG SD'),
      );
    },
  );
  test(
    'backup preflight accepts personnel and rejects tampered earnings without changing live data',
    () async {
      await service.createRate(admin, rate());
      await approve(entry('a'));
      final directory = await Directory.systemTemp.createTemp(
        'agrico-personnel-backup-',
      );
      final costs = await databaseFactoryFfi.openDatabase(
        '${directory.path}/costs.db',
      );
      try {
        await costs.execute(
          'CREATE TABLE production_costs(id TEXT PRIMARY KEY)',
        );
        final bytes = await LocalDatabaseSnapshot.create(
          db,
          costsDatabase: costs,
        );
        Future<void> preflight(Uint8List data) async {
          await LocalRestorePreflight.validate(
            bytes: data,
            primary: db,
            costs: costs,
            factory: databaseFactoryFfi,
            temporaryDirectory: directory.path,
          );
        }

        await preflight(bytes);
        final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final payload =
            jsonDecode(envelope['payload']! as String) as Map<String, dynamic>;
        final databases = payload['databases'] as Map<String, dynamic>;
        final tables = (databases['agrico.db'] as Map)['tables'] as Map;
        ((tables['personnel_entries_v1'] as List).single
                as Map)['total_amount'] =
            '1';
        envelope['payload'] = jsonEncode(payload);
        envelope['sha256'] = sha256
            .convert(utf8.encode(jsonEncode(payload)))
            .toString();
        await expectLater(
          preflight(Uint8List.fromList(utf8.encode(jsonEncode(envelope)))),
          throwsA(isA<RestorePreflightException>()),
        );
        expect((await saved('a')).total, '110000');
      } finally {
        await costs.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test('piece prices can differ by shared work type on the same day', () async {
    final catalog = CompanyCatalogService(
      repository: SqliteCompanyCatalog(db),
      subject: admin,
    );
    await catalog.create(
      const CatalogEntry(
        id: 'sowing',
        farmId: 'f',
        kind: CatalogKind.taskType,
        code: '',
        name: 'Sowing',
      ),
      reason: 'Type',
    );
    await catalog.create(
      const CatalogEntry(
        id: 'harvest',
        farmId: 'f',
        kind: CatalogKind.taskType,
        code: '',
        name: 'Harvest',
      ),
      reason: 'Type',
    );
    for (final type in ['sowing', 'harvest']) {
      await service.createRate(
        admin,
        PayRate(
          id: type,
          farmId: 'f',
          workerId: 'w',
          effectiveOn: '2026-10-01',
          basis: PayBasis.piece,
          rate: type == 'sowing' ? '50000' : '70000',
          currency: 'VND',
          rounding: MoneyRounding.halfUp,
          moneyScale: 0,
          pieceUnit: 'ha',
          workTypeId: type,
        ),
      );
    }
    for (final item in [('sowing', 1), ('harvest', 4)]) {
      await approve(
        LaborEntryDraft(
          id: item.$1,
          farmId: 'f',
          workerId: 'w',
          startsAt: DateTime.utc(2026, 10, 25, item.$2),
          endsAt: DateTime.utc(2026, 10, 25, item.$2 + 2),
          breakMinutes: 0,
          overtimeMinutes: 0,
          pieceQuantity: '1',
          workTypeId: item.$1,
          requestedBasis: PayBasis.piece,
          allocations: [],
        ),
      );
    }
    expect((await saved('sowing')).total, '50000');
    expect((await saved('harvest')).total, '70000');
    await PersonnelIntegrity.validate(db);
  });
  test(
    'hourly work can record output without switching to piece wages',
    () async {
      await service.createRate(
        admin,
        rate(basis: PayBasis.hourly, amount: '10000'),
      );
      await approve(
        LaborEntryDraft(
          id: 'output',
          farmId: 'f',
          workerId: 'w',
          startsAt: DateTime.utc(2026, 10, 25, 1),
          endsAt: DateTime.utc(2026, 10, 25, 9),
          breakMinutes: 0,
          overtimeMinutes: 0,
          requestedBasis: PayBasis.hourly,
          outputQuantity: '2',
          outputUnit: 'ha',
          allocations: [],
        ),
      );
      final e = await saved('output');
      expect(e.total, '80000');
      expect(e.productivityQuantity, '2');
      expect(e.pieceAmount, '0');
      await PersonnelIntegrity.validate(db);
    },
  );
  test(
    'same-date rate revisions preserve approved earnings and fix future approvals',
    () async {
      await service.createRate(admin, rate(ot: null));
      await approve(entry('old', hours: 4, overtime: 0));
      await service.createRate(
        admin,
        rate(id: 'revised', amount: '96000', ot: '18000'),
      );
      await approve(entry('new', start: 13, hours: 6, overtime: 120));
      expect((await saved('old')).total, '40000');
      expect((await saved('new')).total, '84000');
      expect((await service.rates(admin)).first.revision, 2);
      await PersonnelIntegrity.validate(db);
    },
  );
  test(
    'rounding is selected explicitly and regular/OT minutes are bounded',
    () {
      expect(
        LaborMoney.fraction('10000', 1, 480, 0, MoneyRounding.halfUp),
        '21',
      );
      expect(LaborMoney.fraction('10000', 1, 480, 0, MoneyRounding.down), '20');
      expect(
        () => entry('bad', hours: 4, overtime: 300).validate(),
        throwsFormatException,
      );
    },
  );
}
