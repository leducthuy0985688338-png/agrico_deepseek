import 'dart:convert';

import 'package:agrico_deepseek/core/spatial/data/spatial_feature_json_codec.dart';
import 'package:agrico_deepseek/core/spatial/data/spatial_feature_revision_json_codec.dart';
import 'package:agrico_deepseek/core/spatial/data/spatial_feature_revision_sqlite_mapper.dart';
import 'package:agrico_deepseek/core/spatial/data/spatial_feature_sqlite_mapper.dart';
import 'package:agrico_deepseek/core/spatial/data/spatial_geometry_json_codec.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  const point = SpatialPoint(
    coordinate: SpatialCoordinate(
      latitude: 16.500000000123,
      longitude: 104.700000000456,
      altitudeM: 125.4,
    ),
  );

  SpatialFeature feature({SpatialPoint? geometry = point}) => SpatialFeature(
    id: 'feature-1',
    featureType: SpatialFeatureTypes.landParcel,
    geometryType: SpatialGeometryType.point,
    geometry: geometry,
    lifecycleStatus: SpatialFeatureLifecycleStatus.active,
    projectId: 'project-1',
    businessUnitId: 'unit-1',
    code: 'Mã-ລາວ',
    name: 'Thửa Việt–Lào',
    createdAt: DateTime.parse('2026-01-02T03:04:05+07:00'),
    createdBy: 'user-1',
    updatedAt: DateTime.parse('2026-01-03T04:05:06+07:00'),
    updatedBy: 'user-2',
    schemaVersion: 3,
  );

  SpatialFeatureRevision revision({
    SpatialPoint? geometry = point,
    String? geometryReference = 'geometry/ref',
    DateTime? validTo,
  }) => SpatialFeatureRevision(
    id: 'revision-2',
    featureId: 'feature-1',
    revision: 2,
    geometryType: SpatialGeometryType.point,
    geometry: geometry,
    geometryReference: geometryReference,
    temporalState: SpatialTemporalState.asBuilt,
    effectivePeriod: SpatialEffectivePeriod(
      validFrom: DateTime.parse('2026-02-02T03:04:05+07:00'),
      validTo: validTo,
    ),
    source: SpatialSource(
      type: SpatialSourceType.survey,
      surveyedAt: DateTime.parse('2026-02-01T03:04:05+07:00'),
      surveyedBy: 'surveyor-1',
      horizontalAccuracyM: 0.0123456789,
      sourceReference: 'job-ລາວ',
      sourceFileName: 'ranh-giới.dwg',
      sourceFileHash: 'sha256:abc',
      notes: 'Nguồn Việt / ລາວ',
    ),
    changeReason: 'Điều chỉnh ທີ່ດິນ',
    notes: 'Revision Việt–Lào',
    createdAt: DateTime.parse('2026-02-03T03:04:05+07:00'),
    createdBy: 'user-2',
    schemaVersion: 4,
  );

  void expectFeature(SpatialFeature actual, SpatialFeature expected) {
    expect(
      SpatialFeatureJsonCodec.encode(actual),
      SpatialFeatureJsonCodec.encode(expected),
    );
  }

  void expectRevision(
    SpatialFeatureRevision actual,
    SpatialFeatureRevision expected,
  ) {
    expect(
      SpatialFeatureRevisionJsonCodec.encode(actual),
      SpatialFeatureRevisionJsonCodec.encode(expected),
    );
  }

  group('SpatialFeatureSqliteMapper', () {
    test('toRow has exact keys and canonical scalar values', () {
      final row = SpatialFeatureSqliteMapper.toRow(feature());
      expect(row.keys, {
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
      expect(row['id'], 'feature-1');
      expect(row['geometry_type'], 'point');
      expect(row['lifecycle_status'], 'active');
      expect(row['code'], 'Mã-ລາວ');
      expect(row['created_at'], '2026-01-01T20:04:05.000Z');
      expect(row['updated_at'], '2026-01-02T21:05:06.000Z');
      expect(row['schema_version'], 3);
    });

    test('payload_json and geometry_json are canonical codec output', () {
      final source = feature();
      final row = SpatialFeatureSqliteMapper.toRow(source);
      expect(
        jsonDecode(row['payload_json']! as String),
        SpatialFeatureJsonCodec.encode(source),
      );
      expect(
        jsonDecode(row['geometry_json']! as String),
        SpatialGeometryJsonCodec.encode(point),
      );
    });

    test('null geometry and nullable metadata remain SQL null', () {
      final source = SpatialFeature(
        id: 'feature-1',
        featureType: 'landParcel',
        geometryType: SpatialGeometryType.point,
        lifecycleStatus: SpatialFeatureLifecycleStatus.planned,
        createdAt: DateTime.utc(2026),
        createdBy: 'user-1',
        updatedAt: DateTime.utc(2026),
        updatedBy: 'user-1',
      );
      final row = SpatialFeatureSqliteMapper.toRow(source);
      expect(row['geometry_json'], isNull);
      expect(row['project_id'], isNull);
      expect(row['business_unit_id'], isNull);
      expect(row['code'], isNull);
      expect(row['name'], isNull);
      expectFeature(SpatialFeatureSqliteMapper.fromRow(row), source);
    });

    test('toRow/fromRow round-trip preserves Unicode and semantics', () {
      final source = feature();
      expectFeature(
        SpatialFeatureSqliteMapper.fromRow(
          SpatialFeatureSqliteMapper.toRow(source),
        ),
        source,
      );
    });

    for (final entry in <String, Object?>{
      'id': 'other',
      'feature_type': 'river',
      'geometry_type': 'polygon',
      'lifecycle_status': 'inactive',
      'project_id': null,
      'business_unit_id': 'other',
      'code': '',
      'name': 'other',
      'created_at': '2026-01-01T00:00:00.000Z',
      'created_by': 'other',
      'updated_at': '2026-01-04T00:00:00.000Z',
      'updated_by': 'other',
      'schema_version': 2,
    }.entries) {
      test('rejects scalar/payload mismatch for ${entry.key}', () {
        final row = SpatialFeatureSqliteMapper.toRow(feature())
          ..[entry.key] = entry.value;
        expect(
          () => SpatialFeatureSqliteMapper.fromRow(row),
          throwsFormatException,
        );
      });
    }

    test('rejects malformed payload_json and malformed geometry_json', () {
      for (final field in ['payload_json', 'geometry_json']) {
        final row = SpatialFeatureSqliteMapper.toRow(feature())
          ..[field] = '{bad';
        expect(
          () => SpatialFeatureSqliteMapper.fromRow(row),
          throwsFormatException,
        );
      }
    });

    test('rejects geometry content mismatch and null disagreement', () {
      final different = SpatialPoint(
        coordinate: const SpatialCoordinate(latitude: 17, longitude: 105),
      );
      final mismatched = SpatialFeatureSqliteMapper.toRow(feature())
        ..['geometry_json'] = jsonEncode(
          SpatialGeometryJsonCodec.encode(different),
        );
      expect(
        () => SpatialFeatureSqliteMapper.fromRow(mismatched),
        throwsFormatException,
      );
      final missing = SpatialFeatureSqliteMapper.toRow(feature())
        ..['geometry_json'] = null;
      expect(
        () => SpatialFeatureSqliteMapper.fromRow(missing),
        throwsFormatException,
      );
      final unexpected = SpatialFeatureSqliteMapper.toRow(
        feature(geometry: null),
      )..['geometry_json'] = jsonEncode(SpatialGeometryJsonCodec.encode(point));
      expect(
        () => SpatialFeatureSqliteMapper.fromRow(unexpected),
        throwsFormatException,
      );
    });

    test('rejects missing keys and wrong SQLite primitive types', () {
      final missing = SpatialFeatureSqliteMapper.toRow(feature())..remove('id');
      expect(
        () => SpatialFeatureSqliteMapper.fromRow(missing),
        throwsFormatException,
      );
      for (final mutation in <void Function(Map<String, Object?>)>[
        (row) => row['id'] = 1,
        (row) => row['schema_version'] = 3.0,
        (row) => row['created_at'] = 1,
        (row) => row['payload_json'] = <String, Object?>{},
      ]) {
        final row = SpatialFeatureSqliteMapper.toRow(feature());
        mutation(row);
        expect(
          () => SpatialFeatureSqliteMapper.fromRow(row),
          throwsFormatException,
        );
      }
    });
  });

  group('SpatialFeatureRevisionSqliteMapper', () {
    test('toRow has exact keys and canonical scalar values', () {
      final row = SpatialFeatureRevisionSqliteMapper.toRow(revision());
      expect(row.keys, {
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
      expect(row['feature_id'], 'feature-1');
      expect(row['revision'], 2);
      expect(row['temporal_state'], 'asBuilt');
      expect(row['source_type'], 'survey');
      expect(row['valid_from'], '2026-02-01T20:04:05.000Z');
      expect(row['surveyed_at'], '2026-01-31T20:04:05.000Z');
      expect(row['horizontal_accuracy_m'], 0.0123456789);
      expect(row['schema_version'], 4);
    });

    test('payload and geometry JSON use canonical codecs', () {
      final source = revision();
      final row = SpatialFeatureRevisionSqliteMapper.toRow(source);
      expect(
        jsonDecode(row['payload_json']! as String),
        SpatialFeatureRevisionJsonCodec.encode(source),
      );
      expect(
        jsonDecode(row['geometry_json']! as String),
        SpatialGeometryJsonCodec.encode(point),
      );
    });

    test(
      'preserves nullable geometry, reference, period and source fields',
      () {
        final source = SpatialFeatureRevision(
          id: 'revision-1',
          featureId: 'feature-1',
          revision: 1,
          geometryType: SpatialGeometryType.point,
          temporalState: SpatialTemporalState.baseline,
          effectivePeriod: SpatialEffectivePeriod(
            validFrom: DateTime.utc(2026),
          ),
          source: const SpatialSource(type: SpatialSourceType.manual),
          createdAt: DateTime.utc(2026),
          createdBy: 'user-1',
        );
        final row = SpatialFeatureRevisionSqliteMapper.toRow(source);
        expect(row['geometry_json'], isNull);
        expect(row['geometry_reference'], isNull);
        expect(row['valid_to'], isNull);
        expect(row['surveyed_at'], isNull);
        expectRevision(SpatialFeatureRevisionSqliteMapper.fromRow(row), source);
      },
    );

    test('toRow/fromRow preserves Unicode and all semantics', () {
      final source = revision(validTo: DateTime.parse('2026-03-01T00:00:00Z'));
      expectRevision(
        SpatialFeatureRevisionSqliteMapper.fromRow(
          SpatialFeatureRevisionSqliteMapper.toRow(source),
        ),
        source,
      );
    });

    for (final entry in <String, Object?>{
      'id': 'other',
      'feature_id': 'other',
      'revision': 3,
      'geometry_type': 'polygon',
      'geometry_reference': null,
      'temporal_state': 'baseline',
      'valid_from': '2026-01-01T00:00:00Z',
      'valid_to': '2027-01-01T00:00:00Z',
      'source_type': 'gps',
      'surveyed_at': null,
      'surveyed_by': 'other',
      'horizontal_accuracy_m': 9.5,
      'source_reference': 'other',
      'source_file_name': 'other',
      'source_file_hash': 'other',
      'source_notes': 'other',
      'change_reason': 'other',
      'notes': 'other',
      'created_at': '2026-01-01T00:00:00Z',
      'created_by': 'other',
      'schema_version': 3,
    }.entries) {
      test('rejects revision scalar mismatch for ${entry.key}', () {
        final row = SpatialFeatureRevisionSqliteMapper.toRow(revision())
          ..[entry.key] = entry.value;
        expect(
          () => SpatialFeatureRevisionSqliteMapper.fromRow(row),
          throwsFormatException,
        );
      });
    }

    test('rejects malformed JSON and geometry consistency failures', () {
      for (final field in ['payload_json', 'geometry_json']) {
        final row = SpatialFeatureRevisionSqliteMapper.toRow(revision())
          ..[field] = '[]';
        expect(
          () => SpatialFeatureRevisionSqliteMapper.fromRow(row),
          throwsFormatException,
        );
      }
      final missing = SpatialFeatureRevisionSqliteMapper.toRow(revision())
        ..['geometry_json'] = null;
      expect(
        () => SpatialFeatureRevisionSqliteMapper.fromRow(missing),
        throwsFormatException,
      );
    });

    test('rejects missing keys and wrong SQLite primitive types', () {
      final missing = SpatialFeatureRevisionSqliteMapper.toRow(revision())
        ..remove('feature_id');
      expect(
        () => SpatialFeatureRevisionSqliteMapper.fromRow(missing),
        throwsFormatException,
      );
      for (final mutation in <void Function(Map<String, Object?>)>[
        (row) => row['revision'] = '2',
        (row) => row['schema_version'] = 4.0,
        (row) => row['temporal_state'] = 1,
        (row) => row['horizontal_accuracy_m'] = '0.01',
      ]) {
        final row = SpatialFeatureRevisionSqliteMapper.toRow(revision());
        mutation(row);
        expect(
          () => SpatialFeatureRevisionSqliteMapper.fromRow(row),
          throwsFormatException,
        );
      }
    });
  });

  test('mapper rows survive real SQLite storage and retrieval', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await database.execute('PRAGMA foreign_keys = ON');
    await SqliteSpatialSchema.createSchema(database);
    final sourceFeature = feature();
    final sourceRevision = revision();
    await database.insert(
      SqliteSpatialSchema.featuresTable,
      SpatialFeatureSqliteMapper.toRow(sourceFeature),
    );
    await database.insert(
      SqliteSpatialSchema.revisionsTable,
      SpatialFeatureRevisionSqliteMapper.toRow(sourceRevision),
    );
    expectFeature(
      SpatialFeatureSqliteMapper.fromRow(
        (await database.query(SqliteSpatialSchema.featuresTable)).single,
      ),
      sourceFeature,
    );
    expectRevision(
      SpatialFeatureRevisionSqliteMapper.fromRow(
        (await database.query(SqliteSpatialSchema.revisionsTable)).single,
      ),
      sourceRevision,
    );
  });
}
