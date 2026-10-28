import 'dart:convert';
import 'dart:io';

import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_restore_activation_io.dart';
import 'package:agrico_deepseek/core/migrations/production_v2_test_cleanup.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database primary;
  late Database costs;
  late SqliteInventoryRepository inventory;

  setUp(() async {
    primary = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    costs = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await primary.execute('PRAGMA foreign_keys=ON');
    await primary.execute(
      'CREATE TABLE land_parcels(id TEXT PRIMARY KEY,farm_id TEXT,parcel_code TEXT,active INTEGER,kind TEXT)',
    );
    await primary.insert('land_parcels', {
      'id': 'parcel',
      'farm_id': 'local-farm',
      'parcel_code': 'P1',
      'active': 1,
      'kind': 'fieldPlot',
    });
    await SqliteInventoryRepository.createSchema(primary);
    for (final table in ProductionV2TestCleanup.legacyPrimaryTables) {
      await primary.execute('CREATE TABLE "$table"(id TEXT PRIMARY KEY)');
      await primary.insert(table, {'id': 'legacy-ລາວ-Việt'});
    }
    await costs.execute('CREATE TABLE production_costs(id TEXT PRIMARY KEY)');
    await costs.insert('production_costs', {'id': 'legacy-cost'});
    inventory = SqliteInventoryRepository(primary);
    await inventory.register(
      const InventoryItem(
        id: 'item',
        farmId: 'local-farm',
        code: 'VT1',
        name: 'Material',
        unit: 'kg',
        unitPrice: 12,
        supplier: '',
      ),
    );
    await inventory.record(
      InventoryMovement(
        id: 'receipt',
        farmId: 'local-farm',
        itemId: 'item',
        kind: InventoryMovementKind.receipt,
        quantity: 5,
        occurredAt: DateTime.utc(2026, 10, 25),
      ),
    );
    await primary.execute(
      'CREATE TABLE linked_documents(id TEXT PRIMARY KEY,parcel_id TEXT REFERENCES land_parcels(id),movement_id TEXT REFERENCES inventory_movements_v2(id),amount INTEGER)',
    );
    await primary.insert('linked_documents', {
      'id': 'finance-payroll-trade-link',
      'parcel_id': 'parcel',
      'movement_id': 'receipt',
      'amount': 60,
    });
  });
  tearDown(() async {
    await primary.close();
    await costs.close();
  });

  Future<String> state() async => jsonEncode({
    'backup': base64Encode(
      await LocalDatabaseSnapshot.create(primary, costsDatabase: costs),
    ),
    'schema': await primary.rawQuery(
      "SELECT type,name,sql FROM sqlite_master ORDER BY type,name",
    ),
    'costSchema': await costs.rawQuery(
      "SELECT type,name,sql FROM sqlite_master ORDER BY type,name",
    ),
  });
  Future<void> guard() => ProductionV2TestCleanup.validateStartup(primary);
  Future<void> marker(String phase, {String counts = '{}', String? at}) async {
    await primary.execute('''CREATE TABLE ${ProductionV2TestCleanup.table} (
      id INTEGER PRIMARY KEY,phase TEXT,counts_json TEXT,completed_at TEXT)''');
    await primary.insert(ProductionV2TestCleanup.table, {
      'id': 1,
      'phase': phase,
      'counts_json': counts,
      'completed_at':
          at ?? (phase == 'complete' ? '2026-10-25T00:00:00Z' : null),
    });
  }

  Future<void> unchanged({bool blocked = false}) async {
    final before = await state();
    await primary.execute('PRAGMA query_only=ON');
    try {
      if (blocked) {
        await expectLater(guard(), throwsStateError);
      } else {
        await guard();
        await guard();
      }
    } finally {
      await primary.execute('PRAGMA query_only=OFF');
    }
    expect(await state(), before);
    expect(await primary.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  }

  test(
    'fresh installation does not create a cleanup marker or any schema',
    () async {
      final fresh = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        await fresh.execute('PRAGMA query_only=ON');
        await ProductionV2TestCleanup.validateStartup(fresh);
        expect(
          await fresh.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table'",
          ),
          isEmpty,
        );
      } finally {
        await fresh.close();
      }
    },
  );
  test(
    'missing marker preserves legacy rows stock sequences and linked data on repeated startup',
    () async {
      await unchanged();
      expect((await inventory.listByFarm('local-farm')).single.stock, 5);
      expect(
        (await inventory.movementsByFarm('local-farm')).single.code,
        'NHAP-202610-001',
      );
      expect(await primary.query('linked_documents'), hasLength(1));
    },
  );
  test(
    'valid empty marker schema continues without schema or data writes',
    () async {
      await marker('complete');
      await primary.delete(ProductionV2TestCleanup.table);
      await unchanged();
    },
  );
  for (final schema in [
    'unrelated TEXT',
    'id INTEGER PRIMARY KEY,phase INTEGER,counts_json TEXT,completed_at TEXT',
    'id INTEGER,phase TEXT,counts_json TEXT,completed_at TEXT',
  ]) {
    test('malformed empty marker schema fails closed: $schema', () async {
      await primary.execute(
        'CREATE TABLE ${ProductionV2TestCleanup.table}($schema)',
      );
      expect(await primary.query(ProductionV2TestCleanup.table), isEmpty);
      await unchanged(blocked: true);
    });
  }
  test(
    'completed historical cutover preserves newly entered and legacy data',
    () async {
      await marker('complete', counts: '{"fields":3}');
      await unchanged();
    },
  );
  test(
    'interrupted main_done is blocked without clearing cost DB or updating marker',
    () async {
      await marker('main_done');
      await unchanged(blocked: true);
      expect(await costs.query('production_costs'), hasLength(1));
      expect(
        (await primary.query(ProductionV2TestCleanup.table)).single['phase'],
        'main_done',
      );
    },
  );
  for (final invalid in [
    ('unknown phase', 'unknown', '{}', '2026-10-25T00:00:00Z'),
    ('bad JSON', 'complete', '{bad', '2026-10-25T00:00:00Z'),
    ('negative counts', 'complete', '{"fields":-1}', '2026-10-25T00:00:00Z'),
    ('wrong counts type', 'complete', '[]', '2026-10-25T00:00:00Z'),
    ('invalid timestamp', 'complete', '{}', 'not-a-date'),
  ]) {
    test('invalid marker ${invalid.$1} fails closed without writes', () async {
      await marker(invalid.$2, counts: invalid.$3, at: invalid.$4);
      await unchanged(blocked: true);
    });
  }
  test('multiple marker rows fail closed', () async {
    await marker('complete');
    await primary.insert(ProductionV2TestCleanup.table, {
      'id': 2,
      'phase': 'complete',
      'counts_json': '{}',
      'completed_at': '2026-10-25T00:00:00Z',
    });
    await unchanged(blocked: true);
  });
  test(
    'malformed marker schema fails closed without touching either business DB',
    () async {
      await primary.execute(
        'CREATE TABLE ${ProductionV2TestCleanup.table}(id INTEGER)',
      );
      await primary.insert(ProductionV2TestCleanup.table, {'id': 1});
      await unchanged(blocked: true);
    },
  );
  test(
    'explicit reset helper rejects unconfirmed datasets before any schema or data write',
    () async {
      final before = await state();
      await expectLater(
        ProductionV2TestCleanup.run(
          primary: primary,
          legacyCosts: costs,
          farmId: 'local-farm',
          confirmedDisposableTestData: false,
        ),
        throwsStateError,
      );
      expect(await state(), before);
    },
  );
  test(
    'V2 production data with no marker is preserved and never triggers a reset',
    () async {
      await primary.insert('production_seasons_v2', {
        'id': 'season',
        'farm_id': 'local-farm',
        'parcel_id': 'parcel',
        'name': 'Season',
        'starts_on': '2026-10-25',
        'active': 1,
      });
      await unchanged();
    },
  );
  test(
    'bootstrap wires the read-only guard before module creation and has no reset call',
    () {
      final source = File(
        'lib/app_v2/agrico_v2_composition.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('ProductionV2TestCleanup.run(')));
      expect(
        source.indexOf('ProductionV2TestCleanup.validateStartup(database)'),
        allOf(
          greaterThan(0),
          lessThan(
            source.indexOf(
              'final spatial = SpatialPersistenceComposition(database)',
            ),
          ),
        ),
      );
    },
  );

  test(
    'legacy backup restore and repeated file reopen retain rows and links without a marker',
    () async {
      final dir = await Directory.systemTemp.createTemp('agrico-w1-restore-');
      Database? db, costDb;
      try {
        db = await databaseFactoryFfi.openDatabase('${dir.path}/agrico.db');
        costDb = await databaseFactoryFfi.openDatabase(
          '${dir.path}/agrico_costs.db',
        );
        await db.execute('CREATE TABLE fields(id TEXT PRIMARY KEY,name TEXT)');
        await db.execute(
          'CREATE TABLE production_seasons(id TEXT PRIMARY KEY,field_id TEXT REFERENCES fields(id))',
        );
        await costDb.execute(
          'CREATE TABLE production_costs(id TEXT PRIMARY KEY,season_id TEXT,amount INTEGER)',
        );
        await db.insert('fields', {'id': 'field', 'name': 'Lô đất ລາວ'});
        await db.insert('production_seasons', {
          'id': 'season',
          'field_id': 'field',
        });
        await costDb.insert('production_costs', {
          'id': 'cost',
          'season_id': 'season',
          'amount': 123,
        });
        final bytes = await LocalDatabaseSnapshot.create(
          db,
          costsDatabase: costDb,
        );
        await db.close();
        db = null;
        await costDb.close();
        costDb = null;
        final activation = LocalRestoreActivation(dir, databaseFactoryFfi);
        await activation.schedule(bytes);
        expect(await activation.applyPending(), isTrue);
        for (var launch = 0; launch < 2; launch++) {
          db = await databaseFactoryFfi.openDatabase('${dir.path}/agrico.db');
          costDb = await databaseFactoryFfi.openDatabase(
            '${dir.path}/agrico_costs.db',
          );
          await ProductionV2TestCleanup.validateStartup(db);
          expect((await db.query('fields')).single['name'], 'Lô đất ລາວ');
          expect(
            (await db.query('production_seasons')).single['field_id'],
            'field',
          );
          expect(
            (await costDb.query('production_costs')).single['amount'],
            123,
          );
          await db.close();
          db = null;
          await costDb.close();
          costDb = null;
        }
      } finally {
        await db?.close();
        await costDb?.close();
        // Only this test's freshly created synthetic sandbox is removed.
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'restart after a synthetic cross-file crash never resumes destructive cost deletion',
    () async {
      final dir = await Directory.systemTemp.createTemp('agrico-w1-crash-');
      Database? db, costDb;
      try {
        db = await databaseFactoryFfi.openDatabase('${dir.path}/agrico.db');
        costDb = await databaseFactoryFfi.openDatabase(
          '${dir.path}/agrico_costs.db',
        );
        await db.execute(
          'CREATE TABLE ${ProductionV2TestCleanup.table}(id INTEGER PRIMARY KEY,phase TEXT,counts_json TEXT,completed_at TEXT)',
        );
        await db.insert(ProductionV2TestCleanup.table, {
          'id': 1,
          'phase': 'main_done',
          'counts_json': '{"fields":1}',
          'completed_at': null,
        });
        await costDb.execute(
          'CREATE TABLE production_costs(id TEXT PRIMARY KEY)',
        );
        await costDb.insert('production_costs', {'id': 'not-yet-cleared'});
        await db.close();
        db = null;
        await costDb.close();
        costDb = null;
        for (var launch = 0; launch < 2; launch++) {
          db = await databaseFactoryFfi.openDatabase('${dir.path}/agrico.db');
          costDb = await databaseFactoryFfi.openDatabase(
            '${dir.path}/agrico_costs.db',
          );
          await expectLater(
            ProductionV2TestCleanup.validateStartup(db),
            throwsStateError,
          );
          expect(
            (await db.query(ProductionV2TestCleanup.table)).single['phase'],
            'main_done',
          );
          expect(
            (await costDb.query('production_costs')).single['id'],
            'not-yet-cleared',
          );
          await db.close();
          db = null;
          await costDb.close();
          costDb = null;
        }
      } finally {
        await db?.close();
        await costDb?.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
