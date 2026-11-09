import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/production_plan.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/production_destination_repository.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:agrico_deepseek/features/trade/application/trade_service.dart';
import 'package:agrico_deepseek/features/trade/application/trade_report.dart';
import 'package:agrico_deepseek/features/trade/data/sqlite_trade_repository.dart';
import 'package:agrico_deepseek/features/trade/data/trade_integrity.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteTradeRepository repo;
  late SqliteInventoryRepository stock;
  late TradeService service;
  final admin = AuthorizationSubject(
    userId: 'admin',
    membershipId: 'm',
    farmId: 'f',
    permissionCodes: PermissionCodes.values,
    dataScopes: const {DataScope.allFarm},
  );
  TradeDraft harvest({
    String id = 'h',
    String quantity = '10',
    String price = '5',
    String day = '2026-10-20',
    String currency = 'VND',
  }) => TradeDraft(
    id: id,
    kind: TradeKind.harvest,
    day: day,
    currency: currency,
    rounding: MoneyRounding.halfUp,
    lines: [TradeLine(ref: 'product', quantity: quantity, price: price)],
    planId: 'p',
  );
  TradeDraft sale({
    String id = 's',
    String quantity = '4',
    String price = '10',
    String day = '2026-10-21',
    String currency = 'VND',
    List<TradeLine>? lines,
  }) => TradeDraft(
    id: id,
    kind: TradeKind.sale,
    day: day,
    currency: currency,
    rounding: MoneyRounding.halfUp,
    lines:
        lines ??
        [
          TradeLine(
            ref: 'h:0',
            issuePrice: '5',
            quantity: quantity,
            price: price,
          ),
        ],
    partyId: 'customer',
    dueOn: '2026-10-25',
  );
  TradeDraft purchase({
    String id = 'buy',
    String quantity = '3',
    String price = '7',
  }) => TradeDraft(
    id: id,
    kind: TradeKind.purchase,
    day: '2026-10-20',
    currency: 'VND',
    rounding: MoneyRounding.down,
    lines: [TradeLine(ref: 'material', quantity: quantity, price: price)],
    partyId: 'supplier',
    dueOn: '2026-10-25',
    reference: 'PO001',
  );
  TradeDraft expense({
    String id = 'expense',
    String treatment = 'periodExpense',
  }) => TradeDraft(
    id: id,
    kind: TradeKind.expense,
    day: '2026-10-20',
    currency: 'VND',
    rounding: MoneyRounding.halfUp,
    lines: const [
      TradeLine(ref: '', quantity: '1', price: '12', label: 'Transport'),
    ],
    partyId: 'supplier',
    dueOn: '2026-10-25',
    reference: 'CP001',
    expenseTreatment: treatment,
  );
  Future<TradeRecord> saved(String id) async =>
      (await repo.documents('f')).firstWhere((r) => r.draft.id == id);
  Future<void> post(TradeDraft d) async {
    await repo.create('f', d, 'admin');
    await repo.post('f', d.id, 0, 'admin');
  }

  Future<void> pay({
    String id = 'pay',
    String doc = 's',
    String amount = '15',
    String currency = 'VND',
    String day = '2026-10-22',
  }) => repo.settle(
    'f',
    id,
    doc,
    amount,
    currency,
    day,
    'Bank reference $id',
    'admin',
  );
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys=ON');
    await db.execute(
      'CREATE TABLE land_parcels(id TEXT PRIMARY KEY,farm_id TEXT,parcel_code TEXT,active INTEGER,kind TEXT)',
    );
    await db.execute(
      'CREATE TABLE parcel_work_resources(id TEXT PRIMARY KEY,farm_id TEXT,kind TEXT,code TEXT,name TEXT,active INTEGER)',
    );
    await db.execute(
      'CREATE TABLE farm_tasks_v2(id TEXT PRIMARY KEY,farm_id TEXT,status TEXT,worker_resource_id TEXT,machine_resource_id TEXT)',
    );
    await SqliteInventoryRepository.createSchema(db);
    await SqliteCompanyCatalog.createSchema(db);
    await SqliteFinanceDocumentRepository.createSchema(db);
    await SqliteTradeRepository.createSchema(db);
    stock = SqliteInventoryRepository(db);
    repo = SqliteTradeRepository(db);
    service = TradeService(repo, subject: admin, currentSubject: () => admin);
    final catalog = CompanyCatalogService(
      repository: SqliteCompanyCatalog(db),
      subject: admin,
    );
    for (final (id, kind, unit) in [
      ('unit', CatalogKind.unit, null),
      ('product', CatalogKind.product, 'unit'),
      ('material', CatalogKind.material, 'unit'),
      ('customer', CatalogKind.customer, null),
      ('supplier', CatalogKind.supplier, null),
    ]) {
      await catalog.create(
        CatalogEntry(
          id: id,
          farmId: 'f',
          kind: kind,
          code: '',
          name: id,
          unitId: unit,
        ),
        reason: 'Setup',
      );
    }
    await db.insert('land_parcels', {
      'id': 'land',
      'farm_id': 'f',
      'parcel_code': 'P001',
      'active': 1,
      'kind': 'fieldPlot',
    });
    await stock.createProductionSeason(
      const ProductionSeason(
        id: 'season',
        farmId: 'f',
        parcelId: 'land',
        name: 'Season',
        startsOn: '2026-10-01',
      ),
    );
    await stock.createProductionPlan(
      const ProductionPlan(
        id: 'p',
        farmId: 'f',
        parcelId: 'land',
        seasonId: 'season',
        name: 'Plan',
        crop: 'Peanut',
        startsOn: '2026-10-01',
        endsOn: '2026-10-31',
        currency: 'VND',
        materialBudget: '1000',
        laborBudget: '0',
        machineBudget: '0',
        laborHours: '0',
        machineShifts: '0',
      ),
      'admin',
    );
    await stock.changeProductionPlanStatus(
      'f',
      'p',
      0,
      ProductionPlanStatus.active,
      'admin',
    );
  });
  tearDown(() async {
    await db.close();
  });
  test(
    'new customer and product use generated shared codes and warehouse identity',
    () async {
      final cards = await SqliteCompanyCatalog(db).entries('f');
      expect(cards.firstWhere((c) => c.id == 'product').code, 'TP-000001');
      expect(cards.firstWhere((c) => c.id == 'customer').code, 'KH-000001');
      expect(
        (await stock.listByFarm(
          'f',
        )).firstWhere((i) => i.id == 'product').finishedGoods,
        isTrue,
      );
      expect(
        (await db.query('inventory_items_v2', where: "id='product'")).length,
        1,
      );
    },
  );
  test(
    'harvest atomically posts lot and shared NHAP stock with plan',
    () async {
      await post(harvest());
      final lot = (await repo.lots('f')).single;
      expect(lot.stockUnits, 10000000);
      expect(lot.planId, 'p');
      expect((await saved('h')).code, 'TH-202610-001');
      expect((await stock.movementsByFarm('f')).single.code, 'NHAP-202610-001');
      expect(await repo.cashBook('f'), isEmpty);
      await TradeIntegrity.validate(db);
    },
  );
  test('sale posts lot reduction, COGS and debt before cash', () async {
    await post(harvest());
    await post(sale());
    expect((await repo.lots('f')).single.quantity, '6');
    expect((await saved('s')).balance, '40');
    expect(
      ((await saved('s')).snapshots['lines'] as List).single['cost'],
      '20',
    );
    expect(await repo.cashBook('f'), isEmpty);
    await TradeIntegrity.validate(db);
  });
  test(
    'partial settlement posts exactly one shared THU and remaining balance',
    () async {
      await post(harvest());
      await post(sale());
      await pay();
      await pay();
      expect((await saved('s')).paid, '15');
      expect((await saved('s')).balance, '25');
      final cash = await repo.cashBook('f');
      expect(cash.single['code'], 'THU-202610-001');
      expect(cash.single['amount_minor'], 15);
      await TradeIntegrity.validate(db);
    },
  );
  test(
    'wrong currency, early date and overpayment leave no cash or sequence',
    () async {
      await post(harvest());
      await post(sale());
      await expectLater(pay(currency: 'LAK'), throwsStateError);
      await expectLater(pay(day: '2026-10-20'), throwsStateError);
      await expectLater(pay(amount: '41'), throwsStateError);
      expect(await repo.cashBook('f'), isEmpty);
      expect(
        await db.query('monthly_document_sequences', where: "kind='THU'"),
        isEmpty,
      );
    },
  );
  test('same payment ID with changed content is rejected', () async {
    await post(harvest());
    await post(sale());
    await pay();
    await expectLater(pay(amount: '16'), throwsStateError);
    expect((await repo.payments('f')).length, 1);
    expect((await saved('s')).balance, '25');
  });
  test(
    'reverse payment appends CHI and restores debt without deleting THU',
    () async {
      await post(harvest());
      await post(sale());
      await pay();
      await repo.reversePayment(
        'f',
        'pay',
        'reverse',
        '2026-10-23',
        'Wrong receipt',
        'admin',
      );
      await repo.reversePayment(
        'f',
        'pay',
        'reverse',
        '2026-10-23',
        'Wrong receipt',
        'admin',
      );
      expect((await saved('s')).balance, '40');
      expect((await repo.cashBook('f')).length, 2);
      expect((await repo.payments('f')).single.reversed, isTrue);
      await TradeIntegrity.validate(db);
    },
  );
  test(
    'sale reversal restores stock only after all payments reversed',
    () async {
      await post(harvest());
      await post(sale());
      await pay();
      await expectLater(
        repo.voidDocument('f', 's', 1, '2026-10-23', 'Cancel', 'admin'),
        throwsStateError,
      );
      await repo.reversePayment(
        'f',
        'pay',
        'reverse',
        '2026-10-23',
        'Wrong receipt',
        'admin',
      );
      await repo.voidDocument('f', 's', 1, '2026-10-23', 'Cancel', 'admin');
      expect((await repo.lots('f')).single.quantity, '10');
      expect((await saved('s')).balance, '0');
      expect((await stock.movementsByFarm('f')).length, 3);
      await TradeIntegrity.validate(db);
    },
  );
  test(
    'cannot reverse consumed harvest, unused harvest reverses with XUAT',
    () async {
      await post(harvest());
      await post(sale());
      await expectLater(
        repo.voidDocument('f', 'h', 1, '2026-10-23', 'Cancel', 'admin'),
        throwsStateError,
      );
      await repo.voidDocument('f', 's', 1, '2026-10-23', 'Cancel', 'admin');
      await repo.voidDocument('f', 'h', 1, '2026-10-23', 'Cancel', 'admin');
      expect(await repo.lots('f'), isEmpty);
      expect(
        (await stock.listByFarm(
          'f',
        )).firstWhere((i) => i.id == 'product').stock,
        0,
      );
      await TradeIntegrity.validate(db);
    },
  );
  test(
    'two sale lines exceeding same lot rollback stock and XUAT number',
    () async {
      await post(harvest());
      final d = sale(
        lines: const [
          TradeLine(ref: 'h:0', issuePrice: '5', quantity: '6', price: '10'),
          TradeLine(ref: 'h:0', issuePrice: '5', quantity: '6', price: '10'),
        ],
      );
      await repo.create('f', d, 'admin');
      await expectLater(repo.post('f', 's', 0, 'admin'), throwsStateError);
      expect((await repo.lots('f')).single.quantity, '10');
      expect((await saved('s')).status, 'draft');
      expect((await stock.movementsByFarm('f')).length, 1);
      expect(
        await db.query('monthly_document_sequences', where: "kind='XUAT'"),
        isEmpty,
      );
    },
  );
  test(
    'generic warehouse workflow cannot bypass finished-goods lot ledger',
    () async {
      await post(harvest());
      await expectLater(
        stock.record(
          InventoryMovement(
            id: 'bypass',
            farmId: 'f',
            itemId: 'product',
            kind: InventoryMovementKind.issue,
            quantity: 1,
            occurredAt: DateTime.utc(2026, 10, 21),
            unitPriceText: '5',
            currency: 'VND',
            pricedBy: 'admin',
          ),
        ),
        throwsStateError,
      );
      expect((await repo.lots('f')).single.quantity, '10');
    },
  );
  test(
    'purchase creates stock and AP, CHI settlement does not create another cost',
    () async {
      await post(purchase());
      expect((await saved('buy')).balance, '21');
      expect(
        (await stock.listByFarm(
          'f',
        )).firstWhere((i) => i.id == 'material').stock,
        3,
      );
      await pay(doc: 'buy', amount: '7');
      expect((await saved('buy')).balance, '14');
      expect((await repo.cashBook('f')).single['kind'], 'CHI');
      expect(await stock.productionCosts('f'), isEmpty);
      await TradeIntegrity.validate(db);
    },
  );
  test(
    'purchase correction is blocked after subsequent stock issues',
    () async {
      await post(purchase());
      await stock.record(
        InventoryMovement(
          id: 'issue',
          farmId: 'f',
          itemId: 'material',
          kind: InventoryMovementKind.issue,
          quantity: 1,
          occurredAt: DateTime.utc(2026, 10, 21),
          unitPriceText: '7',
          currency: 'VND',
          pricedBy: 'admin',
        ),
      );
      await expectLater(
        repo.voidDocument(
          'f',
          'buy',
          1,
          '2026-10-23',
          'Wrong supplier',
          'admin',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'expense payable distinguishes period costs and included production components',
    () async {
      await post(expense(treatment: 'includedInProduction'));
      expect((await saved('expense')).balance, '12');
      await pay(doc: 'expense', amount: '12');
      expect((await saved('expense')).balance, '0');
      final book = TradeReport(
        farm: 'f',
        period: '2026-10',
        documents: await repo.documents('f'),
        lots: await repo.lots('f'),
        payments: await repo.payments('f'),
        cash: await repo.cashBook('f'),
      ).workbook();
      expect(book['KET QUA KY'].rows[1][4]!.value.toString(), '0');
      expect(book['KET QUA KY'].rows[1][9]!.value.toString(), '12');
    },
  );
  test(
    'fractional weights and prices round invoice once and conserve line totals',
    () async {
      await post(harvest(quantity: '10.5', price: '0.125'));
      await post(
        sale(
          lines: const [
            TradeLine(ref: 'h:0', issuePrice: '5', quantity: '0.5', price: '1'),
            TradeLine(ref: 'h:0', issuePrice: '5', quantity: '0.5', price: '1'),
          ],
        ),
      );
      expect((await saved('s')).draft.billed, '1');
      final lines = (await saved('s')).snapshots['lines'] as List;
      expect(lines.map((l) => l['billed']).toList(), ['1', '0']);
      expect((await repo.lots('f')).single.quantity, '9.5');
      await TradeIntegrity.validate(db);
    },
  );
  test(
    'zero price requires explicit confirmation and produces no cash debt',
    () async {
      await expectLater(
        repo.create('f', harvest(price: '0'), 'admin'),
        throwsFormatException,
      );
      await post(harvest());
      final d = sale(
        lines: const [
          TradeLine(
            ref: 'h:0',
            issuePrice: '5',
            quantity: '1',
            price: '0',
            zeroConfirmed: true,
          ),
        ],
      );
      await post(d);
      expect((await saved('s')).balance, '0');
      await expectLater(pay(amount: '1'), throwsStateError);
    },
  );
  test(
    'draft replay and duplicate external invoice reference do not consume counter',
    () async {
      final d = purchase();
      await repo.create('f', d, 'admin');
      await repo.create('f', d, 'admin');
      await expectLater(
        repo.create('f', purchase(id: 'buy2'), 'admin'),
        throwsA(anything),
      );
      expect((await repo.documents('f')).length, 1);
      expect((await db.query('trade_sequences_v1')).single['value'], 1);
    },
  );
  test('foreign farm and wrong party kind cannot post', () async {
    await expectLater(repo.create('g', harvest(), 'admin'), throwsStateError);
    final d = purchase().toJson()..['partyId'] = 'customer';
    await expectLater(
      repo.create('f', TradeDraft.fromJson(d), 'admin'),
      throwsStateError,
    );
  });
  test('inactive plan or wrong harvest currency leaves no stock', () async {
    await expectLater(
      repo.create('f', harvest(currency: 'LAK'), 'admin'),
      throwsStateError,
    );
    await db.update('production_plans_v1', {
      'status': 'completed',
    }, where: "id='p'");
    await expectLater(repo.create('f', harvest(), 'admin'), throwsStateError);
    expect(await repo.lots('f'), isEmpty);
  });
  test('sale before harvest and oversell leave no movements', () async {
    await post(harvest());
    await expectLater(
      repo.create('f', sale(day: '2026-10-19'), 'admin'),
      throwsStateError,
    );
    await repo.create('f', sale(quantity: '11'), 'admin');
    await expectLater(repo.post('f', 's', 0, 'admin'), throwsStateError);
    expect((await stock.movementsByFarm('f')).length, 1);
  });
  test(
    'failed post audit rolls back lot, warehouse stock and revision',
    () async {
      await repo.create('f', harvest(), 'admin');
      await expectLater(repo.post('f', 'h', 0, ''), throwsFormatException);
      expect(await repo.lots('f'), isEmpty);
      expect((await saved('h')).status, 'draft');
      expect(await stock.movementsByFarm('f'), isEmpty);
    },
  );
  test(
    'report separates revenue from receipts and stock purchases from expenses',
    () async {
      await post(harvest());
      await post(sale());
      await post(purchase());
      await post(expense());
      await pay();
      final report = TradeReport(
        farm: 'f',
        period: '2026-10',
        documents: await repo.documents('f'),
        lots: await repo.lots('f'),
        payments: await repo.payments('f'),
        cash: await repo.cashBook('f'),
      );
      final book = Excel.decodeBytes(report.bytes());
      expect(book.tables.length, 12);
      final row = book['KET QUA KY'].rows[1];
      expect(row[1]!.value.toString(), '40');
      expect(row[2]!.value.toString(), '20');
      expect(row[5]!.value.toString(), '8');
      expect(row[6]!.value.toString(), '15');
    },
  );
  test('service rejects view-only, expired and narrow-scoped writes', () async {
    final reader = AuthorizationSubject(
      userId: 'r',
      membershipId: 'r',
      farmId: 'f',
      permissionCodes: const {PermissionCodes.financeView},
      dataScopes: const {DataScope.allFarm},
    );
    final read = TradeService(
      repo,
      subject: reader,
      currentSubject: () => reader,
    );
    expect(() => read.create(harvest()), throwsStateError);
    final narrow = AuthorizationSubject(
      userId: 'r',
      membershipId: 'r',
      farmId: 'f',
      permissionCodes: PermissionCodes.values,
      dataScopes: const {DataScope.own},
    );
    expect(
      () => TradeService(
        repo,
        subject: narrow,
        currentSubject: () => narrow,
      ).create(harvest()),
      throwsStateError,
    );
    expect(
      () => TradeService(
        repo,
        subject: admin,
        currentSubject: () => null,
      ).create(harvest()),
      throwsStateError,
    );
    await service.create(harvest());
    expect((await repo.documents('f')).length, 1);
  });
  test('backup rejects lot stock and cash amount tampering', () async {
    await post(harvest());
    await post(sale());
    await pay();
    await TradeIntegrity.validate(db);
    await db.update('trade_lots_v1', {'stock_units': 1}, where: "id='h:0'");
    await expectLater(TradeIntegrity.validate(db), throwsStateError);
    await db.update('trade_lots_v1', {
      'stock_units': 6000000,
    }, where: "id='h:0'");
    await db.update('finance_documents_v2', {'amount_minor': 16});
    await expectLater(TradeIntegrity.validate(db), throwsStateError);
  });
  test(
    'backup rejects orphan trade movement and altered body mirror',
    () async {
      await post(harvest());
      final r = (await db.query('trade_documents_v1')).single;
      final body = SqliteTradeRepository.decode(r['body'])
        ..['currency'] = 'LAK';
      await db.update('trade_documents_v1', {'body': jsonEncode(body)});
      await expectLater(TradeIntegrity.validate(db), throwsStateError);
      await db.update('trade_documents_v1', {'body': r['body']});
      await db.delete('trade_stock_links_v1');
      await expectLater(TradeIntegrity.validate(db), throwsStateError);
    },
  );
  test('Admin issue cost is independent from harvest receipt price', () async {
    await post(harvest(price: '5'));
    await post(
      sale(
        lines: const [
          TradeLine(ref: 'h:0', quantity: '4', price: '10', issuePrice: '6'),
        ],
      ),
    );
    expect(
      ((await saved('s')).snapshots['lines'] as List).single['cost'],
      '24',
    );
    final movement = (await stock.movementsByFarm(
      'f',
    )).firstWhere((m) => m.kind == InventoryMovementKind.issue);
    expect(movement.unitPriceText, '6');
    await TradeIntegrity.validate(db);
  });
  test('LAK lots and invoices remain independent from VND', () async {
    await stock.createProductionPlan(
      const ProductionPlan(
        id: 'lak',
        farmId: 'f',
        parcelId: 'land',
        seasonId: 'season',
        name: 'LAK plan',
        crop: 'Peanut',
        startsOn: '2026-10-01',
        endsOn: '2026-10-31',
        currency: 'LAK',
        materialBudget: '0',
        laborBudget: '0',
        machineBudget: '0',
        laborHours: '0',
        machineShifts: '0',
      ),
      'admin',
    );
    await stock.changeProductionPlanStatus(
      'f',
      'lak',
      0,
      ProductionPlanStatus.active,
      'admin',
    );
    final h = harvest(currency: 'LAK').toJson()..['planId'] = 'lak';
    await post(TradeDraft.fromJson(h));
    await post(sale(currency: 'LAK'));
    await pay(currency: 'LAK');
    expect((await saved('s')).balance, '25');
    expect((await repo.cashBook('f')).single['currency'], 'LAK');
    await TradeIntegrity.validate(db);
  });
  test('failed financial insert rolls back settlement and THU counter', () async {
    await post(harvest());
    await post(sale());
    await db.execute(
      "CREATE TRIGGER fail_trade_cash BEFORE INSERT ON finance_documents_v2 BEGIN SELECT RAISE(ABORT,'fixture failure'); END",
    );
    await expectLater(pay(), throwsA(anything));
    expect(await repo.payments('f'), isEmpty);
    expect((await saved('s')).balance, '40');
    expect(
      await db.query('monthly_document_sequences', where: "kind='THU'"),
      isEmpty,
    );
  });
  test(
    'stale draft cannot post twice and cancelled draft cannot affect stock',
    () async {
      await post(harvest());
      await expectLater(repo.post('f', 'h', 0, 'admin'), throwsStateError);
      await repo.create('f', sale(), 'admin');
      await repo.voidDocument(
        'f',
        's',
        0,
        '2026-10-22',
        'Cancel draft',
        'admin',
      );
      await expectLater(repo.post('f', 's', 1, 'admin'), throwsStateError);
      expect((await repo.lots('f')).single.quantity, '10');
      await TradeIntegrity.validate(db);
    },
  );
  test(
    'pending harvest draft blocks plan close and posted harvest blocks cancellation',
    () async {
      await repo.create('f', harvest(), 'admin');
      await expectLater(
        stock.changeProductionPlanStatus(
          'f',
          'p',
          1,
          ProductionPlanStatus.completed,
          'admin',
        ),
        throwsStateError,
      );
      await repo.post('f', 'h', 0, 'admin');
      await expectLater(
        stock.changeProductionPlanStatus(
          'f',
          'p',
          1,
          ProductionPlanStatus.cancelled,
          'admin',
        ),
        throwsStateError,
      );
      await stock.changeProductionPlanStatus(
        'f',
        'p',
        1,
        ProductionPlanStatus.completed,
        'admin',
      );
    },
  );

  test(
    'same active bank reference cannot be entered twice with different request IDs',
    () async {
      await post(harvest());
      await post(sale());
      await pay();
      await expectLater(
        repo.settle(
          'f',
          'other',
          's',
          '10',
          'VND',
          '2026-10-22',
          'Bank reference pay',
          'admin',
        ),
        throwsStateError,
      );
      expect((await saved('s')).balance, '25');
      expect((await repo.cashBook('f')).length, 1);
    },
  );
  test('expired live session cannot create commercial documents', () async {
    final expired = AuthorizationSubject(
      userId: 'admin',
      membershipId: 'm',
      farmId: 'f',
      permissionCodes: PermissionCodes.values,
      dataScopes: const {DataScope.allFarm},
      validUntil: DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(
      () => TradeService(
        repo,
        subject: admin,
        currentSubject: () => expired,
      ).create(harvest()),
      throwsStateError,
    );
  });
  test(
    'local unit rename updates product projection without changing lot history or stock',
    () async {
      await post(harvest());
      final catalog = CompanyCatalogService(
        repository: SqliteCompanyCatalog(db),
        subject: admin,
      );
      final unit = (await catalog.entries()).firstWhere((e) => e.id == 'unit');
      await catalog.save(
        CatalogEntry(
          id: 'unit',
          farmId: 'f',
          kind: CatalogKind.unit,
          code: unit.code,
          name: 'Kilogram renamed',
        ),
        expectedRevision: unit.revision,
        reason: 'Rename unit',
      );
      final item = (await stock.listByFarm(
        'f',
      )).firstWhere((i) => i.id == 'product');
      expect(item.unit, 'Kilogram renamed');
      expect(item.stock, 10);
      expect((await repo.lots('f')).single.unit, 'unit');
      await TradeIntegrity.validate(db);
    },
  );
}
