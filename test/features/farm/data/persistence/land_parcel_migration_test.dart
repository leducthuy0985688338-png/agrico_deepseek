import 'dart:convert';

import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  });

  tearDown(() => database.close());

  /// Creates the pre-P02A shape of `land_parcels`.
  Future<void> createLegacySchema(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS land_parcels (
        id TEXT PRIMARY KEY,
        farm_id TEXT NOT NULL,
        parcel_code TEXT NOT NULL,
        active INTEGER NOT NULL,
        boundary_version INTEGER NOT NULL,
        schema_version INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        UNIQUE(farm_id, parcel_code)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS land_parcel_boundary_versions (
        id TEXT PRIMARY KEY,
        parcel_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        schema_version INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        UNIQUE(parcel_id, version)
      )
    ''');
  }

  Map<String, Object?> legacyPayload({
    String id = 'legacy-1',
    String code = 'AGR-NONG-L001',
    String? parcelLayer,
    String? parentLandBlockId,
    String name = 'Lô ກະສິກຳ',
  }) => {
    'id': id,
    'farmId': 'farm-1',
    'parcelCode': code,
    'name': name,
    'active': true,
    'spatialFeatureId': null,
    'countryCode': null,
    'provinceCode': null,
    'districtCode': null,
    'villageCode': null,
    'createdAt': '2026-09-30T06:00:00.000Z',
    'createdBy': 'member-1',
    'updatedAt': '2026-09-30T06:00:00.000Z',
    'updatedBy': 'member-1',
    'schemaVersion': 2,
    'boundary': [
      {'latitude': 16.5, 'longitude': 104.7, 'altitudeM': null},
      {'latitude': 16.5, 'longitude': 104.701, 'altitudeM': null},
      {'latitude': 16.501, 'longitude': 104.7, 'altitudeM': null},
    ],
    'centroid': {'latitude': 16.5003, 'longitude': 104.7003, 'altitudeM': null},
    'areaM2': 1000.0,
    'areaHa': 0.1,
    'perimeterM': 150.0,
    'boundarySource': 'gps',
    'horizontalAccuracyM': null,
    'measuredAt': null,
    'measuredBy': null,
    'verificationStatus': 'measured',
    'boundaryConfidence': null,
    'boundaryVersion': 1,
    'legacyMetadata': {
      if (parcelLayer != null) 'parcelLayer': parcelLayer,
      if (parentLandBlockId != null) 'parentLandBlockId': parentLandBlockId,
      'crop': 'Lúa',
    },
  };

  Future<void> insertLegacyParcel(
    Database db,
    Map<String, Object?> payload,
  ) async {
    await db.insert('land_parcels', {
      'id': payload['id'],
      'farm_id': payload['farmId'],
      'parcel_code': payload['parcelCode'],
      'active': 1,
      'boundary_version': 1,
      'schema_version': 2,
      'payload_json': jsonEncode(payload),
    });
    await db.insert('land_parcel_boundary_versions', {
      'id': '${payload['id']}-boundary-1',
      'parcel_id': payload['id'],
      'version': 1,
      'schema_version': 2,
      'payload_json': jsonEncode({
        'id': '${payload['id']}-boundary-1',
        'parcelId': payload['id'],
        'version': 1,
        'boundary': payload['boundary'],
        'centroid': payload['centroid'],
        'areaM2': payload['areaM2'],
        'areaHa': payload['areaHa'],
        'perimeterM': payload['perimeterM'],
        'source': payload['boundarySource'],
        'verificationStatus': payload['verificationStatus'],
        'horizontalAccuracyM': null,
        'boundaryConfidence': null,
        'occurredAt': '2026-09-30T06:00:00.000Z',
        'actorMembershipId': 'member-1',
        'note': null,
        'sourceFileName': null,
        'sourceFileHash': null,
      }),
    });
  }

  group('migration on old database', () {
    test('adds typed columns and backfills kind from metadata', () async {
      await createLegacySchema(database);
      // Parent land block.
      await insertLegacyParcel(
        database,
        legacyPayload(
          id: 'legacy-block',
          code: 'AGR-NONG-L001',
          name: 'Lô cha',
          parcelLayer: 'landBlock',
        ),
      );
      // Field plot with valid parent.
      await insertLegacyParcel(
        database,
        legacyPayload(
          id: 'legacy-plot',
          code: 'AGR-NONG-T001',
          name: 'Thửa con',
          parcelLayer: 'fieldPlot',
          parentLandBlockId: 'legacy-block',
        ),
      );

      await database.transaction((txn) async {
        await SqliteLandParcelRepository.migrateAddTypedColumns(txn);
      });

      final rows = await database.query('land_parcels', orderBy: 'id');
      expect(rows, hasLength(2));
      final block = rows.firstWhere((r) => r['id'] == 'legacy-block');
      final plot = rows.firstWhere((r) => r['id'] == 'legacy-plot');
      expect(block['kind'], 'landBlock');
      expect(block['parent_block_id'], isNull);
      expect(plot['kind'], 'fieldPlot');
      expect(plot['parent_block_id'], 'legacy-block');
      expect(plot['project_id'], isNull);
    });

    test('missing parcelLayer falls back to landBlock', () async {
      await createLegacySchema(database);
      await insertLegacyParcel(database, legacyPayload());

      await database.transaction((txn) async {
        await SqliteLandParcelRepository.migrateAddTypedColumns(txn);
      });

      final rows = await database.query('land_parcels');
      expect(rows.single['kind'], 'landBlock');
      expect(rows.single['parent_block_id'], isNull);
    });

    test('unknown parcelLayer value aborts migration', () async {
      await createLegacySchema(database);
      await insertLegacyParcel(
        database,
        legacyPayload(parcelLayer: 'weird'),
      );

      await expectLater(
        () => database.transaction((txn) async {
          await SqliteLandParcelRepository.migrateAddTypedColumns(txn);
        }),
        throwsA(isA<FormatException>()),
      );

      // Rollback: original row untouched, no ledger, no new columns.
      final cols = await database.rawQuery('PRAGMA table_info(land_parcels)');
      final names = cols.map((r) => r['name'] as String).toSet();
      expect(names.contains('kind'), isFalse);
      final ledger = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'agrico_schema_migrations'",
      );
      // Ledger table creation rolls back because it ran inside the tx.
      expect(ledger, isEmpty);
    });

    test('running migration twice leaves already-correct data alone', () async {
      await createLegacySchema(database);
      await insertLegacyParcel(database, legacyPayload());
      await database.transaction((txn) async {
        await SqliteLandParcelRepository.migrateAddTypedColumns(txn);
      });

      // Manually change kind and parent to simulate a user-typed value.
      await database.update(
        'land_parcels',
        {'kind': 'fieldPlot', 'parent_block_id': null},
        where: 'id = ?',
        whereArgs: ['legacy-1'],
      );

      // Second run should be a no-op because the ledger row exists.
      await database.transaction((txn) async {
        await SqliteLandParcelRepository.migrateAddTypedColumns(txn);
      });

      final rows = await database.query('land_parcels');
      expect(rows.single['kind'], 'fieldPlot');
      expect(rows.single['parent_block_id'], isNull);
    });

    test('ledger records the migration once', () async {
      await createLegacySchema(database);
      await insertLegacyParcel(database, legacyPayload());
      await database.transaction((txn) async {
        await SqliteLandParcelRepository.migrateAddTypedColumns(txn);
      });

      final ledger = await database.query(
        'agrico_schema_migrations',
        where: 'id = ?',
        whereArgs: ['p02a_add_typed_columns'],
      );
      expect(ledger, hasLength(1));
    });

    test('unicode and identity survive migration', () async {
      await createLegacySchema(database);
      await insertLegacyParcel(
        database,
        legacyPayload(name: 'Lô ກະສິກຳ ທົ່ງນາ'),
      );

      await database.transaction((txn) async {
        await SqliteLandParcelRepository.migrateAddTypedColumns(txn);
      });

      final rows = await database.query('land_parcels');
      final payload = jsonDecode(rows.single['payload_json'] as String)
          as Map<String, dynamic>;
      expect(payload['name'], 'Lô ກະສິກຳ ທົ່ງນາ');
      expect(rows.single['id'], 'legacy-1');
      expect(rows.single['parcel_code'], 'AGR-NONG-L001');
    });

    test('failure inside migration rolls back DDL, data and ledger', () async {
      await createLegacySchema(database);
      await insertLegacyParcel(database, legacyPayload());

      await expectLater(
        () => database.transaction((txn) async {
          await SqliteLandParcelRepository.migrateAddTypedColumns(txn);
          // Simulate a later failure inside the same transaction.
          throw StateError('forced migration failure');
        }),
        throwsStateError,
      );

      final cols = await database.rawQuery('PRAGMA table_info(land_parcels)');
      final names = cols.map((r) => r['name'] as String).toSet();
      expect(names.contains('kind'), isFalse);
      expect(names.contains('parent_block_id'), isFalse);
      expect(names.contains('project_id'), isFalse);

      final ledgerTables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'agrico_schema_migrations'",
      );
      expect(ledgerTables, isEmpty);

      final rows = await database.query('land_parcels');
      expect(rows, hasLength(1));
      final payload = jsonDecode(rows.single['payload_json'] as String)
          as Map<String, dynamic>;
      expect(payload['parcelCode'], 'AGR-NONG-L001');
    });
  });

    test('rolls back when a payload self-references as parent', () async {
      await createLegacySchema(database);
      await insertLegacyParcel(
        database,
        legacyPayload(
          id: 'self-parent',
          parcelLayer: 'fieldPlot',
          parentLandBlockId: 'self-parent',
        ),
      );

      await expectLater(
        () => database.transaction((txn) async {
          await SqliteLandParcelRepository.migrateAddTypedColumns(txn);
        }),
        throwsA(anything),
      );

      // Rollback: no new columns, no ledger, original row untouched.
      final cols = await database.rawQuery('PRAGMA table_info(land_parcels)');
      expect(cols.map((r) => r['name']).contains('kind'), isFalse);
      final ledger = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'agrico_schema_migrations'",
      );
      expect(ledger, isEmpty);
    });

    test('rolls back on malformed payload_json', () async {
      await createLegacySchema(database);
      await database.insert('land_parcels', {
        'id': 'broken',
        'farm_id': 'farm-1',
        'parcel_code': 'BROKEN',
        'active': 1,
        'boundary_version': 1,
        'schema_version': 2,
        'payload_json': 'this is not valid json',
      });

      await expectLater(
        () => database.transaction((txn) async {
          await SqliteLandParcelRepository.migrateAddTypedColumns(txn);
        }),
        throwsA(isA<FormatException>()),
      );

      // Rollback.
      final cols = await database.rawQuery('PRAGMA table_info(land_parcels)');
      expect(cols.map((r) => r['name']).contains('kind'), isFalse);
      final ledger = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'agrico_schema_migrations'",
      );
      expect(ledger, isEmpty);
    });

    test('rolls back when parent does not exist', () async {
      await createLegacySchema(database);
      await insertLegacyParcel(
        database,
        legacyPayload(
          id: 'orphan-plot',
          parcelLayer: 'fieldPlot',
          parentLandBlockId: 'missing-parent',
        ),
      );

      await expectLater(
        () => database.transaction((txn) async {
          await SqliteLandParcelRepository.migrateAddTypedColumns(txn);
        }),
        throwsA(anything),
      );

      final cols = await database.rawQuery('PRAGMA table_info(land_parcels)');
      expect(cols.map((r) => r['name']).contains('kind'), isFalse);
      final ledger = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'agrico_schema_migrations'",
      );
      expect(ledger, isEmpty);
    });
}