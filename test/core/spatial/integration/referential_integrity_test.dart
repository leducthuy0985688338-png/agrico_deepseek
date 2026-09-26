import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_spatial_link_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');

    final fkEnabled =
        (await db.rawQuery('PRAGMA foreign_keys')).single.values.single;
    expect(fkEnabled, 1, reason: 'Foreign keys must be enabled for audit.');

    // Production schema order (mirrors FieldDatabase migrations):
    await SqliteLandParcelRepository.createSchema(db);
    await SqliteSpatialSchema.createSchema(db);
    await SqliteLandParcelSpatialLinkRepository.createSchema(db);
  });

  tearDown(() => db.close());

  // ------------------------------------------------------------
  // SEED HELPERS (raw rows — KHÔNG cần full domain entity)
  // ------------------------------------------------------------

  Future<void> seedLandParcel(String id) async {
    await db.insert(SqliteLandParcelRepository.parcelTable, {
      'id': id,
      'farm_id': 'farm-1',
      'parcel_code': 'CODE-$id',
      'active': 1,
      'boundary_version': 1,
      'schema_version': 2,
      'payload_json': '{}',
    });
  }

  Future<void> seedSpatialFeature(String id) async {
    await db.insert(SqliteSpatialSchema.featuresTable, {
      'id': id,
      'feature_type': 'landParcel',
      'geometry_type': 'polygon',
      'lifecycle_status': 'active',
      'created_at': '2026-01-01T00:00:00.000Z',
      'created_by': 'user-1',
      'updated_at': '2026-01-01T00:00:00.000Z',
      'updated_by': 'user-1',
      'schema_version': 1,
      'geometry_json': null,
      'payload_json': '{}',
    });
  }

  Future<void> seedSpatialFeatureRevision({
    required String id,
    required String featureId,
    required int revision,
  }) async {
    await db.insert(SqliteSpatialSchema.revisionsTable, {
      'id': id,
      'feature_id': featureId,
      'revision': revision,
      'geometry_type': 'polygon',
      'temporal_state': 'baseline',
      'valid_from': '2026-01-01T00:00:00.000Z',
      'source_type': 'survey',
      'created_at': '2026-01-01T00:00:00.000Z',
      'created_by': 'user-1',
      'schema_version': 1,
      'payload_json': '{}',
    });
  }

  Future<void> seedLink({
    required String id,
    required String landParcelId,
    required String spatialFeatureId,
  }) async {
    await db.insert(SqliteLandParcelSpatialLinkRepository.table, {
      'id': id,
      'land_parcel_id': landParcelId,
      'spatial_feature_id': spatialFeatureId,
      'created_at': '2026-01-01T00:00:00.000Z',
      'created_by': 'user-1',
      'schema_version': 1,
    });
  }

  Future<int> countRows(String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return rows.single['c'] as int;
  }

  // ============================================================
  // TEST 1 — Valid chain
  // ============================================================
  test('1. valid LandParcel + SpatialFeature + Revision + Link', () async {
    await seedLandParcel('parcel-1');
    await seedSpatialFeature('SPF-001');
    await seedSpatialFeatureRevision(
      id: 'R-1',
      featureId: 'SPF-001',
      revision: 1,
    );
    await seedLink(
      id: 'link-1',
      landParcelId: 'parcel-1',
      spatialFeatureId: 'SPF-001',
    );

    expect(await countRows(SqliteLandParcelRepository.parcelTable), 1);
    expect(await countRows(SqliteSpatialSchema.featuresTable), 1);
    expect(await countRows(SqliteSpatialSchema.revisionsTable), 1);
    expect(await countRows(SqliteLandParcelSpatialLinkRepository.table), 1);

    // Identity consistency
    final link = (await db.query(
      SqliteLandParcelSpatialLinkRepository.table,
    )).single;

    expect(link['land_parcel_id'], 'parcel-1');
    expect(link['spatial_feature_id'], 'SPF-001');

    final revision = (await db.query(
      SqliteSpatialSchema.revisionsTable,
    )).single;
    expect(revision['feature_id'], 'SPF-001');
    expect(revision['revision'], 1);
  });

  // ============================================================
  // TEST 2 — Orphan LandParcel FK rejected
  // ============================================================
  test('2. orphan land_parcel_id FK rejected', () async {
    await seedSpatialFeature('SPF-001');

    await expectLater(
      seedLink(
        id: 'link-orphan',
        landParcelId: 'nonexistent-parcel',
        spatialFeatureId: 'SPF-001',
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(await countRows(SqliteLandParcelSpatialLinkRepository.table), 0);
  });

  // ============================================================
  // TEST 3 — Orphan SpatialFeature FK rejected
  // ============================================================
  test('3. orphan spatial_feature_id FK rejected', () async {
    await seedLandParcel('parcel-1');

    await expectLater(
      seedLink(
        id: 'link-orphan',
        landParcelId: 'parcel-1',
        spatialFeatureId: 'nonexistent-feature',
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(await countRows(SqliteLandParcelSpatialLinkRepository.table), 0);
  });

  // ============================================================
  // TEST 4 — Orphan SpatialFeatureRevision FK rejected
  // ============================================================
  test('4. orphan feature_id in revision rejected', () async {
    await expectLater(
      seedSpatialFeatureRevision(
        id: 'R-orphan',
        featureId: 'nonexistent-feature',
        revision: 1,
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(await countRows(SqliteSpatialSchema.revisionsTable), 0);
  });

  // ============================================================
  // TEST 5 — Duplicate link rejected by land_parcel_id
  // ============================================================
  test('5. duplicate link by land_parcel_id rejected', () async {
    await seedLandParcel('parcel-A');
    await seedSpatialFeature('SPF-X');
    await seedSpatialFeature('SPF-Y');

    await seedLink(
      id: 'link-1',
      landParcelId: 'parcel-A',
      spatialFeatureId: 'SPF-X',
    );

    await expectLater(
      seedLink(
        id: 'link-2',
        landParcelId: 'parcel-A',
        spatialFeatureId: 'SPF-Y',
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(await countRows(SqliteLandParcelSpatialLinkRepository.table), 1);
  });

  // ============================================================
  // TEST 6 — Duplicate link rejected by spatial_feature_id
  // ============================================================
  test('6. duplicate link by spatial_feature_id rejected', () async {
    await seedLandParcel('parcel-A');
    await seedLandParcel('parcel-B');
    await seedSpatialFeature('SPF-X');

    await seedLink(
      id: 'link-1',
      landParcelId: 'parcel-A',
      spatialFeatureId: 'SPF-X',
    );

    await expectLater(
      seedLink(
        id: 'link-2',
        landParcelId: 'parcel-B',
        spatialFeatureId: 'SPF-X',
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(await countRows(SqliteLandParcelSpatialLinkRepository.table), 1);
  });

  // ============================================================
  // TEST 7 — Delete LandParcel RESTRICT
  // ============================================================
  test('7. delete LandParcel RESTRICT when link exists', () async {
    await seedLandParcel('parcel-1');
    await seedSpatialFeature('SPF-001');
    await seedLink(
      id: 'link-1',
      landParcelId: 'parcel-1',
      spatialFeatureId: 'SPF-001',
    );

    await expectLater(
      db.delete(
        SqliteLandParcelRepository.parcelTable,
        where: 'id = ?',
        whereArgs: ['parcel-1'],
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(await countRows(SqliteLandParcelRepository.parcelTable), 1);
    expect(await countRows(SqliteLandParcelSpatialLinkRepository.table), 1);
  });

  // ============================================================
  // TEST 8 — Delete SpatialFeature RESTRICT
  // ============================================================
  test('8. delete SpatialFeature RESTRICT when revision/link exists',
      () async {
    await seedLandParcel('parcel-1');
    await seedSpatialFeature('SPF-001');
    await seedSpatialFeatureRevision(
      id: 'R-1',
      featureId: 'SPF-001',
      revision: 1,
    );
    await seedLink(
      id: 'link-1',
      landParcelId: 'parcel-1',
      spatialFeatureId: 'SPF-001',
    );

    await expectLater(
      db.delete(
        SqliteSpatialSchema.featuresTable,
        where: 'id = ?',
        whereArgs: ['SPF-001'],
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(await countRows(SqliteSpatialSchema.featuresTable), 1);
    expect(await countRows(SqliteSpatialSchema.revisionsTable), 1);
    expect(await countRows(SqliteLandParcelSpatialLinkRepository.table), 1);
  });

  // ============================================================
  // TEST 9 — Transaction rollback after FK failure
  // ============================================================
  test('9. transaction rollback after FK failure leaves no partial state',
      () async {
    await expectLater(
      db.transaction((txn) async {
        // Valid inserts inside transaction
        await txn.insert(SqliteLandParcelRepository.parcelTable, {
          'id': 'parcel-tx',
          'farm_id': 'farm-1',
          'parcel_code': 'CODE-TX',
          'active': 1,
          'boundary_version': 1,
          'schema_version': 2,
          'payload_json': '{}',
        });

        await txn.insert(SqliteSpatialSchema.featuresTable, {
          'id': 'SPF-TX',
          'feature_type': 'landParcel',
          'geometry_type': 'polygon',
          'lifecycle_status': 'active',
          'created_at': '2026-01-01T00:00:00.000Z',
          'created_by': 'user-1',
          'updated_at': '2026-01-01T00:00:00.000Z',
          'updated_by': 'user-1',
          'schema_version': 1,
          'payload_json': '{}',
        });

        await txn.insert(SqliteSpatialSchema.revisionsTable, {
          'id': 'R-TX',
          'feature_id': 'SPF-TX',
          'revision': 1,
          'geometry_type': 'polygon',
          'temporal_state': 'baseline',
          'valid_from': '2026-01-01T00:00:00.000Z',
          'source_type': 'survey',
          'created_at': '2026-01-01T00:00:00.000Z',
          'created_by': 'user-1',
          'schema_version': 1,
          'payload_json': '{}',
        });

        // Invalid link FK → transaction must rollback
        await txn.insert(SqliteLandParcelSpatialLinkRepository.table, {
          'id': 'link-tx-invalid',
          'land_parcel_id': 'nonexistent',
          'spatial_feature_id': 'SPF-TX',
          'created_at': '2026-01-01T00:00:00.000Z',
          'created_by': 'user-1',
          'schema_version': 1,
        });
      }),
      throwsA(isA<DatabaseException>()),
    );

    // Verify no partial state
    expect(await countRows(SqliteLandParcelRepository.parcelTable), 0);
    expect(await countRows(SqliteSpatialSchema.featuresTable), 0);
    expect(await countRows(SqliteSpatialSchema.revisionsTable), 0);
    expect(await countRows(SqliteLandParcelSpatialLinkRepository.table), 0);
  });
}