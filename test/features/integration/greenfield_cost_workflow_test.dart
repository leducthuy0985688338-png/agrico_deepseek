import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/production/source_governance.dart';
import 'package:agrico_deepseek/core/periods/period_lock.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/features/integration/domain/production_cost_workflow.dart';
import 'package:agrico_deepseek/features/integration/domain/production_cost_entry.dart';
import 'package:agrico_deepseek/features/integration/application/production_cost_workflow_service.dart';
import 'package:agrico_deepseek/features/integration/application/integration_service.dart';
import 'package:agrico_deepseek/features/integration/application/production_cost_projection.dart';
import 'package:agrico_deepseek/features/integration/application/production_cost_export.dart';
import 'package:agrico_deepseek/features/integration/data/integration_repository.dart';
import 'package:agrico_deepseek/features/integration/data/production_cost_workflow_repository.dart';
import 'package:agrico_deepseek/features/trade/data/sqlite_trade_repository.dart';
import 'package:agrico_deepseek/features/trade/domain/trade.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late ProductionCostWorkflowRepository repo;
  final admin = AuthorizationSubject(
    userId: 'approver',
    membershipId: 'm',
    farmId: 'f',
    permissionCodes: PermissionCodes.values,
    dataScopes: const {DataScope.allFarm},
  );
  late AuthorizationSubject? live;
  late ProductionCostWorkflowService service;
  setUp(() async {
    live = admin;
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys=ON');
    await db.execute(
      'CREATE TABLE land_parcels(id TEXT PRIMARY KEY,farm_id TEXT,active INTEGER,parcel_code TEXT)',
    );
    await db.execute(
      'CREATE TABLE production_plans_v1(id TEXT PRIMARY KEY,farm_id TEXT,parcel_id TEXT,season_id TEXT,currency TEXT,starts_on TEXT,ends_on TEXT,status TEXT,code TEXT)',
    );
    await db.execute(
      'CREATE TABLE company_catalog_entries_v1(id TEXT PRIMARY KEY,farm_id TEXT,kind TEXT,name TEXT,code TEXT,active INTEGER)',
    );
    await db.execute(
      'CREATE TABLE inventory_movements_v2(id TEXT PRIMARY KEY,farm_id TEXT,code TEXT,item_id TEXT,warehouse_id TEXT,kind TEXT,plan_id TEXT,quantity_units INTEGER,unit_price_text TEXT,amount_text TEXT,currency TEXT,priced_by TEXT,occurred_at TEXT,zero_price_confirmed INTEGER)',
    );
    await db.execute(
      'CREATE TABLE production_material_costs_v2(movement_id TEXT PRIMARY KEY,farm_id TEXT,item_id TEXT,parcel_id TEXT,season_id TEXT,plan_id TEXT,quantity_units INTEGER,unit_price_text TEXT,amount_text TEXT,currency TEXT,priced_by TEXT,occurred_at TEXT,zero_price_confirmed INTEGER)',
    );
    await SqliteTradeRepository.createSchema(db);
    await SqliteFinanceDocumentRepository.createSchema(db);
    for (final name in ProductionCostProjection.requiredTables) {
      if ((await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [name],
      )).isEmpty) {
        await db.execute(
          'CREATE TABLE $name(id TEXT PRIMARY KEY,farm_id TEXT)',
        );
      }
    }
    await IntegrationRepository.createSchema(db);
    await db.insert('land_parcels', {
      'id': 'parcel',
      'farm_id': 'f',
      'active': 1,
      'parcel_code': 'LO-A',
    });
    for (final pair in [
      ('a', 'VND'),
      ('b', 'VND'),
      ('c', 'VND'),
      ('lak', 'LAK'),
    ]) {
      await db.insert('production_plans_v1', {
        'id': pair.$1,
        'farm_id': 'f',
        'parcel_id': 'parcel',
        'season_id': 'season',
        'currency': pair.$2,
        'starts_on': '2026-10-01',
        'ends_on': '2026-12-31',
        'status': 'active',
        'code': pair.$1,
      });
    }
    await db.insert('company_catalog_entries_v1', {
      'id': 'supplier',
      'farm_id': 'f',
      'kind': 'supplier',
      'name': 'Synthetic supplier',
      'code': 'SUP-1',
      'active': 1,
    });
    repo = ProductionCostWorkflowRepository(db);
    service = ProductionCostWorkflowService(
      repo,
      IntegrationService(
        repository: IntegrationRepository(db),
        subject: admin,
        currentSubject: () => live,
        productionCosts: repo,
      ),
    );
  });
  tearDown(() async {
    await db.close();
  });

  Future<void> issue() async {
    final m = <String, Object?>{
      'id': 'issue',
      'farm_id': 'f',
      'code': 'XK-1',
      'item_id': 'item',
      'warehouse_id': 'wh',
      'kind': 'issue',
      'plan_id': 'a',
      'quantity_units': 1500000,
      'unit_price_text': '2',
      'amount_text': '3',
      'currency': 'VND',
      'priced_by': 'price-admin',
      'occurred_at': '2026-10-20T01:00:00Z',
      'zero_price_confirmed': 0,
    };
    final c =
        <String, Object?>{
            ...m,
            'movement_id': 'issue',
            'parcel_id': 'parcel',
            'season_id': 'season',
          }
          ..remove('id')
          ..remove('kind')
          ..remove('code')
          ..remove('warehouse_id');
    await db.transaction((tx) async {
      await tx.insert('inventory_movements_v2', m);
      await tx.insert('production_material_costs_v2', c);
      await SourceGovernance.register(
        tx,
        farm: 'f',
        type: 'material',
        id: 'issue',
        day: '2026-10-20',
        actor: 'creator',
        payload: SourceGovernance.material(m, c),
      );
    });
  }

  Future<void> expense({
    String id = 'expense',
    String amount = '1',
    String currency = 'VND',
    bool direct = false,
    String day = '2026-10-20',
  }) async {
    final trade = SqliteTradeRepository(db);
    await trade.create(
      'f',
      TradeDraft(
        id: id,
        kind: TradeKind.expense,
        day: day,
        currency: currency,
        rounding: MoneyRounding.halfUp,
        partyId: 'supplier',
        planId: direct ? (currency == 'VND' ? 'a' : 'lak') : null,
        dueOn: '2026-10-21',
        reference: 'invoice-$id',
        expenseTreatment: direct ? 'directProduction' : 'commonProduction',
        lines: [
          TradeLine(
            ref: '',
            label: 'Synthetic expense',
            quantity: '1',
            price: amount,
          ),
        ],
      ),
      'creator',
    );
    await trade.post('f', id, 0, 'poster');
  }

  ExpenseAllocationProposal proposal({
    String id = 'expense',
    CostAllocationDriver driver = CostAllocationDriver.approvedWeights,
    int base = 3,
    int scale = 2,
    List<String> plans = const ['a', 'b', 'c'],
  }) => ExpenseAllocationProposal(
    expenseId: id,
    driver: driver,
    baseUnits: base,
    moneyScale: scale,
    weights: plans
        .map(
          (p) => CostAllocationWeight(p, 1, 'approved synthetic basis for $p'),
        )
        .toList(),
  );
  Future<ProductionCostProjection> projection() => IntegrationRepository(
    db,
  ).snapshot('f', '2026-10').then(ProductionCostProjection.new);

  test(
    'fresh and repeated schema creation preserves existing test rows without backfill',
    () async {
      await issue();
      final before = await db.query('inventory_movements_v2');
      await IntegrationRepository.createSchema(db);
      await IntegrationRepository.createSchema(db);
      expect(await db.query('inventory_movements_v2'), before);
      expect((await db.query(SourceGovernance.versions)).single['revision'], 1);
      await ProductionCostWorkflowRepository.validate(db);
    },
  );
  test(
    'material requires real approval and binds exact payload revision',
    () async {
      await issue();
      expect(
        (await projection()).entries.single.eligibility,
        CostEligibility.pending,
      );
      await service.approveMaterial('issue', 1);
      final e = (await projection()).entries.single;
      expect(e.eligibility, CostEligibility.eligible);
      expect(e.amountExact, '3');
      expect(e.sourceRevision, 2);
      expect(e.createdBy, 'creator');
      expect(e.approvedBy, 'approver');
      await service.approveMaterial('issue', 1);
      expect((await db.query(SourceGovernance.audit)).length, 2);
      expect((await db.query('production_material_costs_v2')).length, 1);
    },
  );
  test('stale material revision cannot approve', () async {
    await issue();
    await expectLater(service.approveMaterial('issue', 0), throwsStateError);
    expect(
      (await db.query(SourceGovernance.versions)).single['status'],
      'draft',
    );
  });
  test('material payload mutation cannot reuse approval', () async {
    await issue();
    await db.update('inventory_movements_v2', {'amount_text': '4'});
    await expectLater(service.approveMaterial('issue', 1), throwsStateError);
    expect(
      (await projection()).entries.single.issues,
      contains('approvedPayloadDigestMismatch'),
    );
  });
  test('source audit and approved metadata are immutable', () async {
    await issue();
    await service.approveMaterial('issue', 1);
    await expectLater(
      db.update(SourceGovernance.audit, {'actor_id': 'fake'}),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.update(SourceGovernance.versions, {'approver': 'fake'}),
      throwsA(isA<DatabaseException>()),
    );
  });
  test(
    'direct expense is one native Trade source and one approved plan allocation',
    () async {
      await expense(direct: true, amount: '800000');
      await service.proposeExpense(
        proposal(
          driver: CostAllocationDriver.direct,
          base: 1,
          scale: 0,
          plans: ['a'],
        ),
      );
      expect(
        (await projection()).entries.single.eligibility,
        CostEligibility.pending,
      );
      await service.approveExpense('expense', 1);
      await service.approveExpense('expense', 1);
      expect(
        (await db.query(
          ProductionCostWorkflowRepository.costs,
        )).single['amount'],
        '800000',
      );
      expect(
        (await projection()).entries.single.eligibility,
        CostEligibility.eligible,
      );
      expect((await db.query('trade_documents_v1')).length, 1);
    },
  );
  for (final driver in [
    CostAllocationDriver.area,
    CostAllocationDriver.machineMinutes,
    CostAllocationDriver.laborMinutes,
    CostAllocationDriver.approvedWeights,
  ]) {
    test(
      'explicit ${driver.name} policy conserves fractional residue',
      () async {
        await expense();
        await service.proposeExpense(proposal(driver: driver));
        expect(await db.query(ProductionCostWorkflowRepository.costs), isEmpty);
        await service.approveExpense('expense', 1);
        final costs = await db.query(
          ProductionCostWorkflowRepository.costs,
          orderBy: 'plan_id',
        );
        expect(costs.map((r) => r['amount']).toList(), [
          '0.34',
          '0.33',
          '0.33',
        ]);
        expect(
          (await projection())
              .groups()
              .firstWhere((g) => g.currency == 'VND')
              .totalCost,
          '1',
        );
        await ProductionCostWorkflowRepository.validate(db);
      },
    );
  }
  test('no policy means no automatic overhead allocation', () async {
    await expense();
    expect(await db.query(ProductionCostWorkflowRepository.costs), isEmpty);
    expect(
      (await projection()).entries.single.eligibility,
      CostEligibility.incomplete,
    );
  });
  test(
    'malformed approval metadata fails restore validation and direct projection',
    () async {
      await issue();
      await service.approveMaterial('issue', 1);
      await SourceGovernance.removeStorageGuardsForRestore(db);
      await db.update(SourceGovernance.versions, {
        'approver': '',
        'approved_at': 'bad',
      });
      await db.update(
        SourceGovernance.audit,
        {'actor_id': '', 'occurred_at': 'bad'},
        where: 'action=?',
        whereArgs: ['approve'],
      );
      await expectLater(
        ProductionCostWorkflowRepository.validate(db),
        throwsStateError,
      );
      expect(
        (await projection()).entries.single.eligibility,
        CostEligibility.incomplete,
      );
    },
  );
  test(
    'native posted expense mutation cannot enter a new allocation approval',
    () async {
      await expense();
      await db.update(
        'trade_documents_v1',
        {'total': '2'},
        where: 'id=?',
        whereArgs: ['expense'],
      );
      await expectLater(service.proposeExpense(proposal()), throwsStateError);
      expect(
        await db.query(ProductionCostWorkflowRepository.policies),
        isEmpty,
      );
    },
  );
  test(
    'reversal date is sealed by actual correction approval, not merely its format',
    () async {
      await expense();
      await service.proposeExpense(proposal());
      await service.approveExpense('expense', 1);
      await SqliteTradeRepository(db).voidDocument(
        'f',
        'expense',
        1,
        '2026-10-21',
        'Authorized correction',
        'corrector',
      );
      await db.update(
        'trade_documents_v1',
        {'void_day': '2026-10-22'},
        where: 'id=?',
        whereArgs: ['expense'],
      );
      await expectLater(
        ProductionCostWorkflowRepository.validate(db),
        throwsStateError,
      );
      final p = await projection();
      expect(
        p.entries
            .where((e) => e.sourceType == 'expenseReversal')
            .every(
              (e) =>
                  e.eligibility == CostEligibility.incomplete &&
                  e.issues.contains('approvedPayloadDigestMismatch'),
            ),
        isTrue,
      );
      expect(
        p.groups().firstWhere((g) => g.currency == 'VND').totalCost,
        isNull,
      );
    },
  );
  test(
    'cross-period partial reversal fails closed without modifying the source',
    () async {
      await db.update('production_plans_v1', {'starts_on': '2026-09-01'});
      await expense(amount: '100', day: '2026-09-20');
      await service.proposeExpense(proposal(base: 4, plans: ['a', 'b']));
      await service.approveExpense('expense', 1);
      await expectLater(
        SqliteTradeRepository(db).voidDocument(
          'f',
          'expense',
          1,
          '2026-10-21',
          'Unsupported partial timing',
          'corrector',
        ),
        throwsStateError,
      );
      expect((await db.query('trade_documents_v1')).single['status'], 'posted');
    },
  );
  test(
    'fully allocated reversal belongs to its actual correction month',
    () async {
      await db.update('production_plans_v1', {'starts_on': '2026-09-01'});
      await expense(day: '2026-09-20');
      await service.proposeExpense(proposal());
      await service.approveExpense('expense', 1);
      await SqliteTradeRepository(db).voidDocument(
        'f',
        'expense',
        1,
        '2026-10-21',
        'Correct in open period',
        'corrector',
      );
      final p = await projection();
      expect(p.entries.every((e) => e.sourceType == 'expenseReversal'), isTrue);
      expect(p.groups().firstWhere((g) => g.currency == 'VND').totalCost, '-1');
    },
  );
  test(
    'unapproved allocation can be voided without leaving a phantom pending cost',
    () async {
      await expense();
      await service.proposeExpense(proposal());
      await SqliteTradeRepository(db).voidDocument(
        'f',
        'expense',
        1,
        '2026-10-21',
        'Replace erroneous proposal',
        'corrector',
      );
      final p = await projection();
      expect(p.entries.single.eligibility, CostEligibility.voided);
      expect(p.groups().firstWhere((g) => g.currency == 'VND').totalCost, '0');
    },
  );
  test(
    'partial approved allocation can be cancelled in its open source period',
    () async {
      await expense(amount: '100');
      await service.proposeExpense(proposal(base: 4, plans: ['a', 'b']));
      await service.approveExpense('expense', 1);
      await SqliteTradeRepository(db).voidDocument(
        'f',
        'expense',
        1,
        '2026-10-21',
        'Cancel partial allocation before replacement',
        'corrector',
      );
      final p = await projection();
      expect(
        p.entries.where((e) => e.sourceType == 'productionExpenseUnallocated'),
        isEmpty,
      );
      expect(p.groups().firstWhere((g) => g.currency == 'VND').totalCost, '0');
    },
  );
  test('zero base, over-allocation and duplicate plans are rejected', () async {
    await expense();
    for (final p in [
      proposal(base: 0),
      proposal(base: 2),
      proposal(plans: ['a', 'a', 'b']),
    ]) {
      await expectLater(service.proposeExpense(p), throwsFormatException);
    }
    expect(await db.query(ProductionCostWorkflowRepository.policies), isEmpty);
  });
  test(
    'partial allocation exposes remainder without inventing destination',
    () async {
      await expense(amount: '100');
      await service.proposeExpense(proposal(base: 4, plans: ['a', 'b']));
      await service.approveExpense('expense', 1);
      final p = await projection();
      expect(
        p.entries
            .singleWhere((e) => e.sourceType == 'productionExpenseUnallocated')
            .amountExact,
        '50',
      );
      expect(
        p.groups().firstWhere((g) => g.currency == 'VND').totalCost,
        isNull,
      );
    },
  );
  test(
    'unknown inactive and wrong-currency plans cannot receive costs',
    () async {
      await expense();
      for (final target in ['missing', 'lak']) {
        await expectLater(
          service.proposeExpense(proposal(base: 1, plans: [target])),
          throwsStateError,
        );
      }
      await db.update(
        'production_plans_v1',
        {'status': 'closed'},
        where: 'id=?',
        whereArgs: ['a'],
      );
      await expectLater(
        service.proposeExpense(proposal(base: 1, plans: ['a'])),
        throwsStateError,
      );
    },
  );
  test(
    'plan loses eligibility before approval: rollback leaves zero costs',
    () async {
      await expense();
      await service.proposeExpense(proposal());
      await db.update(
        'production_plans_v1',
        {'status': 'closed'},
        where: 'id=?',
        whereArgs: ['b'],
      );
      await expectLater(service.approveExpense('expense', 1), throwsStateError);
      expect(await db.query(ProductionCostWorkflowRepository.costs), isEmpty);
    },
  );
  test(
    'replayed proposal cannot change approved financial configuration',
    () async {
      await expense();
      await service.proposeExpense(proposal());
      await service.proposeExpense(proposal());
      await service.approveExpense('expense', 1);
      await expectLater(
        service.proposeExpense(proposal(base: 4)),
        throwsStateError,
      );
      expect(
        (await db.query(ProductionCostWorkflowRepository.costs)).length,
        3,
      );
    },
  );
  test('concurrent approval replay cannot duplicate child costs', () async {
    await expense();
    await service.proposeExpense(proposal());
    await Future.wait([
      service.approveExpense('expense', 1),
      service.approveExpense('expense', 1),
    ]);
    expect((await db.query(ProductionCostWorkflowRepository.costs)).length, 3);
  });
  test(
    'expense void creates separately dated negative allocations without rewriting original',
    () async {
      await expense();
      await service.proposeExpense(proposal());
      await service.approveExpense('expense', 1);
      final original = await db.query(ProductionCostWorkflowRepository.costs);
      await SqliteTradeRepository(db).voidDocument(
        'f',
        'expense',
        1,
        '2026-10-21',
        'Synthetic reversal',
        'corrector',
      );
      final p = await projection();
      expect(
        p.entries.where((e) => e.sourceType == 'expenseReversal').length,
        3,
      );
      expect(p.groups().firstWhere((g) => g.currency == 'VND').totalCost, '0');
      expect(await db.query(ProductionCostWorkflowRepository.costs), original);
    },
  );
  test(
    'LAK and VND with more than fifteen digits retain independent exact totals',
    () async {
      await expense(id: 'vnd', amount: '9007199254740991');
      await expense(
        id: 'lakExpense',
        amount: '1200000',
        currency: 'LAK',
        direct: true,
      );
      await service.proposeExpense(proposal(id: 'vnd'));
      await service.proposeExpense(
        proposal(
          id: 'lakExpense',
          driver: CostAllocationDriver.direct,
          base: 1,
          plans: ['lak'],
        ),
      );
      await service.approveExpense('vnd', 1);
      await service.approveExpense('lakExpense', 1);
      final p = await projection();
      expect(
        p.groups().firstWhere((g) => g.currency == 'VND').totalCost,
        '9007199254740991',
      );
      expect(
        p.groups().firstWhere((g) => g.currency == 'LAK').totalCost,
        '1200000',
      );
      final book = Excel.createExcel();
      ProductionCostExport.append(book, p);
      book.delete('Sheet1');
      final bytes = book.encode()!;
      final read = Excel.decodeBytes(bytes);
      final headers = read.tables[ProductionCostExport.tabs.first]!.rows.first
          .map((c) => c!.value.toString())
          .toList();
      expect(
        headers,
        containsAll([
          'Approved payload digest',
          'Allocation driver',
          'Weight evidence',
        ]),
      );
      expect(read.tables.length, 5);
      final dir = Platform.environment['AGRICO_GREENFIELD_EVIDENCE_DIR'];
      if (dir != null) {
        File(
          '$dir/greenfield-v2-exact-five-sheets.xlsx',
        ).writeAsBytesSync(bytes);
      }
    },
  );
  test(
    'logout wrong membership or missing approval permission blocks all writes',
    () async {
      await issue();
      live = null;
      await expectLater(service.approveMaterial('issue', 1), throwsStateError);
      live = AuthorizationSubject(
        userId: 'approver',
        membershipId: 'changed',
        farmId: 'f',
        permissionCodes: PermissionCodes.values,
        dataScopes: const {DataScope.allFarm},
      );
      await expectLater(service.approveMaterial('issue', 1), throwsStateError);
      live = AuthorizationSubject(
        userId: 'approver',
        membershipId: 'm',
        farmId: 'f',
        permissionCodes: {...PermissionCodes.values}
          ..remove(PermissionCodes.financeApprove),
        dataScopes: const {DataScope.allFarm},
      );
      await expectLater(service.approveMaterial('issue', 1), throwsStateError);
      expect(
        (await db.query(SourceGovernance.versions)).single['status'],
        'draft',
      );
    },
  );
  test(
    'revocation inside transaction rolls back source approval and audit',
    () async {
      await issue();
      var calls = 0;
      await expectLater(
        repo.approveMaterial('f', 'issue', 1, 'actor', () {
          if (++calls == 2) throw StateError('Revoked');
        }),
        throwsStateError,
      );
      expect(
        (await db.query(SourceGovernance.versions)).single['status'],
        'draft',
      );
      expect((await db.query(SourceGovernance.audit)).length, 1);
    },
  );
  test(
    'period locks reject approval and offline-late proposals without partial writes',
    () async {
      await issue();
      await expense();
      await db.insert(PeriodLock.states, {
        'farm_id': 'f',
        'period': '2026-10',
        'revision': 1,
        'status': 'closed',
        'event_id': 'synthetic-close',
      });
      await expectLater(
        service.approveMaterial('issue', 1),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        service.proposeExpense(proposal()),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        await db.query(ProductionCostWorkflowRepository.policies),
        isEmpty,
      );
    },
  );
  test(
    'SQLite upgrade preserves unversioned test source and does not invent approval',
    () async {
      final upgrade = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      addTearDown(upgrade.close);
      await upgrade.execute(
        'CREATE TABLE test_source(id TEXT PRIMARY KEY,amount TEXT)',
      );
      await upgrade.insert('test_source', {
        'id': 'existing-test',
        'amount': '123.45',
      });
      await ProductionCostWorkflowRepository.createSchema(upgrade);
      expect((await upgrade.query('test_source')).single['amount'], '123.45');
      expect(await upgrade.query(SourceGovernance.versions), isEmpty);
    },
  );
  test(
    'backup contains native source approval audit and exact allocations',
    () async {
      await expense();
      await service.proposeExpense(proposal());
      await service.approveExpense('expense', 1);
      final bytes = await LocalDatabaseSnapshot.create(db);
      final tables =
          LocalDatabaseSnapshot.decodeDatabases(bytes)['agrico.db']!['tables']
              as Map;
      expect(
        (tables[SourceGovernance.audit] as List)
            .where((r) => r['source_type'] == 'expenseAllocation')
            .length,
        2,
      );
      expect(
        (tables[SourceGovernance.audit] as List)
            .where((r) => r['source_type'] == 'tradeExpense')
            .length,
        2,
      );
      expect(
        (tables[ProductionCostWorkflowRepository.costs] as List).length,
        3,
      );
      final before = await db.query(ProductionCostWorkflowRepository.costs);
      await ProductionCostWorkflowRepository.validate(db);
      expect(await db.query(ProductionCostWorkflowRepository.costs), before);
    },
  );
}
