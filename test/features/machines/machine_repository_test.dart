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
import 'package:agrico_deepseek/core/periods/period_lock.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteMachineRepository repo;
  late MachineService service;
  late AuthorizationSubject live;
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
    MoneyRounding rounding = MoneyRounding.halfUp,
  }) => MachineRate(
    id: id,
    machineId: 'm',
    effectiveOn: day,
    amount: amount,
    currency: currency,
    shiftMinutes: minutes,
    scale: scale,
    rounding: rounding,
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
    List<MachineAllocation> segments = const [],
  }) => MachineRun(
    id: id,
    machineId: machine,
    operatorId: worker,
    startsAt: DateTime.utc(2026, 10, day, start - 7),
    endsAt: DateTime.utc(2026, 10, day, start - 7 + hours),
    idleMinutes: idle,
    meterStart: meterStart,
    meterEnd: meterEnd,
    allocations:
        allocations ??
        (segments.isEmpty
            ? [const MachineAllocation('p', 480)]
            : MachineRun.aggregateSegments(segments)),
    segments: segments,
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
    await db.execute(
      'CREATE TABLE land_parcels(id TEXT PRIMARY KEY,farm_id TEXT,parcel_code TEXT)',
    );
    await db.execute('CREATE TABLE production_seasons_v2(id TEXT PRIMARY KEY)');
    await db.execute(
      'CREATE TABLE farm_tasks_v2(id TEXT PRIMARY KEY,farm_id TEXT,worker_resource_id TEXT,machine_resource_id TEXT,status TEXT)',
    );
    await SqliteProductionPlanningRepository.createSchema(db);
    await SqliteCompanyCatalog.createSchema(db);
    await SqliteMachineRepository.createSchema(db);
    await SqlitePersonnelRepository.createSchema(db);
    repo = SqliteMachineRepository(db);
    live = admin;
    service = MachineService(repo, currentSubject: () => live);
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
    await db.insert('land_parcels', {
      'id': 'land',
      'farm_id': 'f',
      'parcel_code': 'LO-001',
    });
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
    'export preserves money beyond spreadsheet numeric precision as text',
    () async {
      await repo.addRate(
        'f',
        rate(amount: '9007199254740993.01', scale: 2),
        'admin',
      );
      await approve(
        run(
          segments: const [
            MachineAllocation('p', 240),
            MachineAllocation('p2', 240),
          ],
        ),
      );
      final book = Excel.decodeBytes(
        MachineReport(
          farm: 'f',
          period: '2026-10',
          machines: await repo.machines('f'),
          runs: await repo.runs('f'),
          expenses: [],
          costs: await repo.productionMachineCosts('f'),
          trace: await repo.machineTrace('f'),
        ).export(),
      );
      expect(
        book['PHAN BO CA MAY ERP'].rows[1][10]!.value,
        TextCellValue('4503599627370496.51'),
      );
      expect(
        book['PHAN BO CA MAY ERP'].rows[2][10]!.value,
        TextCellValue('4503599627370496.5'),
      );
      await MachineIntegrity.validate(db);
    },
  );
  test(
    'trace respects assigned machine scope for plans rates and actor events',
    () async {
      await repo.addRate('f', rate(), 'admin');
      await approve(run());
      await repo.addRate(
        'f',
        const MachineRate(
          id: 'm2-rate',
          machineId: 'm2',
          effectiveOn: '2026-10-01',
          amount: '800000',
          currency: 'VND',
          shiftMinutes: 480,
          scale: 0,
          rounding: MoneyRounding.halfUp,
        ),
        'admin',
      );
      await approve(
        run(
          id: 'private-run',
          machine: 'm2',
          day: 21,
          allocations: const [MachineAllocation('p2', 480)],
        ),
      );
      final limited = AuthorizationSubject(
        userId: 'u',
        membershipId: 'u',
        farmId: 'f',
        permissionCodes: PermissionCodes.values,
        dataScopes: const {DataScope.assignedMachines},
        assignedMachineIds: const {'m'},
      );
      live = limited;
      final trace = await service.trace(limited);
      expect(trace.plans.keys, {'p'});
      expect(trace.rates.map((r) => r.machineId).toSet(), {'m'});
      expect(trace.audit.map((r) => r['entity_id']).toSet(), {'run'});
      expect(trace.parcelCodes.values, {'LO-001'});
    },
  );
  for (final rounding in MoneyRounding.values) {
    test(
      'decimal rate keeps $rounding policy before grouping returning minute visits',
      () async {
        await repo.addRate(
          'f',
          rate(amount: '1.005', scale: 2, rounding: rounding),
          'admin',
        );
        await approve(
          run(
            segments: const [
              MachineAllocation('p', 120),
              MachineAllocation('p2', 240),
              MachineAllocation('p', 120),
            ],
          ),
        );
        final costs = await repo.productionMachineCosts('f');
        expect(
          (await repo.runs('f')).single.amount,
          rounding == MoneyRounding.halfUp ? '1.01' : '1',
        );
        expect(
          costs.map((c) => c.amount),
          rounding == MoneyRounding.halfUp ? ['0.51', '0.5'] : ['0.5', '0.5'],
        );
        await MachineIntegrity.validate(db);
      },
    );
  }
  test(
    'mixed VND LAK reports never combine currency and preserve old approved rate',
    () async {
      await repo.addRate('f', rate(), 'admin');
      await approve(
        run(
          segments: const [
            MachineAllocation('p', 240),
            MachineAllocation('p2', 240),
          ],
        ),
      );
      await repo.addRate('f', rate(id: 'lak-rate', currency: 'LAK'), 'admin');
      await approve(
        run(
          id: 'lak-run',
          day: 21,
          meterStart: '108',
          meterEnd: '116',
          segments: const [
            MachineAllocation('lak', 120),
            MachineAllocation('lak', 360),
          ],
        ),
      );
      final records = await repo.runs('f');
      expect(records.firstWhere((r) => r.value.id == 'run').rateId, 'rate');
      final book = MachineReport(
        farm: 'f',
        period: '2026-10',
        machines: await repo.machines('f'),
        runs: records,
        expenses: [],
        costs: await repo.productionMachineCosts('f'),
      ).workbook();
      expect(book['TONG HOP'].rows[1][0]!.value.toString(), 'VND');
      expect(book['TONG HOP'].rows[2][0]!.value.toString(), 'LAK');
      expect(book['TONG HOP'].rows[1][2]!.value.toString(), '800000');
      expect(book['TONG HOP'].rows[2][2]!.value.toString(), '800000');
      await MachineIntegrity.validate(db);
    },
  );
  test('trace requires financial permission and live membership', () async {
    final clerk = AuthorizationSubject(
      userId: 'clerk',
      membershipId: 'm',
      farmId: 'f',
      permissionCodes: const {PermissionCodes.machineView},
      dataScopes: const {DataScope.allFarm},
    );
    live = clerk;
    expect(() => service.trace(clerk), throwsStateError);
    expect(() => service.trace(admin), throwsStateError);
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
    'two minute visits split the 480 minute cost without components',
    () async {
      await repo.addRate('f', rate(), 'admin');
      await approve(
        run(
          segments: const [
            MachineAllocation('p', 240),
            MachineAllocation('p2', 240),
          ],
        ),
      );
      final costs = await repo.productionMachineCosts('f');
      expect(costs.map((c) => c.amount), ['400000', '400000']);
      expect(hr.LaborMoney.sum(costs.map((c) => c.amount)), '800000');
      await MachineIntegrity.validate(db);
    },
  );
  test(
    'three plans preserve parcel codes, rate snapshot and entry approval trace',
    () async {
      final p = Map<String, Object?>.from(
        (await db.query(
          'production_plans_v1',
          where: 'id=?',
          whereArgs: ['p'],
        )).single,
      );
      await db.insert('land_parcels', {
        'id': 'other',
        'farm_id': 'f',
        'parcel_code': 'LO-002',
      });
      await db.insert('production_plans_v1', {
        ...p,
        'id': 'p3',
        'code': 'PLAN-3',
        'parcel_id': 'other',
      });
      await repo.addRate('f', rate(), 'admin');
      await approve(
        run(
          segments: const [
            MachineAllocation('p', 120),
            MachineAllocation('p2', 120),
            MachineAllocation('p3', 240),
          ],
        ),
      );
      final trace = await service.trace(admin);
      final book = MachineReport(
        farm: 'f',
        period: '2026-10',
        machines: await repo.machines('f'),
        runs: await repo.runs('f'),
        expenses: [],
        costs: await repo.productionMachineCosts('f'),
        trace: trace,
      ).workbook();
      final rows = book['PHAN BO CA MAY ERP'].rows;
      expect(rows.length, 4);
      expect(rows[3][6]!.value.toString(), 'PLAN-3');
      expect(rows[3][8]!.value.toString(), 'LO-002');
      expect(rows[3][10]!.value.toString(), '400000');
      expect(rows[3][12]!.value.toString(), 'rate');
      expect(rows[3][13]!.value.toString(), '1');
      expect(rows[3][20]!.value.toString(), 'admin');
      expect(rows[3][22]!.value.toString(), 'admin');
      expect(rows[3][23]!.value.toString(), isNotEmpty);
      expect(book['LUOT CHUYEN MAY ERP'].rows.length, 4);
      await MachineIntegrity.validate(db);
    },
  );
  test(
    'many visits returning to a plan retain order but only one cost per plan',
    () async {
      final segments = List.generate(
        12,
        (i) => MachineAllocation(i.isEven ? 'p' : 'p2', 40),
      );
      final r = run(segments: segments);
      await repo.addRate('f', rate(), 'admin');
      await repo.addRun('f', r, 'admin');
      await repo.addRun('f', r, 'admin');
      await repo.approveRun('f', r.id, 0, 'admin');
      await expectLater(
        repo.approveRun('f', r.id, 0, 'admin'),
        throwsStateError,
      );
      final saved = (await repo.runs('f')).single;
      expect(
        saved.value.segments.map((v) => v.planId),
        segments.map((v) => v.planId),
      );
      expect(saved.value.allocations.map((v) => v.minutes), [240, 240]);
      expect((await repo.productionMachineCosts('f')).length, 2);
      final json = saved.value.toJson();
      expect(MachineRun.fromJson(json).toJson(), json);
      await MachineIntegrity.validate(db);
      final book = Excel.decodeBytes(
        MachineReport(
          farm: 'f',
          period: '2026-10',
          machines: await repo.machines('f'),
          runs: [saved],
          expenses: [],
          costs: await repo.productionMachineCosts('f'),
          trace: await repo.machineTrace('f'),
        ).export(),
      );
      expect(book['LUOT CHUYEN MAY ERP'].rows.length, 13);
      expect(book['PHAN BO CA MAY ERP'].rows.length, 3);
      expect(book['LUOT CHUYEN MAY ERP'].rows[3][2]!.value.toString(), 'p');
    },
  );
  test(
    'visits cannot exceed run minutes, omit plan, or diverge from aggregate',
    () async {
      for (final segments in [
        const [MachineAllocation('p', 481)],
        const [MachineAllocation('', 10)],
        const [MachineAllocation('p', 0)],
      ]) {
        await expectLater(
          repo.addRun('f', run(segments: segments), 'admin'),
          throwsFormatException,
        );
      }
      await expectLater(
        repo.addRun(
          'f',
          run(
            allocations: const [MachineAllocation('p', 480)],
            segments: const [MachineAllocation('p', 240)],
          ),
          'admin',
        ),
        throwsFormatException,
      );
      expect(await db.query('machine_runs_v1'), isEmpty);
    },
  );
  test('visit precision is integer minutes with a bounded technical limit', () {
    expect(
      () => run(
        segments: List.generate(1441, (_) => const MachineAllocation('p', 1)),
      ).validate(),
      throwsFormatException,
    );
    final historical = run();
    expect(historical.toJson().containsKey('segments'), isFalse);
    expect(
      MachineRun.fromJson(historical.toJson()).toJson(),
      historical.toJson(),
    );
  });
  test(
    'partial visits retain remainder and preserve historical rounding tie order',
    () async {
      await repo.addRate('f', rate(amount: '1', minutes: 3), 'admin');
      await approve(
        run(
          hours: 1,
          idle: 57,
          segments: const [
            MachineAllocation('p', 1),
            MachineAllocation('p2', 1),
          ],
        ),
      );
      expect((await repo.productionMachineCosts('f')).map((c) => c.amount), [
        '1',
        '0',
      ]);
      final book = MachineReport(
        farm: 'f',
        period: '2026-10',
        machines: await repo.machines('f'),
        runs: await repo.runs('f'),
        expenses: [],
        costs: await repo.productionMachineCosts('f'),
      ).workbook();
      expect(book['PHAN BO CA MAY ERP'].rows[1][24]!.value.toString(), '1');
      expect(book['PHAN BO CA MAY ERP'].rows[1][25]!.value.toString(), '0');
    },
  );
  test(
    'approved visit body is immutable; correction is void plus a new source',
    () async {
      await repo.addRate('f', rate(), 'admin');
      final r = run(
        segments: const [
          MachineAllocation('p', 120),
          MachineAllocation('p2', 240),
          MachineAllocation('p', 120),
        ],
      );
      await approve(r);
      await expectLater(
        repo.addRun(
          'f',
          run(segments: const [MachineAllocation('p', 480)]),
          'admin',
        ),
        throwsStateError,
      );
      await repo.voidRun('f', r.id, 1, 'Correct minutes', 'admin');
      await approve(
        run(
          id: 'replacement',
          segments: const [
            MachineAllocation('p', 240),
            MachineAllocation('p2', 240),
          ],
        ),
      );
      expect(
        (await repo.productionMachineCosts('f')).map((c) => c.sourceId).toSet(),
        {'replacement'},
      );
      expect(
        (await repo.runs(
          'f',
        )).firstWhere((r) => r.value.id == 'run').value.segments.length,
        3,
      );
      expect(
        (await repo.machineTrace(
          'f',
        )).audit.where((a) => a['reason'] == 'Correct minutes').length,
        1,
      );
      await MachineIntegrity.validate(db);
    },
  );
  test(
    'late offline run and allocation changes fail at SQLite after local period lock',
    () async {
      await repo.addRate('f', rate(), 'admin');
      final r = run(
        segments: const [
          MachineAllocation('p', 240),
          MachineAllocation('p2', 240),
        ],
      );
      await approve(r);
      await PeriodLock.createSchema(db);
      await db.insert(PeriodLock.states, {
        'farm_id': 'f',
        'period': '2026-10',
        'revision': 1,
        'status': 'closed',
        'event_id': 'test-lock',
      });
      await expectLater(
        repo.addRun(
          'f',
          run(
            id: 'late',
            day: 21,
            meterStart: '108',
            meterEnd: '116',
            segments: const [MachineAllocation('p', 480)],
          ),
          'admin',
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        repo.voidRun('f', r.id, 1, 'Late correction', 'admin'),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.update(
          'machine_costs_v1',
          {'minutes': 1},
          where: 'source_id=?',
          whereArgs: [r.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repo.productionMachineCosts('f')).map((c) => c.amount), [
        '400000',
        '400000',
      ]);
      expect((await repo.runs('f')).length, 1);
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
      expect(excel.tables.length, 11);
      expect(
        excel.tables.keys,
        containsAll(['PHAN BO CA MAY ERP', 'LUOT CHUYEN MAY ERP']),
      );
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
    live = clerk;
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
    live = narrow;
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
