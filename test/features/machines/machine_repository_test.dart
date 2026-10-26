import 'package:agrico_deepseek/features/personnel/data/sqlite_personnel_repository.dart';
import 'package:agrico_deepseek/features/personnel/data/personnel_integrity.dart';
import 'package:agrico_deepseek/features/personnel/domain/personnel.dart' as hr;
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/machines/application/machine_service.dart';
import 'package:agrico_deepseek/features/machines/application/machine_report.dart';
import 'package:agrico_deepseek/features/machines/data/sqlite_machine_repository.dart';
import 'package:agrico_deepseek/features/machines/data/machine_integrity.dart';
import 'package:agrico_deepseek/features/inventory/application/production_plan_report.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/production_plan.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_production_planning_repository.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteMachineRepository repo;
  late MachineService service;
  final admin = AuthorizationSubject(
    userId: 'admin',
    membershipId: 'm',
    farmId: 'f',
    permissionCodes: PermissionCodes.values,
    dataScopes: const {DataScope.allFarm},
  );
  MachineRate rate({
    String id = 'rate',
    String day = '2026-10-01',
    String amount = '800000',
    String currency = 'VND',
    int minutes = 480,
    int scale = 0,
  }) => MachineRate(
    id: id,
    machineId: 'm',
    effectiveOn: day,
    amount: amount,
    currency: currency,
    shiftMinutes: minutes,
    scale: scale,
    rounding: MoneyRounding.halfUp,
  );
  MachineRun run({
    String id = 'run',
    String machine = 'm',
    String worker = 'w',
    int day = 20,
    int start = 8,
    int hours = 9,
    int idle = 60,
    String meterStart = '100',
    String meterEnd = '108',
    List<MachineAllocation>? allocations,
  }) => MachineRun(
    id: id,
    machineId: machine,
    operatorId: worker,
    startsAt: DateTime.utc(2026, 10, day, start - 7),
    endsAt: DateTime.utc(2026, 10, day, start - 7 + hours),
    idleMinutes: idle,
    meterStart: meterStart,
    meterEnd: meterEnd,
    allocations: allocations ?? [const MachineAllocation('p', 480)],
    outputQuantity: '4',
    outputUnit: 'ha',
  );
  MachineExpense expense({
    String id = 'fuel',
    String kind = 'fuel',
    String ref = 'PX001',
    String amount = '500000',
    String currency = 'VND',
    String day = '2026-10-20',
    String? nextOn,
    String? nextMeter,
  }) => MachineExpense(
    id: id,
    machineId: 'm',
    kind: kind,
    day: day,
    amount: amount,
    currency: currency,
    reference: ref,
    note: 'External source document',
    litres: kind == 'fuel' ? '25' : null,
    meter: '108',
    nextOn: nextOn,
    nextMeter: nextMeter,
  );
  Future<void> approve(MachineRun r) async {
    await repo.addRun('f', r, 'admin');
    await repo.approveRun('f', r.id, 0, 'admin');
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys=ON');
    await db.execute(
      'CREATE TABLE parcel_work_resources(id TEXT PRIMARY KEY,farm_id TEXT,kind TEXT,code TEXT,name TEXT,active INTEGER)',
    );
    await db.execute('CREATE TABLE land_parcels(id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE production_seasons_v2(id TEXT PRIMARY KEY)');
    await db.execute(
      'CREATE TABLE farm_tasks_v2(id TEXT PRIMARY KEY,farm_id TEXT,worker_resource_id TEXT,machine_resource_id TEXT,status TEXT)',
    );
    await SqliteProductionPlanningRepository.createSchema(db);
    await SqliteCompanyCatalog.createSchema(db);
    await SqliteMachineRepository.createSchema(db);
    await SqlitePersonnelRepository.createSchema(db);
    repo = SqliteMachineRepository(db);
    service = MachineService(repo);
    for (final (id, kind, farm) in [
      ('m', 'machine', 'f'),
      ('m2', 'machine', 'f'),
      ('w', 'worker', 'f'),
      ('w2', 'worker', 'f'),
      ('foreign', 'machine', 'g'),
    ]) {
      await db.insert('company_catalog_entries_v1', {
        'id': id,
        'farm_id': farm,
        'kind': kind,
        'code': id,
        'name': id,
        'name_key': id,
        'active': 1,
        'revision': 1,
      });
      await db.insert('parcel_work_resources', {
        'id': id,
        'farm_id': farm,
        'kind': kind,
        'code': id,
        'name': id,
        'active': 1,
      });
    }
    await db.insert('land_parcels', {'id': 'land'});
    await db.insert('production_seasons_v2', {'id': 'season'});
    for (final (id, currency) in [
      ('p', 'VND'),
      ('p2', 'VND'),
      ('lak', 'LAK'),
    ]) {
      await db.insert('production_plans_v1', {
        'id': id,
        'farm_id': 'f',
        'parcel_id': 'land',
        'season_id': 'season',
        'code': id,
        'name': id,
        'crop': 'peanut',
        'starts_on': '2026-10-01',
        'ends_on': '2026-10-31',
        'currency': currency,
        'material_budget': '0',
        'labor_budget': '0',
        'machine_budget': '1000000',
        'labor_hours': '0',
        'machine_shifts': '1',
        'status': 'active',
        'revision': 0,
      });
    }
    await repo.profile('f', 'm', 0, {
      'meterUnit': 'hour',
      'model': 'Tractor',
    }, 'admin');
    await repo.profile('f', 'm2', 0, {'meterUnit': 'hour'}, 'admin');
  });
  tearDown(() async {
    await db.close();
  });
  test(
    'shared identity profile preserves code, revision and no duplicate catalog',
    () async {
      final before = await db.query('company_catalog_entries_v1');
      final m = (await service.machines(admin)).first;
      expect(m.id, 'm');
      expect(m.revision, 1);
      await expectLater(
        repo.profile('f', 'm', 0, {'meterUnit': 'hour'}, 'admin'),
        throwsStateError,
      );
      expect(await db.query('company_catalog_entries_v1'), before);
      await expectLater(
        repo.profile('f', 'foreign', 0, {'meterUnit': 'hour'}, 'admin'),
        throwsStateError,
      );
    },
  );
  test(
    '480 operating minutes use one all-inclusive shift, no fuel double count',
    () async {
      await repo.addRate('f', rate(), 'admin');
      await approve(run());
      await repo.addExpense('f', expense(), 'admin');
      await repo.approveExpense('f', 'fuel', 0, 'admin');
      expect((await repo.runs('f')).single.amount, '800000');
      expect((await repo.productionMachineCosts('f')).single.amount, '800000');
      await MachineIntegrity.validate(db);
    },
  );
  test(
    'fractional shift uses explicitly chosen rounding and conservative allocation',
    () async {
      await repo.addRate('f', rate(amount: '1', minutes: 3), 'admin');
      await approve(
        run(
          hours: 1,
          idle: 57,
          allocations: [
            const MachineAllocation('p', 1),
            const MachineAllocation('p2', 1),
          ],
        ),
      );
      final costs = await repo.productionMachineCosts('f');
      expect(costs.map((c) => c.amount).toList(), ['1', '0']);
      expect((await repo.runs('f')).single.amount, '1');
    },
  );
  test(
    'unallocated remainder remains in source and separate report total',
    () async {
      await repo.addRate('f', rate(), 'admin');
      await approve(run(allocations: [const MachineAllocation('p', 240)]));
      expect((await repo.productionMachineCosts('f')).single.amount, '400000');
      final report = MachineReport(
        farm: 'f',
        period: '2026-10',
        machines: await repo.machines('f'),
        runs: await repo.runs('f'),
        expenses: [],
        costs: await repo.productionMachineCosts('f'),
      );
      final excel = Excel.decodeBytes(report.export());
      expect(excel.tables.length, 9);
      expect(excel['TONG HOP'].rows[1][3]!.value.toString(), '400000');
    },
  );
  test(
    'immutable effective rate revisions do not reprice approved history',
    () async {
      await repo.addRate('f', rate(), 'admin');
      await approve(run());
      await repo.addRate('f', rate(id: 'rate2', amount: '900000'), 'admin');
      await approve(
        run(id: 'run2', day: 21, meterStart: '108', meterEnd: '116'),
      );
      expect((await repo.runs('f')).map((r) => r.amount).toList(), [
        '900000',
        '800000',
      ]);
      await MachineIntegrity.validate(db);
    },
  );
  test('future rate is not effective', () async {
    await repo.addRate('f', rate(day: '2026-10-21'), 'admin');
    await repo.addRun('f', run(), 'admin');
    await expectLater(
      repo.approveRun('f', 'run', 0, 'admin'),
      throwsStateError,
    );
    expect((await repo.runs('f')).single.status, 'draft');
    expect(await repo.productionMachineCosts('f'), isEmpty);
  });
  test(
    'machine and operator overlap are rejected, adjacent shifts allowed',
    () async {
      await repo.addRun('f', run(), 'admin');
      await expectLater(
        repo.addRun('f', run(id: 'x', worker: 'w2'), 'admin'),
        throwsStateError,
      );
      await expectLater(
        repo.addRun('f', run(id: 'y', machine: 'm2'), 'admin'),
        throwsStateError,
      );
      await repo.addRun(
        'f',
        run(
          id: 'z',
          start: 17,
          hours: 1,
          idle: 0,
          meterStart: '108',
          meterEnd: '109',
          allocations: [],
        ),
        'admin',
      );
    },
  );
  test(
    'meter cannot regress including backdated insert and locked unit',
    () async {
      await repo.addRun('f', run(), 'admin');
      await expectLater(
        repo.addRun(
          'f',
          run(id: 'x', day: 21, meterStart: '107', meterEnd: '115'),
          'admin',
        ),
        throwsStateError,
      );
      await expectLater(
        repo.addRun(
          'f',
          run(id: 'y', day: 19, meterStart: '99', meterEnd: '101'),
          'admin',
        ),
        throwsStateError,
      );
      await expectLater(
        repo.profile('f', 'm', 1, {'meterUnit': 'km'}, 'admin'),
        throwsStateError,
      );
    },
  );
  test('inactive machine and wrong farm resources are rejected', () async {
    await expectLater(repo.addRun('g', run(), 'admin'), throwsStateError);
    await db.update('company_catalog_entries_v1', {
      'active': 0,
    }, where: "id='m'");
    await expectLater(repo.addRun('f', run(), 'admin'), throwsStateError);
  });
  test('wrong currency approval is atomic across allocation rows', () async {
    await repo.addRate('f', rate(), 'admin');
    await repo.addRun(
      'f',
      run(
        allocations: [
          const MachineAllocation('p', 240),
          const MachineAllocation('lak', 240),
        ],
      ),
      'admin',
    );
    await expectLater(
      repo.approveRun('f', 'run', 0, 'admin'),
      throwsStateError,
    );
    expect((await repo.runs('f')).single.status, 'draft');
    expect(
      (await db.query('machine_costs_v1')).every((r) => r['amount'] == null),
      isTrue,
    );
  });
  test('closed or out of date plans reject drafts', () async {
    await db.update('production_plans_v1', {
      'status': 'completed',
    }, where: "id='p'");
    await expectLater(repo.addRun('f', run(), 'admin'), throwsStateError);
    await expectLater(
      repo.addRun('f', run(id: 'x', day: 1, start: 0), 'admin'),
      throwsStateError,
    );
  });
  test('request replay idempotent, changed payload same ID rejected', () async {
    await repo.addRate('f', rate(), 'admin');
    await repo.addRate('f', rate(), 'admin');
    await repo.addRun('f', run(), 'admin');
    await repo.addRun('f', run(), 'admin');
    await expectLater(
      repo.addRun('f', run(meterEnd: '109'), 'admin'),
      throwsStateError,
    );
    expect((await repo.rates('f')).length, 1);
    expect((await repo.runs('f')).length, 1);
    await repo.addExpense('f', expense(), 'admin');
    await repo.addExpense('f', expense(), 'admin');
    await expectLater(
      repo.addExpense('f', expense(amount: '1'), 'admin'),
      throwsStateError,
    );
  });
  test('duplicate source reference and negative litres rejected', () async {
    await repo.addExpense('f', expense(), 'admin');
    await expectLater(
      repo.addExpense('f', expense(id: 'x'), 'admin'),
      throwsA(anything),
    );
    final e = expense().toJson()
      ..['litres'] = '-1'
      ..['id'] = 'bad';
    await expectLater(
      repo.addExpense('f', MachineExpense.fromJson(e), 'admin'),
      throwsFormatException,
    );
  });
  test('maintenance schedule validates next date and meter', () async {
    await expectLater(
      repo.addExpense(
        'f',
        expense(kind: 'maintenance', nextOn: '2026-10-19'),
        'admin',
      ),
      throwsFormatException,
    );
    await expectLater(
      repo.addExpense(
        'f',
        expense(kind: 'maintenance', nextMeter: '100'),
        'admin',
      ),
      throwsFormatException,
    );
    await repo.addExpense(
      'f',
      expense(kind: 'maintenance', nextOn: '2026-11-20', nextMeter: '200'),
      'admin',
    );
    await repo.approveExpense('f', 'fuel', 0, 'admin');
    await MachineIntegrity.validate(db);
    expect((await repo.expenses('f')).single.status, 'approved');
  });
  test('void keeps audit and history, removes projected cost', () async {
    await repo.addRate('f', rate(), 'admin');
    await approve(run());
    await expectLater(
      repo.voidRun('f', 'run', 0, 'Correction', 'admin'),
      throwsStateError,
    );
    await expectLater(
      repo.voidRun('f', 'run', 1, '', 'admin'),
      throwsFormatException,
    );
    await repo.voidRun('f', 'run', 1, 'Correction', 'admin');
    expect((await repo.runs('f')).single.status, 'void');
    expect(await repo.productionMachineCosts('f'), isEmpty);
    expect(
      (await db.query(
        'machine_audit_v1',
        where: "action LIKE '%void'",
      )).single['reason'],
      'Correction',
    );
  });
  test('cannot void cost belonging to closed plan', () async {
    await repo.addRate('f', rate(), 'admin');
    await approve(run());
    await db.update('production_plans_v1', {
      'status': 'completed',
    }, where: "id='p'");
    await expectLater(
      repo.voidRun('f', 'run', 1, 'Correction', 'admin'),
      throwsStateError,
    );
  });
  test('failed audit rolls back source and allocation', () async {
    await expectLater(repo.addRun('f', run(), ''), throwsFormatException);
    expect(await repo.runs('f'), isEmpty);
    expect(await db.query('machine_costs_v1'), isEmpty);
  });
  test('clerk cannot fetch financial rates expenses or approve', () async {
    final clerk = AuthorizationSubject(
      userId: 'clerk',
      membershipId: 'c',
      farmId: 'f',
      permissionCodes: const {
        PermissionCodes.machineView,
        PermissionCodes.machineLog,
      },
      dataScopes: const {DataScope.allFarm},
    );
    await repo.addRate('f', rate(), 'admin');
    await approve(run());
    expect((await service.runs(clerk)).single.amount, isNull);
    expect(() => service.rates(clerk), throwsStateError);
    expect(() => service.expenses(clerk), throwsStateError);
    expect(
      () => service.approveRun(clerk, (MachineRecord(run(), 'draft', 0))),
      throwsStateError,
    );
  });
  test('farm-limited role is not broadened to allFarm', () async {
    final narrow = AuthorizationSubject(
      userId: 'u',
      membershipId: 'u',
      farmId: 'f',
      permissionCodes: PermissionCodes.values,
      dataScopes: const {DataScope.assignedMachines},
    );
    expect(() => service.machines(narrow), throwsStateError);
  });
  test('LAK independent totals and machine plan report actuals', () async {
    await repo.addRate('f', rate(currency: 'LAK'), 'admin');
    await approve(run(allocations: [const MachineAllocation('lak', 480)]));
    final costs = await repo.productionMachineCosts('f');
    expect(costs.single.currency, 'LAK');
    final report = ProductionPlanReport(
      farmId: 'f',
      plans: [
        ProductionPlan(
          id: 'lak',
          farmId: 'f',
          parcelId: 'land',
          seasonId: 'season',
          name: 'Plan',
          crop: 'peanut',
          startsOn: '2026-10-01',
          endsOn: '2026-10-31',
          currency: 'LAK',
          materialBudget: '0',
          laborBudget: '0',
          machineBudget: '1000000',
          laborHours: '0',
          machineShifts: '1',
        ),
      ],
      tasks: [],
      costs: [],
      machineCosts: costs,
      machineActualsAvailable: true,
    );
    expect(report.machineActual('lak').toString(), '800000');
  });
  test(
    'backup rejects tampered source amount and missing allocation',
    () async {
      await repo.addRate('f', rate(), 'admin');
      await approve(run());
      await MachineIntegrity.validate(db);
      await db.update('machine_runs_v1', {'amount': '1'}, where: "id='run'");
      await expectLater(MachineIntegrity.validate(db), throwsStateError);
      await db.update('machine_runs_v1', {
        'amount': '800000',
      }, where: "id='run'");
      await db.delete('machine_costs_v1');
      await expectLater(MachineIntegrity.validate(db), throwsStateError);
    },
  );
  test('backup rejects body and indexed identity mismatch', () async {
    await repo.addRun('f', run(), 'admin');
    final r = (await db.query('machine_runs_v1')).single;
    final b = SqliteMachineRepository.body(r)
      ..['day'] = 'ignored'
      ..['machineId'] = 'm2';
    await db.update('machine_runs_v1', {'body': jsonEncode(b)});
    await expectLater(MachineIntegrity.validate(db), throwsStateError);
  });
  Future<void> attendance({String? machine}) async {
    final personnel = SqlitePersonnelRepository(db);
    await personnel.createRate(
      hr.PayRate(
        id: 'wage',
        farmId: 'f',
        workerId: 'w',
        effectiveOn: '2026-10-01',
        basis: hr.PayBasis.daily,
        rate: '80000',
        currency: 'VND',
        moneyScale: 0,
        rounding: hr.MoneyRounding.halfUp,
      ),
      'admin',
    );
    await personnel.createEntry(
      hr.LaborEntryDraft(
        id: 'attendance',
        farmId: 'f',
        workerId: 'w',
        startsAt: DateTime.utc(2026, 10, 20, 1),
        endsAt: DateTime.utc(2026, 10, 20, 10),
        breakMinutes: 60,
        overtimeMinutes: 0,
        machineId: machine,
        allocations: const [],
      ),
      'admin',
    );
  }

  test(
    'machine approval blocks driver wages already counted separately',
    () async {
      await repo.addRate('f', rate(), 'admin');
      await attendance();
      await SqlitePersonnelRepository(
        db,
      ).approveEntry('f', 'attendance', 0, 'admin');
      await repo.addRun('f', run(), 'admin');
      await expectLater(
        repo.approveRun('f', 'run', 0, 'admin'),
        throwsStateError,
      );
      expect(await repo.productionMachineCosts('f'), isEmpty);
    },
  );
  test(
    'attendance approval blocks double count after machine shift approved',
    () async {
      await repo.addRate('f', rate(), 'admin');
      await approve(run());
      await attendance();
      await expectLater(
        SqlitePersonnelRepository(
          db,
        ).approveEntry('f', 'attendance', 0, 'admin'),
        throwsStateError,
      );
    },
  );
  test(
    'driver wages remain payable when marked included in machine rate',
    () async {
      await repo.addRate('f', rate(), 'admin');
      await attendance(machine: 'm');
      await SqlitePersonnelRepository(
        db,
      ).approveEntry('f', 'attendance', 0, 'admin');
      await approve(run());
      expect(
        (await SqlitePersonnelRepository(
          db,
        ).entries('f', money: true)).single.total,
        '80000',
      );
      expect(
        await SqlitePersonnelRepository(db).productionLaborCosts('f'),
        isEmpty,
      );
      expect((await repo.productionMachineCosts('f')).single.amount, '800000');
      await MachineIntegrity.validate(db);
    },
  );
  test('personnel backup accepts populated employee profiles', () async {
    final personnel = SqlitePersonnelRepository(db);
    await personnel.saveProfile(
      hr.EmployeeProfile(
        workerId: 'w',
        farmId: 'f',
        details: const {'phone': '123'},
        revision: 0,
      ),
      'admin',
    );
    await PersonnelIntegrity.validate(db);
  });
  test('pending machine allocations prevent closing plan', () async {
    await repo.addRun('f', run(), 'admin');
    await expectLater(
      SqliteProductionPlanningRepository(db).changeProductionPlanStatus(
        'f',
        'p',
        0,
        ProductionPlanStatus.completed,
        'admin',
      ),
      throwsStateError,
    );
    await repo.voidRun('f', 'run', 0, 'Cancelled', 'admin');
    await SqliteProductionPlanningRepository(db).changeProductionPlanStatus(
      'f',
      'p',
      0,
      ProductionPlanStatus.completed,
      'admin',
    );
  });
  test(
    'task allocation rejects a machine assigned to another resource',
    () async {
      await db.insert('farm_tasks_v2', {
        'id': 'task',
        'farm_id': 'f',
        'worker_resource_id': 'w',
        'machine_resource_id': 'm2',
        'status': 'pending',
      });
      await db.insert('production_plan_tasks_v1', {
        'id': 'task',
        'farm_id': 'f',
        'plan_id': 'p',
        'stage': 'work',
        'quantity': '1',
        'unit': 'ha',
        'revision': 0,
      });
      await expectLater(
        repo.addRun(
          'f',
          run(allocations: [const MachineAllocation('p', 480, taskId: 'task')]),
          'admin',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'service report reaches meter threshold without adding component money',
    () async {
      await repo.addRate('f', rate(), 'admin');
      await approve(run());
      await repo.addExpense(
        'f',
        expense(kind: 'maintenance', nextMeter: '110'),
        'admin',
      );
      await repo.approveExpense('f', 'fuel', 0, 'admin');
      await approve(
        run(id: 'run2', day: 21, meterStart: '108', meterEnd: '116'),
      );
      final report = MachineReport(
        farm: 'f',
        period: '2026-10',
        machines: await repo.machines('f'),
        runs: await repo.runs('f'),
        expenses: await repo.expenses('f'),
        costs: await repo.productionMachineCosts('f'),
      ).workbook();
      expect(report['LICH BAO DUONG'].rows[1][5]!.value.toString(), 'Due');
      expect(report['TONG HOP'].rows[1][2]!.value.toString(), '1600000');
    },
  );
}
