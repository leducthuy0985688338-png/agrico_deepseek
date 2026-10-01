import 'dart:convert';
import 'dart:io';

import 'package:agrico_deepseek/services/field_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late String dbPath;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('agrico-upgrade-');
    dbPath = p.join(tempDir.path, 'agrico.db');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Seeds the pre-P02A shape of the database at version 8.
  Future<void> seedVersion8(String path) async {
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 8),
    );
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
    await db.insert('land_parcels', {
      'id': 'legacy-1',
      'farm_id': 'farm-1',
      'parcel_code': 'AGR-NONG-L001',
      'active': 1,
      'boundary_version': 1,
      'schema_version': 2,
      'payload_json': jsonEncode({
        'id': 'legacy-1',
        'farmId': 'farm-1',
        'parcelCode': 'AGR-NONG-L001',
        'name': 'Lô ກະສິກຳ',
        'active': true,
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
        'centroid': {
          'latitude': 16.5003,
          'longitude': 104.7003,
          'altitudeM': null,
        },
        'areaM2': 1000.0,
        'areaHa': 0.1,
        'perimeterM': 150.0,
        'boundarySource': 'gps',
        'verificationStatus': 'measured',
        'boundaryVersion': 1,
        'legacyMetadata': <String, Object?>{},
      }),
    });
    await db.close();
  }

  /// Opens the database the same way the application does: through
  /// FieldDatabase.configure and FieldDatabase.upgradeSchema.
  Future<Database> openLikeApplication(String path, int version) =>
      databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: version,
          onConfigure: FieldDatabase.configure,
          onCreate: FieldDatabase.createSchema,
          onUpgrade: FieldDatabase.upgradeSchema,
        ),
      );

  test(
    'FieldDatabase.upgradeSchema migrates v8 to v9 and adds typed columns',
    () async {
      await seedVersion8(dbPath);

      final db = await openLikeApplication(
        dbPath,
        FieldDatabase.databaseVersion,
      );

      // 1. Typed columns exist.
      final cols = await db.rawQuery('PRAGMA table_info(land_parcels)');
      final names = cols.map((c) => c['name'] as String).toSet();
      expect(names, contains('project_id'));
      expect(names, contains('kind'));
      expect(names, contains('parent_block_id'));

      // 2. Backfill done: legacy parcel has kind='landBlock', parent NULL.
      final rows = await db.query('land_parcels');
      expect(rows, hasLength(1));
      expect(rows.single['kind'], 'landBlock');
      expect(rows.single['parent_block_id'], isNull);
      expect(rows.single['project_id'], isNull);

      // 3. Ledger row written.
      final ledger = await db.query(
        'agrico_schema_migrations',
        where: 'id = ?',
        whereArgs: ['p02a_add_typed_columns'],
      );
      expect(ledger, hasLength(1));

      // 4. Triggers installed.
      final triggers = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger' "
        "AND name LIKE 'trg_land_parcels_%'",
      );
      final triggerNames = triggers.map((t) => t['name'] as String).toSet();
      expect(triggerNames, contains('trg_land_parcels_parent_protect_update'));
      expect(
        triggerNames,
        contains('trg_land_parcels_parent_orphan_delete'),
      );

      await db.close();
    },
  );

  test('reopening through FieldDatabase is idempotent', () async {
    await seedVersion8(dbPath);

    Future<void> openAndClose() async {
      final db = await openLikeApplication(
        dbPath,
        FieldDatabase.databaseVersion,
      );
      await db.close();
    }

    await openAndClose();
    await openAndClose();

    final db = await databaseFactoryFfi.openDatabase(dbPath);
    final ledger = await db.query('agrico_schema_migrations');
    // Migration recorded exactly once.
    expect(
      ledger.where((r) => r['id'] == 'p02a_add_typed_columns'),
      hasLength(1),
    );
    await db.close();
  });
}