import 'package:agrico_deepseek/features/trade/domain/trade.dart'
    show TradeDraft, TradeKind, TradeLine;
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:agrico_deepseek/features/machines/domain/machines.dart'
    show MachineExpense;
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/integration/data/integration_repository.dart';
import 'package:agrico_deepseek/features/integration/data/integration_cash.dart';
import 'package:agrico_deepseek/features/integration/data/integration_integrity.dart';
import 'package:agrico_deepseek/features/integration/application/integration_service.dart';
import 'package:agrico_deepseek/features/integration/application/report20.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_summary.dart';
import 'package:agrico_deepseek/features/trade/data/sqlite_trade_repository.dart';
import 'package:agrico_deepseek/features/machines/data/sqlite_machine_repository.dart';
import 'dart:io';
import 'dart:convert';
import 'package:excel/excel.dart';
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
    service = PersonnelService(repo);
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
  test(
    'salary exact cash and append-only refund are atomic and idempotent',
    () async {
      await salaryReady();
      await pay();
      await pay();
      expect(await db.query('integration_cash_links_v1'), hasLength(1));
      var cash = await db.query('finance_documents_v2');
      expect(cash, hasLength(1));
      expect(IntegrationCash.amount(cash.single), '0.25');
      expect(cash.single['amount_scale'], 2);
      expect((await service.payrolls(admin)).single.remaining, '0.75');
      final cost = await repo.productionLaborCosts('f');
      await bridge().reverseSalary(
        'f',
        'pay',
        'refund',
        '2026-10-26',
        'Cancelled transfer',
        'admin',
      );
      await bridge().reverseSalary(
        'f',
        'pay',
        'refund',
        '2026-10-26',
        'Cancelled transfer',
        'admin',
      );
      expect((await service.payrolls(admin)).single.remaining, '1');
      expect((await service.payments(admin)).single.reversed, isTrue);
      expect(await repo.productionLaborCosts('f'), hasLength(cost.length));
      final summary = await FinanceDocumentSummary(
        SqliteFinanceDocumentRepository(db),
      ).byOrganization('f');
      expect(summary.single.receiptsText, '0.25');
      expect(summary.single.paymentsText, '0.25');
      expect(summary.single.balanceText, '0');
      await PersonnelIntegrity.validate(db);
      await IntegrationIntegrity.validate(db);
      await pay(id: 'replacement', amount: '1');
      expect((await service.payrolls(admin)).single.remaining, '0');
      await expectLater(pay(id: 'over', amount: '0.01'), throwsStateError);
    },
  );
  test(
    'failed finance insert rolls back HR payment and both sequences',
    () async {
      await salaryReady();
      await db.execute(
        "CREATE TRIGGER fail_cash BEFORE INSERT ON finance_documents_v2 BEGIN SELECT RAISE(ABORT,'test'); END",
      );
      await expectLater(pay(), throwsA(isA<DatabaseException>()));
      expect(await db.query('personnel_payments_v1'), isEmpty);
      expect(await db.query('integration_cash_links_v1'), isEmpty);
      await db.execute('DROP TRIGGER fail_cash');
      await pay();
      expect(
        (await db.query('finance_documents_v2')).single['code'],
        'CHI-202610-001',
      );
    },
  );
  test(
    'salary posting rejects future date and does not consume records',
    () async {
      await salaryReady();
      await expectLater(
        pay(day: '2099-01-01'),
        throwsA(isA<FormatException>()),
      );
      expect(await db.query('personnel_payments_v1'), isEmpty);
    },
  );
  test(
    'metadata keeps spatial payload untouched and enforces revision and source farm',
    () async {
      final before = await db.query('land_parcels');
      await bridge().metadata('f', 'parcel', 'p', 0, {
        'pH': '6.5',
        'soilType': 'Đất ດິນ',
      }, 'admin');
      expect(await db.query('land_parcels'), before);
      await expectLater(
        bridge().metadata('f', 'parcel', 'p', 0, {'pH': '7'}, 'admin'),
        throwsStateError,
      );
      await expectLater(
        bridge().metadata('f', 'parcel', 'p', 1, {'pH': '15'}, 'admin'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        bridge().metadata('other', 'parcel', 'p', 1, {'pH': '7'}, 'admin'),
        throwsStateError,
      );
      await IntegrationIntegrity.validate(db);
    },
  );
  test(
    'full 20-sheet report preserves identity text, exact cash, currency and formulas',
    () async {
      await salaryReady();
      await pay();
      await service.saveProfile(
        admin,
        EmployeeProfile(
          workerId: 'w',
          farmId: 'f',
          details: {
            'phone': '0123456789',
            'bankAccount': '0000123',
            'identityNo': '0009',
          },
        ),
      );
      final s = await bridge().snapshot('f', '2026-10');
      final bytes = Report20(s).bytes();
      final x = Excel.decodeBytes(bytes);
      expect(x.tables, hasLength(20));
      final staff = x['DANH SACH NV'];
      expect(staff.rows[1][5]!.value, TextCellValue('0123456789'));
      expect(staff.rows[1][13]!.value, TextCellValue('0000123'));
      expect(x['THU CHI'].rows[1][7]!.value, DoubleCellValue(0.25));
      expect(s.cashTotal('VND', 'CHI'), '0.25');
      expect(s.cashTotal('LAK', 'CHI'), '0');
      expect(
        x['DASHBOARD'].rows
            .where((r) => r.first?.value.toString() == 'Chi tiền')
            .single[1]!
            .value,
        DoubleCellValue(0.25),
      );
    },
  );
  test('snapshot authorization revocation and farm boundaries', () async {
    var live = admin;
    final api = IntegrationService(
      repository: bridge(),
      subject: admin,
      currentSubject: () => live,
    );
    final s = await api.snapshot('2026-10');
    expect(
      s.rows('company_catalog_entries_v1').every((r) => r['farm_id'] == 'f'),
      isTrue,
    );
    live = const AuthorizationSubject(
      userId: 'admin',
      membershipId: 'm',
      farmId: 'f',
      permissionCodes: {},
      dataScopes: {DataScope.allFarm},
    );
    await expectLater(api.snapshot('2026-10'), throwsStateError);
  });

  Future<void> machineSource({String id = 'fuel', String kind = 'fuel'}) async {
    final machines = SqliteMachineRepository(db);
    await machines.profile('f', 'machine', 0, {'meterUnit': 'hour'}, 'admin');
    await machines.addExpense(
      'f',
      MachineExpense(
        id: id,
        machineId: 'machine',
        kind: kind,
        day: '2026-10-25',
        amount: '25.5',
        currency: 'VND',
        reference: id,
        note: 'Approved machine component',
        litres: kind == 'fuel' ? '2.5' : null,
      ),
      'admin',
    );
    await machines.approveExpense('f', id, 0, 'admin');
  }

  Future<void> supplier() async =>
      CompanyCatalogService(
        repository: SqliteCompanyCatalog(db),
        subject: admin,
      ).create(
        const CatalogEntry(
          id: 'supplier',
          farmId: 'f',
          kind: CatalogKind.supplier,
          code: '',
          name: 'Nhà cung cấp',
        ),
        reason: 'test',
      );
  Future<void> fuelStock() async {
    final c = CompanyCatalogService(
      repository: SqliteCompanyCatalog(db),
      subject: admin,
    );
    await c.create(
      const CatalogEntry(
        id: 'litre',
        farmId: 'f',
        kind: CatalogKind.unit,
        code: '',
        name: 'Lít',
      ),
      reason: 'test',
    );
    await c.create(
      const CatalogEntry(
        id: 'diesel',
        farmId: 'f',
        kind: CatalogKind.material,
        code: '',
        name: 'Diesel',
        unitId: 'litre',
      ),
      reason: 'test',
    );
    await inventory.record(
      InventoryMovement(
        id: 'opening',
        farmId: 'f',
        itemId: 'diesel',
        kind: InventoryMovementKind.receipt,
        quantity: 10,
        occurredAt: DateTime(2026, 10, 24),
        unitPriceText: '10',
        currency: 'VND',
        pricedBy: 'admin',
      ),
    );
  }

  test(
    'machine payable is one atomic included-cost document and prevents stock duplication',
    () async {
      await supplier();
      await machineSource();
      await bridge().machinePayable(
        'f',
        'fuel',
        'supplier',
        'invoice',
        MoneyRounding.halfUp,
        'admin',
      );
      await bridge().machinePayable(
        'f',
        'fuel',
        'supplier',
        'invoice',
        MoneyRounding.halfUp,
        'admin',
      );
      final docs = await db.query('trade_documents_v1');
      expect(docs, hasLength(1));
      expect(docs.single['total'], '26');
      expect(
        jsonDecode(docs.single['body'] as String)['expenseTreatment'],
        'includedInProduction',
      );
      expect(await db.query('finance_documents_v2'), isEmpty);
      expect(await db.query('production_material_costs_v2'), isEmpty);
      await expectLater(
        bridge().fuelIssue('f', 'fuel', 'diesel', '10', false, 'admin'),
        throwsStateError,
      );
      await expectLater(
        SqliteMachineRepository(
          db,
        ).voidExpense('f', 'fuel', 1, 'cancel', 'admin'),
        throwsStateError,
      );
      await IntegrationIntegrity.validate(db);
    },
  );
  test(
    'internal fuel reduces stock once and refund restores it without cash or production costs',
    () async {
      await fuelStock();
      await machineSource();
      await bridge().fuelIssue('f', 'fuel', 'diesel', '10', false, 'admin');
      await bridge().fuelIssue('f', 'fuel', 'diesel', '10', false, 'admin');
      expect(
        (await db.query(
          'inventory_items_v2',
          where: 'id=?',
          whereArgs: ['diesel'],
        )).single['stock_units'],
        7500000,
      );
      expect(await db.query('production_material_costs_v2'), isEmpty);
      expect(await db.query('trade_documents_v1'), isEmpty);
      expect(await db.query('finance_documents_v2'), isEmpty);
      await expectLater(
        bridge().machinePayable(
          'f',
          'fuel',
          'supplier',
          'dup',
          MoneyRounding.halfUp,
          'admin',
        ),
        throwsStateError,
      );
      await bridge().reverseFuel(
        'f',
        'fuel',
        '2026-10-26',
        'unused fuel',
        'admin',
      );
      expect(
        (await db.query(
          'inventory_items_v2',
          where: 'id=?',
          whereArgs: ['diesel'],
        )).single['stock_units'],
        10000000,
      );
      await SqliteMachineRepository(
        db,
      ).voidExpense('f', 'fuel', 1, 'cancel source', 'admin');
      await IntegrationIntegrity.validate(db);
    },
  );
  test('insufficient fuel stock rolls back the link and movement', () async {
    await fuelStock();
    await machineSource();
    await inventory.record(
      InventoryMovement(
        id: 'other',
        farmId: 'f',
        itemId: 'diesel',
        kind: InventoryMovementKind.issue,
        quantity: 9,
        occurredAt: DateTime(2026, 10, 25),
        unitPriceText: '10',
        currency: 'VND',
        pricedBy: 'admin',
      ),
    );
    await expectLater(
      bridge().fuelIssue('f', 'fuel', 'diesel', '10', false, 'admin'),
      throwsStateError,
    );
    expect(await db.query('integration_fuel_issues_v1'), isEmpty);
    expect(await db.query('inventory_movements_v2'), hasLength(2));
  });
  test(
    'historical salary requires explicit matching cash adoption and retains original document',
    () async {
      await salaryReady();
      await db.insert('personnel_payments_v1', {
        'id': 'old',
        'farm_id': 'f',
        'payroll_id': 'salary',
        'amount': '1',
        'currency': 'VND',
        'business_day': '2026-10-25',
        'note': 'Previously paid',
      });
      final cash = await SqliteFinanceDocumentRepository(db).create(
        id: 'old-cash',
        organizationId: 'f',
        kind: BusinessDocumentKind.payment,
        occurredAt: DateTime(2026, 10, 25),
        amountMinor: 1,
        currency: 'VND',
        category: 'Payroll',
        description: 'Original voucher',
      );
      expect((await bridge().snapshot('f', '2026-10')).warnings, hasLength(1));
      await expectLater(
        bridge().linkSalary('f', 'old', 'admin', existingFinanceId: 'missing'),
        throwsStateError,
      );
      await bridge().linkSalary(
        'f',
        'old',
        'admin',
        existingFinanceId: cash.id,
      );
      await bridge().linkSalary(
        'f',
        'old',
        'admin',
        existingFinanceId: cash.id,
      );
      expect(await db.query('finance_documents_v2'), hasLength(1));
      expect(
        (await db.query('finance_documents_v2')).single['description'],
        'Original voucher',
      );
      expect(
        (await SqliteFinanceDocumentRepository(
          db,
        ).listByOrganization('f')).single.isSettlement,
        isTrue,
      );
      await IntegrationIntegrity.validate(db);
      await expectLater(
        bridge().linkSalary('f', 'old', 'admin', existingFinanceId: 'other'),
        throwsStateError,
      );
    },
  );
  test(
    'backup preflight verifies exact salary links and rejects changed coefficient',
    () async {
      await salaryReady();
      await pay();
      final dir = await Directory.systemTemp.createTemp(
        'agrico-integration-backup-',
      );
      final costs = await databaseFactoryFfi.openDatabase(
        '${dir.path}/costs.db',
      );
      await costs.execute('CREATE TABLE production_costs(id TEXT PRIMARY KEY)');
      try {
        final bytes = await LocalDatabaseSnapshot.create(
          db,
          costsDatabase: costs,
        );
        await LocalRestorePreflight.validate(
          bytes: bytes,
          primary: db,
          costs: costs,
          factory: databaseFactoryFfi,
          temporaryDirectory: dir.path,
        );
        await db.update('finance_documents_v2', {'amount_minor': 26});
        final bad = await LocalDatabaseSnapshot.create(
          db,
          costsDatabase: costs,
        );
        await expectLater(
          LocalRestorePreflight.validate(
            bytes: bad,
            primary: db,
            costs: costs,
            factory: databaseFactoryFfi,
            temporaryDirectory: dir.path,
          ),
          throwsA(isA<RestorePreflightException>()),
        );
      } finally {
        await costs.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'stock report formulas include opening balance and cached values, and summary money occurs once per currency',
    () async {
      await fuelStock();
      await db.update(
        'inventory_movements_v2',
        {'occurred_at': DateTime.utc(2026, 9, 30, 5).toIso8601String()},
        where: 'id=?',
        whereArgs: ['opening'],
      );
      await machineSource();
      await bridge().fuelIssue('f', 'fuel', 'diesel', '10', false, 'admin');
      final report = Report20(await bridge().snapshot('f', '2026-10'));
      final encoded = report.bytes();
      final excel = Excel.decodeBytes(encoded);
      final stock = excel['TH KHO VA TAI CHINH'];
      expect(stock.rows[1][2]!.value, isA<FormulaCellValue>());
      expect(stock.rows[1][3]!.value, isA<FormulaCellValue>());
      expect(stock.rows[1][13]!.value, IntCellValue(10));
      expect(
        stock.rows.where(
          (r) =>
              r.length > 1 &&
              r[1]?.value.toString().startsWith('Tổng tiền') == true,
        ),
        hasLength(2),
      );
      final archive = ZipDecoder().decodeBytes(encoded);
      final caches = <String>[];
      for (final entry in archive.files.where(
        (f) => f.name.startsWith('xl/worksheets/') && f.name.endsWith('.xml'),
      )) {
        final xml = XmlDocument.parse(utf8.decode(entry.content as List<int>));
        for (final c
            in xml
                .findAllElements('c')
                .where((c) => c.findElements('f').isNotEmpty)) {
          caches.add(c.findElements('v').single.innerText);
        }
      }
      expect(caches, containsAll(['0', '2.5', '7.5']));
    },
  );

  test(
    'harvest yield and revenue use actual kg lots and sales rather than assumed harvest value',
    () async {
      final c = CompanyCatalogService(
        repository: SqliteCompanyCatalog(db),
        subject: admin,
      );
      await c.create(
        const CatalogEntry(
          id: 'kg',
          farmId: 'f',
          kind: CatalogKind.unit,
          code: '',
          name: 'kg',
        ),
        reason: 'test',
      );
      await c.create(
        const CatalogEntry(
          id: 'product',
          farmId: 'f',
          kind: CatalogKind.product,
          code: '',
          name: 'Lạc',
          unitId: 'kg',
        ),
        reason: 'test',
      );
      await c.create(
        const CatalogEntry(
          id: 'buyer',
          farmId: 'f',
          kind: CatalogKind.customer,
          code: '',
          name: 'Buyer',
        ),
        reason: 'test',
      );
      await db.execute('ALTER TABLE land_parcels ADD COLUMN payload_json TEXT');
      await db.update('land_parcels', {
        'payload_json': jsonEncode({'name': 'Thửa', 'areaM2': 100}),
      });
      final trade = SqliteTradeRepository(db);
      await trade.create(
        'f',
        const TradeDraft(
          id: 'harvest',
          kind: TradeKind.harvest,
          day: '2026-10-25',
          currency: 'VND',
          rounding: MoneyRounding.halfUp,
          planId: 'plan',
          lines: [TradeLine(ref: 'product', quantity: '10', price: '5')],
        ),
        'admin',
      );
      await trade.post('f', 'harvest', 0, 'admin');
      await trade.create(
        'f',
        const TradeDraft(
          id: 'sale',
          kind: TradeKind.sale,
          day: '2026-10-26',
          currency: 'VND',
          rounding: MoneyRounding.halfUp,
          partyId: 'buyer',
          dueOn: '2026-10-26',
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
      var snapshot = await bridge().snapshot('f', '2026-10');
      var report = Report20(snapshot).workbook();
      expect(snapshot.sales('plan', 'VND'), '40');
      expect(report['THU HOACH'].rows[1][8]!.value, IntCellValue(40));
      expect(report['THONG KE LO DAT'].rows[1][6]!.value, DoubleCellValue(0.1));
      await trade.voidDocument(
        'f',
        'sale',
        1,
        '2026-10-26',
        'Cancelled sale',
        'admin',
      );
      snapshot = await bridge().snapshot('f', '2026-10');
      report = Report20(snapshot).workbook();
      expect(snapshot.sales('plan', 'VND'), '0');
      expect(report['THU HOACH'].rows[1][8]!.value, IntCellValue(0));
    },
  );
}
