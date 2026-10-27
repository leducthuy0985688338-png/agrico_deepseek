import 'package:agrico_deepseek/features/trade/domain/trade.dart'
    show TradeDraft, TradeKind, TradeLine;
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_restore_preflight.dart';
import 'package:agrico_deepseek/core/backup/local_restore_activation_io.dart';
import 'package:agrico_deepseek/features/integration/application/report20.dart';
import 'package:agrico_deepseek/core/periods/period_lock.dart';
import 'package:agrico_deepseek/features/integration/data/period_close_repository.dart';
import 'package:agrico_deepseek/features/integration/application/period_close_service.dart';
import 'package:agrico_deepseek/features/integration/application/integration_service.dart';
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
import 'package:agrico_deepseek/features/machines/data/sqlite_machine_repository.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:agrico_deepseek/features/trade/data/sqlite_trade_repository.dart';
import 'package:agrico_deepseek/features/integration/data/integration_repository.dart';

void main() {
  late AuthorizationSubject live;
  sqfliteFfiInit();
  late Database db;
  late Directory directory;
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
    String day = '2026-09-01',
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
    final begins = DateTime.utc(2026, 9, day, start - 7);
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
        startsOn: '2026-09-01',
        endsOn: '2026-09-30',
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
    directory = await Directory.systemTemp.createTemp('agrico-period-');
    db = await databaseFactoryFfi.openDatabase('${directory.path}/agrico.db');
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
        startsOn: '2026-09-01',
      ),
    );
    await addPlan('plan');
    repo = SqlitePersonnelRepository(db);
    service = PersonnelService(repo, currentSubject: () => live);
  });
  tearDown(() async {
    if (db.isOpen) {
      await db.close();
    }
    await directory.delete(recursive: true);
  });

  Future<void> salaryReady() async {
    await service.createRate(admin, rate(amount: '1', ot: '1', scale: 2));
    await approve(entry('a', hours: 8, overtime: 0));
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
  }

  IntegrationRepository bridge() => IntegrationRepository(db);
  PeriodCloseRepository closing({String day = '2026-10-01'}) =>
      PeriodCloseRepository(db, today: () => day);
  Future<void> closeSeptember() async {
    final c = closing();
    final r = await c.review('f', '2026-09');
    expect(r.issues, isEmpty);
    await c.close(
      'f',
      '2026-09',
      r.token,
      r.revision,
      'Monthly approval',
      'admin',
      () {},
    );
  }

  Future<void> cash(String id, String day, {String farm = 'f'}) =>
      db.insert('finance_documents_v2', {
        'id': id,
        'organization_id': farm,
        'code': id,
        'kind': 'THU',
        'occurred_at': day,
        'amount_minor': 1,
        'currency': 'LAK',
        'category': 'Test',
      });
  test(
    'closing freezes report sources; later cash and renamed catalogs cannot restate it',
    () async {
      await cash('receipt', '2026-09-25');
      final before = await bridge().snapshot('f', '2026-09');
      await closeSeptember();
      await cash('next', '2026-10-01');
      await db.update(
        'company_catalog_entries_v1',
        {'name': 'Changed'},
        where: 'id=?',
        whereArgs: ['w'],
      );
      final after = await bridge().snapshot('f', '2026-09');
      expect(PeriodLock.digest(after.tables), PeriodLock.digest(before.tables));
      expect(
        (await bridge().snapshot(
          'f',
          '2026-10',
        )).rows('finance_documents_v2').length,
        2,
      );
      await PeriodCloseRepository.validate(db);
    },
  );
  test(
    'lock rejects insert update moving out and delete; another farm and next month remain writable',
    () async {
      await cash('old', '2026-09-20');
      await closeSeptember();
      await expectLater(cash('backdated', '2026-09-01'), throwsA(anything));
      await expectLater(
        db.update(
          'finance_documents_v2',
          {'occurred_at': '2026-10-01'},
          where: 'id=?',
          whereArgs: ['old'],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.delete('finance_documents_v2', where: 'id=?', whereArgs: ['old']),
        throwsA(anything),
      );
      await cash('other', '2026-09-20', farm: 'other');
      await cash('next', '2026-10-01');
      expect((await db.query('finance_documents_v2')).length, 3);
    },
  );
  test('draft attendance blocks closing without changing anything', () async {
    await service.createRate(admin, rate());
    await service.createEntry(admin, entry('draft'));
    final r = await closing().review('f', '2026-09');
    expect(r.issues, contains('draft:personnel_entries_v1:1'));
    await expectLater(
      closing().close('f', '2026-09', r.token, 0, 'close', 'admin', () {}),
      throwsStateError,
    );
    expect(await db.query(PeriodLock.events), isEmpty);
  });
  test(
    'an unlinked historical salary payment must reconcile before closing',
    () async {
      await salaryReady();
      await db.insert('personnel_payments_v1', {
        'id': 'legacy',
        'farm_id': 'f',
        'payroll_id': 'salary',
        'amount': '0.2',
        'currency': 'VND',
        'business_day': '2026-09-25',
        'note': 'Legacy',
      });
      expect(
        (await closing().review('f', '2026-09')).issues,
        contains('unlinkedSalary:1'),
      );
      await bridge().linkSalary('f', 'legacy', 'admin');
      await closeSeptember();
    },
  );
  test(
    'outstanding payroll carries forward and next-month settlement is allowed',
    () async {
      await salaryReady();
      await closeSeptember();
      await service.recordPayment(
        admin,
        id: 'later',
        payrollId: 'salary',
        amount: '0.2',
        currency: 'VND',
        day: '2026-10-01',
        note: 'Later',
      );
      expect((await service.payrolls(admin)).single.paid, '0.2');
      expect(
        (await bridge().snapshot('f', '2026-09')).rows('personnel_payments_v1'),
        isEmpty,
      );
      await expectLater(
        service.recordPayment(
          admin,
          id: 'old',
          payrollId: 'salary',
          amount: '0.1',
          currency: 'VND',
          day: '2026-09-26',
          note: 'Old',
        ),
        throwsA(anything),
      );
    },
  );
  test(
    'current-month correction to old payroll is allowed but old source stays immutable',
    () async {
      await salaryReady();
      await closeSeptember();
      final d = PayrollAdjustmentDraft(
        id: 'later-adjust',
        farmId: 'f',
        payrollId: 'salary',
        currency: 'VND',
        day: '2026-10-01',
        delta: '0.2',
        reason: 'Current correction',
        expectedRevision: 0,
      );
      final original = await db.query('personnel_payrolls_v1');
      await service.createPayrollAdjustment(admin, d);
      await service.approvePayrollAdjustment(admin, d.id);
      expect((await service.payrolls(admin)).single.effectiveNet, '1.2');
      expect(
        (await bridge().snapshot('f', '2026-09')).salaryNet('salary'),
        '1',
      );
      await PeriodCloseRepository.validate(db);
      await expectLater(
        db.update(
          'personnel_payrolls_v1',
          {'note': 'Changed'},
          where: 'id=?',
          whereArgs: ['salary'],
        ),
        throwsA(anything),
      );
      expect(await db.query('personnel_payrolls_v1'), original);
    },
  );
  test(
    'stale review rejects ledger changes before approval and concurrent double close',
    () async {
      final c = closing();
      final r = await c.review('f', '2026-09');
      await cash('change', '2026-09-25');
      await expectLater(
        c.close('f', '2026-09', r.token, 0, 'close', 'admin', () {}),
        throwsStateError,
      );
      final fresh = await c.review('f', '2026-09');
      await c.close('f', '2026-09', fresh.token, 0, 'close', 'admin', () {});
      await expectLater(
        c.close('f', '2026-09', fresh.token, 0, 'duplicate', 'admin', () {}),
        throwsStateError,
      );
      expect((await db.query(PeriodLock.events)).length, 1);
    },
  );
  test('requires finished month reason actor and a valid YYYY-MM', () async {
    expect(
      (await closing(day: '2026-09-30').review('f', '2026-09')).issues,
      contains('monthNotEnded'),
    );
    await expectLater(closing().review('f', '2026-13'), throwsFormatException);
    final r = await closing().review('f', '2026-09');
    await expectLater(
      closing().close('f', '2026-09', r.token, 0, ' ', 'admin', () {}),
      throwsFormatException,
    );
    await expectLater(
      closing().close('f', '2026-09', r.token, 0, 'why', '', () {}),
      throwsFormatException,
    );
  });
  test(
    'reopen keeps history; changes require a fresh review then a new frozen revision',
    () async {
      await cash('old', '2026-09-20');
      await closeSeptember();
      final c = closing();
      final r = await c.review('f', '2026-09');
      await c.reopen(
        'f',
        '2026-09',
        r.revision,
        'Fix source',
        'manager',
        () {},
      );
      await cash('fix', '2026-09-21');
      await closeSeptember();
      final events = await db.query(PeriodLock.events, orderBy: 'revision');
      expect(events.map((e) => e['action']), ['close', 'reopen', 'close']);
      expect(events[1]['actor_id'], 'manager');
      await expectLater(db.delete(PeriodLock.events), throwsA(anything));
      await expectLater(
        db.update(PeriodLock.events, {'reason': 'rewrite'}),
        throwsA(anything),
      );
      await PeriodCloseRepository.validate(db);
    },
  );
  test(
    'later closed months must be reopened before an earlier month',
    () async {
      await closeSeptember();
      final c = closing(day: '2026-11-01');
      final n = await c.review('f', '2026-10');
      await c.close('f', '2026-10', n.token, 0, 'November', 'admin', () {});
      await expectLater(
        c.reopen('f', '2026-09', 1, 'Earlier', 'admin', () {}),
        throwsStateError,
      );
      await c.reopen('f', '2026-10', 1, 'Newest first', 'admin', () {});
      await c.reopen('f', '2026-09', 1, 'Then October', 'admin', () {});
      await cash('fix', '2026-09-25');
      await PeriodCloseRepository.validate(db);
    },
  );
  test(
    'authorization change just before commit rolls back history and locking state',
    () async {
      final c = closing();
      final r = await c.review('f', '2026-09');
      var count = 0;
      await expectLater(
        c.close('f', '2026-09', r.token, 0, 'Close', 'admin', () {
          if (++count == 2) {
            throw StateError('Logged out');
          }
        }),
        throwsStateError,
      );
      expect(await db.query(PeriodLock.events), isEmpty);
      expect(await db.query(PeriodLock.states), isEmpty);
      await cash('still-open', '2026-09-25');
    },
  );
  test(
    'permission checks require all-farm complete report access and explicit closing permissions',
    () async {
      final access = IntegrationService(
        repository: bridge(),
        subject: admin,
        currentSubject: () => live,
      );
      final s = PeriodCloseService(repository: closing(), access: access);
      expect(s.canClose, isTrue);
      live = AuthorizationSubject(
        userId: 'admin',
        membershipId: 'm',
        farmId: 'f',
        permissionCodes: {PermissionCodes.financeView},
        dataScopes: {DataScope.allFarm},
      );
      expect(s.canClose, isFalse);
      await expectLater(s.review('2026-09'), throwsStateError);
    },
  );
  test(
    'backup validator detects broken digest chain state and cross-farm frozen data',
    () async {
      await closeSeptember();
      await PeriodLock.removeGuards(db);
      await db.update(PeriodLock.events, {'digest': 'tamper'});
      await expectLater(PeriodCloseRepository.validate(db), throwsStateError);
    },
  );
  test(
    'older backups with no closing tables are compatible; missing one history table is rejected',
    () async {
      await PeriodLock.removeGuards(db);
      await db.execute('DROP TABLE accounting_periods_v1');
      await db.execute('DROP TABLE accounting_period_events_v1');
      await PeriodCloseRepository.validate(db);
      await PeriodLock.createSchema(db);
      await closeSeptember();
      await PeriodLock.removeGuards(db);
      await db.execute('DROP TABLE accounting_period_events_v1');
      await expectLater(PeriodCloseRepository.validate(db), throwsA(anything));
    },
  );

  test(
    'late month settlement already present is excluded from an earlier closing balance',
    () async {
      await salaryReady();
      await service.recordPayment(
        admin,
        id: 'oct-pay',
        payrollId: 'salary',
        amount: '0.4',
        currency: 'VND',
        day: '2026-10-01',
        note: 'October settlement',
      );
      await closeSeptember();
      final frozen = await bridge().snapshot('f', '2026-09');
      expect(frozen.salaryPaid('salary'), '0');
      expect(frozen.salaryNet('salary'), '1');
      expect(frozen.rows('finance_documents_v2'), isEmpty);
      expect(frozen.closingRevision, 1);
      expect(frozen.closedBy, 'admin');
      expect(Report20(frozen).workbook().tables.length, 20);
      await PeriodCloseRepository.validate(db);
    },
  );
  test(
    'closed backup rejects altered locked cash even with a recomputed file checksum',
    () async {
      await cash('old', '2026-09-20');
      await closeSeptember();
      final costs = await databaseFactoryFfi.openDatabase(
        '${directory.path}/agrico_costs.db',
      );
      await costs.execute('CREATE TABLE production_costs(id TEXT PRIMARY KEY)');
      try {
        final bytes = await LocalDatabaseSnapshot.create(
          db,
          costsDatabase: costs,
        );
        Future<void> check(Uint8List value) async {
          await LocalRestorePreflight.validate(
            bytes: value,
            primary: db,
            costs: costs,
            factory: databaseFactoryFfi,
            temporaryDirectory: directory.path,
          );
        }

        await check(bytes);
        final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final payload =
            jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
        final t =
            ((payload['databases'] as Map)['agrico.db'] as Map)['tables']
                as Map;
        (t['finance_documents_v2'] as List).single['amount_minor'] = 99;
        final body = jsonEncode(payload);
        envelope['payload'] = body;
        envelope['sha256'] = sha256.convert(utf8.encode(body)).toString();
        await expectLater(
          check(Uint8List.fromList(utf8.encode(jsonEncode(envelope)))),
          throwsA(isA<RestorePreflightException>()),
        );
        expect(
          (await db.query('finance_documents_v2')).single['amount_minor'],
          1,
        );
      } finally {
        await costs.close();
      }
    },
  );
  test(
    'activation restores a closed snapshot atomically and reinstalls guards',
    () async {
      await cash('old', '2026-09-20');
      await closeSeptember();
      final costs = await databaseFactoryFfi.openDatabase(
        '${directory.path}/agrico_costs.db',
      );
      await costs.execute('CREATE TABLE production_costs(id TEXT PRIMARY KEY)');
      final bytes = await LocalDatabaseSnapshot.create(
        db,
        costsDatabase: costs,
      );
      await cash('later', '2026-10-01');
      await db.close();
      await costs.close();
      final activation = LocalRestoreActivation(directory, databaseFactoryFfi);
      await activation.schedule(bytes);
      expect(await activation.applyPending(), isTrue);
      db = await databaseFactoryFfi.openDatabase('${directory.path}/agrico.db');
      expect((await db.query('finance_documents_v2')).length, 1);
      await PeriodCloseRepository.validate(db);
      await expectLater(cash('forbidden', '2026-09-20'), throwsA(anything));
      await cash('allowed', '2026-10-01');
    },
  );
  test(
    'restoring an older pre-lock backup clears newer closing state and all guards remain ready',
    () async {
      final costs = await databaseFactoryFfi.openDatabase(
        '${directory.path}/agrico_costs.db',
      );
      await costs.execute('CREATE TABLE production_costs(id TEXT PRIMARY KEY)');
      final original = await LocalDatabaseSnapshot.create(
        db,
        costsDatabase: costs,
      );
      final envelope =
          jsonDecode(utf8.decode(original)) as Map<String, dynamic>;
      final body =
          jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
      final t =
          ((body['databases'] as Map)['agrico.db'] as Map)['tables'] as Map;
      for (final name in PeriodLock.tables) {
        t.remove(name);
      }
      final text = jsonEncode(body);
      envelope['payload'] = text;
      envelope['sha256'] = sha256.convert(utf8.encode(text)).toString();
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
      await closeSeptember();
      await db.close();
      await costs.close();
      final activation = LocalRestoreActivation(directory, databaseFactoryFfi);
      await activation.schedule(bytes);
      expect(await activation.applyPending(), isTrue);
      db = await databaseFactoryFfi.openDatabase('${directory.path}/agrico.db');
      expect(await db.query(PeriodLock.states), isEmpty);
      expect(await db.query(PeriodLock.events), isEmpty);
      await cash('allowed', '2026-09-20');
      await closeSeptember();
      await expectLater(cash('forbidden', '2026-09-21'), throwsA(anything));
    },
  );
  test(
    'current-period capital metadata is allowed while closed source metadata is blocked',
    () async {
      await cash('old', '2026-09-20');
      await closeSeptember();
      await cash('new', '2026-10-01');
      await expectLater(
        bridge().metadata('f', 'capital', 'old', 0, {
          'capitalKind': 'contribution',
          'reason': 'old',
        }, 'admin'),
        throwsA(anything),
      );
      await bridge().metadata('f', 'capital', 'new', 0, {
        'capitalKind': 'contribution',
        'reason': 'current',
      }, 'admin');
      expect(
        (await bridge().snapshot('f', '2026-10')).capitalTotal('LAK'),
        '1',
      );
      await PeriodCloseRepository.validate(db);
    },
  );

  test(
    'UTC+7 month boundaries govern stock locks and closing balances',
    () async {
      final catalog = CompanyCatalogService(
        repository: SqliteCompanyCatalog(db),
        subject: admin,
      );
      await catalog.create(
        const CatalogEntry(
          id: 'mat',
          farmId: 'f',
          kind: CatalogKind.material,
          code: '',
          name: 'Seed',
          unitId: 'unit-ha',
        ),
        reason: 'Material',
      );
      Future<void> receipt(String id, String instant) => inventory.record(
        InventoryMovement(
          id: id,
          farmId: 'f',
          itemId: 'mat',
          kind: InventoryMovementKind.receipt,
          quantity: 1,
          occurredAt: DateTime.parse(instant),
        ),
      );
      await receipt('september', '2026-09-30T16:59:00Z');
      await receipt('october', '2026-09-30T17:00:00Z');
      await closeSeptember();
      final frozen = await bridge().snapshot('f', '2026-09');
      expect(frozen.rows('inventory_movements_v2').map((r) => r['id']), [
        'september',
      ]);
      expect(frozen.rows('inventory_items_v2').single['stock_units'], 1000000);
      await receipt('later', '2026-09-30T18:00:00Z');
      await expectLater(
        receipt('locked', '2026-09-30T16:00:00Z'),
        throwsA(anything),
      );
      await PeriodCloseRepository.validate(db);
    },
  );
  test(
    'sales in the open month may consume a closed harvest without restating its closing stock',
    () async {
      final c = CompanyCatalogService(
        repository: SqliteCompanyCatalog(db),
        subject: admin,
      );
      await c.create(
        const CatalogEntry(
          id: 'product',
          farmId: 'f',
          kind: CatalogKind.product,
          code: '',
          name: 'Peanut',
          unitId: 'unit-ha',
        ),
        reason: 'Product',
      );
      await c.create(
        const CatalogEntry(
          id: 'buyer',
          farmId: 'f',
          kind: CatalogKind.customer,
          code: '',
          name: 'Buyer',
        ),
        reason: 'Customer',
      );
      final trade = SqliteTradeRepository(db);
      await trade.create(
        'f',
        const TradeDraft(
          id: 'harvest',
          kind: TradeKind.harvest,
          day: '2026-09-25',
          currency: 'VND',
          rounding: MoneyRounding.halfUp,
          planId: 'plan',
          lines: [TradeLine(ref: 'product', quantity: '10', price: '5')],
        ),
        'admin',
      );
      await trade.post('f', 'harvest', 0, 'admin');
      await closeSeptember();
      await trade.create(
        'f',
        const TradeDraft(
          id: 'sale',
          kind: TradeKind.sale,
          day: '2026-10-01',
          currency: 'VND',
          rounding: MoneyRounding.halfUp,
          partyId: 'buyer',
          dueOn: '2026-10-01',
          lines: [
            TradeLine(
              ref: 'harvest:0',
              quantity: '4',
              price: '10',
              issuePrice: '5',
            ),
          ],
        ),
        'admin',
      );
      await trade.post('f', 'sale', 0, 'admin');
      expect((await db.query('trade_lots_v1')).single['stock_units'], 6000000);
      final frozen = await bridge().snapshot('f', '2026-09');
      expect(frozen.rows('trade_lots_v1').single['stock_units'], 10000000);
      expect(frozen.rows('trade_documents_v1').length, 1);
      await expectLater(
        db.update(
          'trade_lots_v1',
          {'price': '9'},
          where: 'id=?',
          whereArgs: ['harvest:0'],
        ),
        throwsA(anything),
      );
      await PeriodCloseRepository.validate(db);
    },
  );

  test(
    'the newest approval actor and reason are checked even without a later history event',
    () async {
      await closeSeptember();
      await PeriodLock.removeGuards(db);
      await db.update(PeriodLock.events, {
        'actor_id': 'rewritten',
        'reason': 'Rewritten reason',
      });
      await expectLater(PeriodCloseRepository.validate(db), throwsStateError);
    },
  );
}
