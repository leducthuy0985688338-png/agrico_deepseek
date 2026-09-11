import 'dart:io';

import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_survey_repository.dart';
import 'package:agrico_deepseek/services/field_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory directory;
  late String path;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('agrico-v7-');
    path = p.join(directory.path, 'agrico.db');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Future<Database> openAuthoritative(int version) =>
      databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: version,
          onConfigure: FieldDatabase.configure,
          onCreate: FieldDatabase.createSchema,
          onUpgrade: FieldDatabase.upgradeSchema,
        ),
      );

  Future<Set<String>> tableNames(Database database) async =>
      (await database.query(
        'sqlite_master',
        columns: ['name'],
        where: "type = 'table'",
      )).map((row) => row['name']! as String).toSet();

  Future<int> pragma(Database database, String name) async =>
      (await database.rawQuery('PRAGMA $name')).single.values.single! as int;

  test('fresh authoritative database creates complete v7 schema', () async {
    final database = await openAuthoritative(FieldDatabase.databaseVersion);
    addTearDown(database.close);

    expect(await pragma(database, 'user_version'), 7);
    expect(await pragma(database, 'foreign_keys'), 1);
    expect(
      await tableNames(database),
      containsAll({
        'fields',
        'field_measurement_history',
        'distance_measurements',
        SqliteLandParcelRepository.parcelTable,
        SqliteLandParcelRepository.boundaryVersionTable,
        SqliteLandSurveyRepository.householdsTable,
        SqliteLandSurveyRepository.surveysTable,
        SqliteLandSurveyRepository.landUseTable,
        SqliteLandSurveyRepository.cropsTable,
        SqliteLandSurveyRepository.attachmentsTable,
        SqliteSpatialSchema.featuresTable,
        SqliteSpatialSchema.revisionsTable,
      }),
    );
    final indexes = await database.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'index' AND name LIKE 'idx_spatial_%'",
    );
    expect(indexes, hasLength(9));
  });

  test('v6 to v7 preserves parcel history and survey-era data', () async {
    var database = await openAuthoritative(6);
    await database.insert(SqliteLandParcelRepository.parcelTable, {
      'id': 'parcel-1',
      'farm_id': 'farm-1',
      'parcel_code': 'P-001',
      'active': 1,
      'boundary_version': 1,
      'schema_version': 1,
      'payload_json': '{"name":"Thửa ດິນ"}',
    });
    await database.insert(SqliteLandParcelRepository.boundaryVersionTable, {
      'id': 'boundary-1',
      'parcel_id': 'parcel-1',
      'version': 1,
      'schema_version': 1,
      'payload_json': '{"audit":"kept"}',
    });
    await database.insert(SqliteLandSurveyRepository.surveysTable, {
      'id': 'survey-1',
      'parcel_id': 'parcel-1',
      'boundary_version': 1,
      'schema_version': 1,
      'payload_json': '{"notes":"Đo tại ລາວ"}',
    });
    await database.close();

    database = await openAuthoritative(7);
    addTearDown(database.close);
    expect(await pragma(database, 'user_version'), 7);
    expect(await pragma(database, 'foreign_keys'), 1);
    expect(
      (await database.query(SqliteLandParcelRepository.parcelTable)).single,
      containsPair('payload_json', '{"name":"Thửa ດິນ"}'),
    );
    expect(
      (await database.query(
        SqliteLandParcelRepository.boundaryVersionTable,
      )).single,
      containsPair('payload_json', '{"audit":"kept"}'),
    );
    expect(
      (await database.query(SqliteLandSurveyRepository.surveysTable)).single,
      containsPair('payload_json', '{"notes":"Đo tại ລາວ"}'),
    );
    expect(await database.query(SqliteSpatialSchema.featuresTable), isEmpty);
    expect(await database.query(SqliteSpatialSchema.revisionsTable), isEmpty);
    expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('representative v1 database reaches complete v7 schema', () async {
    var database = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE fields (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              area REAL NOT NULL,
              crop TEXT NOT NULL,
              status TEXT NOT NULL,
              polygon TEXT NOT NULL,
              photo_paths TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await database.insert('fields', {
            'id': 'legacy-field',
            'name': 'Legacy',
            'area': 1.5,
            'crop': 'rice',
            'status': 'active',
            'polygon': '[]',
            'photo_paths': '[]',
            'updated_at': '2026-01-01T00:00:00.000Z',
          });
        },
      ),
    );
    await database.close();

    database = await openAuthoritative(7);
    addTearDown(database.close);
    expect(await pragma(database, 'user_version'), 7);
    expect((await database.query('fields')).single['id'], 'legacy-field');
    expect(
      await tableNames(database),
      containsAll({
        'field_measurement_history',
        'distance_measurements',
        SqliteLandParcelRepository.parcelTable,
        SqliteLandSurveyRepository.surveysTable,
        SqliteSpatialSchema.featuresTable,
        SqliteSpatialSchema.revisionsTable,
      }),
    );
  });

  test(
    'migrated Spatial constraints enforce PK UNIQUE and FK RESTRICT',
    () async {
      var database = await openAuthoritative(6);
      await database.close();
      database = await openAuthoritative(7);
      addTearDown(database.close);

      final feature = {
        'id': 'feature-1',
        'feature_type': 'landParcel',
        'geometry_type': 'polygon',
        'lifecycle_status': 'active',
        'created_at': '2026-01-01T00:00:00.000Z',
        'created_by': 'user-1',
        'updated_at': '2026-01-01T00:00:00.000Z',
        'updated_by': 'user-1',
        'schema_version': 1,
        'payload_json': '{}',
      };
      final revision = {
        'id': 'revision-1',
        'feature_id': 'feature-1',
        'revision': 1,
        'geometry_type': 'polygon',
        'temporal_state': 'baseline',
        'valid_from': '2026-01-01T00:00:00.000Z',
        'source_type': 'survey',
        'created_at': '2026-01-01T00:00:00.000Z',
        'created_by': 'user-1',
        'schema_version': 1,
        'payload_json': '{}',
      };
      await expectLater(
        database.insert(SqliteSpatialSchema.revisionsTable, revision),
        throwsA(isA<DatabaseException>()),
      );
      await database.insert(SqliteSpatialSchema.featuresTable, feature);
      await database.insert(SqliteSpatialSchema.revisionsTable, revision);
      await expectLater(
        database.insert(SqliteSpatialSchema.featuresTable, feature),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.insert(SqliteSpatialSchema.revisionsTable, {
          ...revision,
          'id': 'revision-2',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.delete(
          SqliteSpatialSchema.featuresTable,
          where: 'id = ?',
          whereArgs: ['feature-1'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.update(
          SqliteSpatialSchema.featuresTable,
          {'id': 'changed'},
          where: 'id = ?',
          whereArgs: ['feature-1'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        await database.query(SqliteSpatialSchema.revisionsTable),
        hasLength(1),
      );
    },
  );

  test('Spatial schema helper remains idempotent on v7 data', () async {
    final database = await openAuthoritative(7);
    addTearDown(database.close);
    await database.insert(SqliteSpatialSchema.featuresTable, {
      'id': 'feature-1',
      'feature_type': 'landParcel',
      'geometry_type': 'polygon',
      'lifecycle_status': 'active',
      'created_at': '2026-01-01T00:00:00.000Z',
      'created_by': 'user-1',
      'updated_at': '2026-01-01T00:00:00.000Z',
      'updated_by': 'user-1',
      'schema_version': 1,
      'payload_json': '{"kept":true}',
    });

    await SqliteSpatialSchema.createSchema(database);
    await SqliteSpatialSchema.createSchema(database);

    expect(
      (await database.query(SqliteSpatialSchema.featuresTable)).single,
      containsPair('payload_json', '{"kept":true}'),
    );
    final indexes = await database.query(
      'sqlite_master',
      where: "type = 'index' AND name LIKE 'idx_spatial_%'",
    );
    expect(indexes, hasLength(9));
  });
}
