import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database database;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');
    expect(
      (await database.rawQuery('PRAGMA foreign_keys')).single.values.single,
      1,
    );
  });

  tearDown(() => database.close());

  Map<String, Object?> featureRow({String id = 'feature-1'}) => {
    'id': id,
    'feature_type': 'landParcel',
    'geometry_type': 'polygon',
    'lifecycle_status': 'active',
    'project_id': 'project-1',
    'business_unit_id': 'unit-1',
    'code': 'P-001',
    'name': 'Parcel 1',
    'created_at': '2026-01-01T00:00:00.000Z',
    'created_by': 'user-1',
    'updated_at': '2026-01-02T00:00:00.000Z',
    'updated_by': 'user-2',
    'schema_version': 1,
    'geometry_json': null,
    'payload_json': '{}',
  };

  Map<String, Object?> revisionRow({
    String id = 'revision-1',
    String featureId = 'feature-1',
    int revision = 1,
  }) => {
    'id': id,
    'feature_id': featureId,
    'revision': revision,
    'geometry_type': 'polygon',
    'geometry_json': null,
    'geometry_reference': null,
    'temporal_state': 'baseline',
    'valid_from': '2026-01-01T00:00:00.000Z',
    'valid_to': null,
    'source_type': 'survey',
    'surveyed_at': null,
    'surveyed_by': null,
    'horizontal_accuracy_m': null,
    'source_reference': null,
    'source_file_name': null,
    'source_file_hash': null,
    'source_notes': null,
    'change_reason': null,
    'notes': null,
    'created_at': '2026-01-01T00:00:00.000Z',
    'created_by': 'user-1',
    'schema_version': 1,
    'payload_json': '{}',
  };

  Future<void> createSchema() => SqliteSpatialSchema.createSchema(database);

  test('creates both Spatial Core tables', () async {
    await createSchema();
    final tables = await database.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'table' AND name LIKE 'spatial_%'",
    );
    expect(
      tables.map((row) => row['name']),
      containsAll(['spatial_features', 'spatial_feature_revisions']),
    );
  });

  test('createSchema is idempotent', () async {
    await createSchema();
    await createSchema();
    expect(
      await database.query('sqlite_master', where: "type = 'table'"),
      isNotEmpty,
    );
  });

  test('spatial_features has exact columns and constraints', () async {
    await createSchema();
    final info = await database.rawQuery('PRAGMA table_info(spatial_features)');
    final columns = {for (final row in info) row['name'] as String: row};
    expect(columns.keys, {
      'id',
      'feature_type',
      'geometry_type',
      'lifecycle_status',
      'project_id',
      'business_unit_id',
      'code',
      'name',
      'created_at',
      'created_by',
      'updated_at',
      'updated_by',
      'schema_version',
      'geometry_json',
      'payload_json',
    });
    expect(columns['id']!['pk'], 1);
    for (final name in [
      'id',
      'feature_type',
      'geometry_type',
      'lifecycle_status',
      'created_at',
      'created_by',
      'updated_at',
      'updated_by',
      'schema_version',
      'payload_json',
    ]) {
      expect(columns[name]!['notnull'], 1, reason: name);
    }
    for (final name in [
      'project_id',
      'business_unit_id',
      'code',
      'name',
      'geometry_json',
    ]) {
      expect(columns[name]!['notnull'], 0, reason: name);
    }
  });

  test('spatial_feature_revisions has exact columns and constraints', () async {
    await createSchema();
    final info = await database.rawQuery(
      'PRAGMA table_info(spatial_feature_revisions)',
    );
    final columns = {for (final row in info) row['name'] as String: row};
    expect(columns.keys, {
      'id',
      'feature_id',
      'revision',
      'geometry_type',
      'geometry_json',
      'geometry_reference',
      'temporal_state',
      'valid_from',
      'valid_to',
      'source_type',
      'surveyed_at',
      'surveyed_by',
      'horizontal_accuracy_m',
      'source_reference',
      'source_file_name',
      'source_file_hash',
      'source_notes',
      'change_reason',
      'notes',
      'created_at',
      'created_by',
      'schema_version',
      'payload_json',
    });
    expect(columns['id']!['pk'], 1);
    for (final name in [
      'id',
      'feature_id',
      'revision',
      'geometry_type',
      'temporal_state',
      'valid_from',
      'source_type',
      'created_at',
      'created_by',
      'schema_version',
      'payload_json',
    ]) {
      expect(columns[name]!['notnull'], 1, reason: name);
    }
  });

  test('primary keys reject duplicate feature and revision ids', () async {
    await createSchema();
    await database.insert('spatial_features', featureRow());
    await expectLater(
      database.insert('spatial_features', featureRow()),
      throwsA(isA<DatabaseException>()),
    );
    await database.insert('spatial_feature_revisions', revisionRow());
    await expectLater(
      database.insert('spatial_feature_revisions', revisionRow(revision: 2)),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('UNIQUE feature_id and revision is enforced', () async {
    await createSchema();
    await database.insert('spatial_features', featureRow());
    await database.insert('spatial_feature_revisions', revisionRow());
    await expectLater(
      database.insert(
        'spatial_feature_revisions',
        revisionRow(id: 'revision-other'),
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('same revision number is allowed for different features', () async {
    await createSchema();
    await database.insert('spatial_features', featureRow());
    await database.insert('spatial_features', featureRow(id: 'feature-2'));
    await database.insert('spatial_feature_revisions', revisionRow());
    await database.insert(
      'spatial_feature_revisions',
      revisionRow(id: 'revision-2', featureId: 'feature-2'),
    );
    expect(await database.query('spatial_feature_revisions'), hasLength(2));
  });

  test('foreign key rejects orphan and accepts revision with parent', () async {
    await createSchema();
    await expectLater(
      database.insert('spatial_feature_revisions', revisionRow()),
      throwsA(isA<DatabaseException>()),
    );
    await database.insert('spatial_features', featureRow());
    await database.insert('spatial_feature_revisions', revisionRow());
    expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('foreign key declares RESTRICT update and delete', () async {
    await createSchema();
    final keys = await database.rawQuery(
      'PRAGMA foreign_key_list(spatial_feature_revisions)',
    );
    expect(keys, hasLength(1));
    expect(keys.single['table'], 'spatial_features');
    expect(keys.single['from'], 'feature_id');
    expect(keys.single['to'], 'id');
    expect(keys.single['on_update'], 'RESTRICT');
    expect(keys.single['on_delete'], 'RESTRICT');
  });

  test(
    'parent delete and id update are restricted and history remains',
    () async {
      await createSchema();
      await database.insert('spatial_features', featureRow());
      await database.insert('spatial_feature_revisions', revisionRow());
      await expectLater(
        database.delete(
          'spatial_features',
          where: 'id = ?',
          whereArgs: ['feature-1'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.update(
          'spatial_features',
          {'id': 'changed'},
          where: 'id = ?',
          whereArgs: ['feature-1'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await database.query('spatial_features'), hasLength(1));
      expect(await database.query('spatial_feature_revisions'), hasLength(1));
    },
  );

  test('nullable geometry_json is accepted in both tables', () async {
    await createSchema();
    await database.insert('spatial_features', featureRow());
    await database.insert('spatial_feature_revisions', revisionRow());
    expect(
      (await database.query('spatial_features')).single['geometry_json'],
      isNull,
    );
    expect(
      (await database.query(
        'spatial_feature_revisions',
      )).single['geometry_json'],
      isNull,
    );
  });

  test('payload_json and schema_version are required', () async {
    await createSchema();
    for (final field in ['payload_json', 'schema_version']) {
      final row = featureRow()..remove(field);
      await expectLater(
        database.insert('spatial_features', row),
        throwsA(isA<DatabaseException>()),
      );
    }
    await database.insert('spatial_features', featureRow());
    for (final field in ['payload_json', 'schema_version']) {
      final row = revisionRow(id: 'revision-$field')..remove(field);
      await expectLater(
        database.insert('spatial_feature_revisions', row),
        throwsA(isA<DatabaseException>()),
      );
    }
  });

  test('selected scalar feature and revision fields are queryable', () async {
    await createSchema();
    await database.insert('spatial_features', featureRow());
    await database.insert('spatial_feature_revisions', revisionRow());
    expect(
      await database.query(
        'spatial_features',
        where: 'feature_type = ? AND lifecycle_status = ?',
        whereArgs: ['landParcel', 'active'],
      ),
      hasLength(1),
    );
    expect(
      await database.query(
        'spatial_feature_revisions',
        where: 'feature_id = ? AND temporal_state = ?',
        whereArgs: ['feature-1', 'baseline'],
      ),
      hasLength(1),
    );
  });

  test('creates only the expected explicit indexes', () async {
    await createSchema();
    final featureIndexes = await database.rawQuery(
      'PRAGMA index_list(spatial_features)',
    );
    expect(
      featureIndexes.map((row) => row['name']),
      containsAll({
        'idx_spatial_features_feature_type',
        'idx_spatial_features_geometry_type',
        'idx_spatial_features_lifecycle_status',
        'idx_spatial_features_project_id',
        'idx_spatial_features_business_unit_id',
        'idx_spatial_features_updated_at',
      }),
    );

    final revisionIndexes = await database.rawQuery(
      'PRAGMA index_list(spatial_feature_revisions)',
    );
    final names = revisionIndexes.map((row) => row['name'] as String).toList();
    expect(
      names,
      containsAll({
        'idx_spatial_feature_revisions_temporal_state',
        'idx_spatial_feature_revisions_valid_from',
        'idx_spatial_feature_revisions_source_type',
      }),
    );
    expect(names, isNot(contains('idx_spatial_feature_revisions_feature_id')));
    expect(
      names,
      isNot(contains('idx_spatial_feature_revisions_feature_revision')),
    );

    final uniqueIndex = revisionIndexes.singleWhere(
      (row) => row['origin'] == 'u',
    );
    final uniqueColumns = await database.rawQuery(
      'PRAGMA index_info(${uniqueIndex['name']})',
    );
    expect(uniqueColumns.map((row) => row['name']), ['feature_id', 'revision']);
  });

  test('createSchema accepts Transaction as DatabaseExecutor', () async {
    await database.transaction((transaction) async {
      await SqliteSpatialSchema.createSchema(transaction);
      await transaction.insert('spatial_features', featureRow());
    });
    expect(await database.query('spatial_features'), hasLength(1));
  });

  test('failed transaction rolls back schema and data work', () async {
    await expectLater(
      database.transaction<void>((transaction) async {
        await SqliteSpatialSchema.createSchema(transaction);
        await transaction.insert('spatial_features', featureRow());
        throw StateError('force rollback');
      }),
      throwsStateError,
    );
    final tables = await database.query(
      'sqlite_master',
      where: "type = 'table' AND name IN (?, ?)",
      whereArgs: ['spatial_features', 'spatial_feature_revisions'],
    );
    expect(tables, isEmpty);
  });
}
