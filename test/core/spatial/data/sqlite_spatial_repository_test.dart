import 'package:agrico_deepseek/core/spatial/data/spatial_feature_json_codec.dart';
import 'package:agrico_deepseek/core/spatial/data/spatial_feature_revision_json_codec.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_feature_repository.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_feature_revision_repository.dart';
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
    coordinate: SpatialCoordinate(latitude: 16.5, longitude: 104.7),
  );

  SpatialFeature feature(
    String id, {
    String? name,
    SpatialPoint? geometry = point,
    DateTime? updatedAt,
  }) => SpatialFeature(
    id: id,
    featureType: SpatialFeatureTypes.landParcel,
    geometryType: SpatialGeometryType.point,
    geometry: geometry,
    lifecycleStatus: SpatialFeatureLifecycleStatus.active,
    projectId: 'project-1',
    businessUnitId: 'unit-1',
    code: 'Mã-$id',
    name: name ?? 'Thửa Việt ລາວ $id',
    createdAt: DateTime.parse('2026-01-02T03:04:05+07:00'),
    createdBy: 'user-1',
    updatedAt: updatedAt ?? DateTime.parse('2026-01-03T03:04:05+07:00'),
    updatedBy: 'user-2',
    schemaVersion: 3,
  );

  SpatialFeatureRevision revision(
    String id,
    String featureId,
    int number, {
    SpatialPoint? geometry = point,
    String? geometryReference,
  }) => SpatialFeatureRevision(
    id: id,
    featureId: featureId,
    revision: number,
    geometryType: SpatialGeometryType.point,
    geometry: geometry,
    geometryReference: geometryReference ?? 'ref/$id',
    temporalState: SpatialTemporalState.asBuilt,
    effectivePeriod: SpatialEffectivePeriod(
      validFrom: DateTime.utc(2026, 2, number),
      validTo: DateTime.utc(2027, 2, number),
    ),
    source: SpatialSource(
      type: SpatialSourceType.survey,
      surveyedAt: DateTime.utc(2026, 1, number),
      surveyedBy: 'surveyor-ລາວ',
      horizontalAccuracyM: 0.02,
      sourceReference: 'job-$number',
      sourceFileName: 'ranh-giới-$number.dwg',
      sourceFileHash: 'sha256:$number',
      notes: 'Nguồn Việt ລາວ',
    ),
    changeReason: 'Điều chỉnh $number',
    notes: 'Lịch sử ທີ່ດິນ',
    createdAt: DateTime.utc(2026, 3, number),
    createdBy: 'user-$number',
    schemaVersion: 4,
  );

  void expectFeature(SpatialFeature? actual, SpatialFeature expected) {
    expect(actual, isNotNull);
    expect(
      SpatialFeatureJsonCodec.encode(actual!),
      SpatialFeatureJsonCodec.encode(expected),
    );
  }

  void expectRevision(
    SpatialFeatureRevision? actual,
    SpatialFeatureRevision expected,
  ) {
    expect(actual, isNotNull);
    expect(
      SpatialFeatureRevisionJsonCodec.encode(actual!),
      SpatialFeatureRevisionJsonCodec.encode(expected),
    );
  }

  late Database db;
  late SqliteSpatialFeatureRepository features;
  late SqliteSpatialFeatureRevisionRepository revisions;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    expect((await db.rawQuery('PRAGMA foreign_keys')).single.values.single, 1);
    await SqliteSpatialSchema.createSchema(db);
    features = SqliteSpatialFeatureRepository(db);
    revisions = SqliteSpatialFeatureRevisionRepository(db);
  });

  tearDown(() => db.close());

  group('SqliteSpatialFeatureRepository', () {
    test(
      'create/findById preserves complete Unicode geometry semantics',
      () async {
        final source = feature('feature-1');
        await features.create(source);
        expectFeature(await features.findById(source.id), source);
      },
    );

    test('create/findById preserves metadata-only feature', () async {
      final source = feature('feature-1', geometry: null);
      await features.create(source);
      expectFeature(await features.findById(source.id), source);
    });

    test('duplicate id is rejected and missing find returns null', () async {
      await features.create(feature('feature-1'));
      await expectLater(
        features.create(feature('feature-1')),
        throwsA(isA<DatabaseException>()),
      );
      expect(await features.findById('missing'), isNull);
    });

    test('findAll is deterministic by id ASC', () async {
      await features.create(feature('c'));
      await features.create(feature('a'));
      await features.create(feature('b'));
      expect((await features.findAll()).map((value) => value.id), [
        'a',
        'b',
        'c',
      ]);
    });

    test('update changes mutable fields and concrete geometry', () async {
      final source = feature('feature-1');
      await features.create(source);
      final changed = SpatialFeature(
        id: source.id,
        featureType: source.featureType,
        geometryType: source.geometryType,
        geometry: const SpatialPoint(
          coordinate: SpatialCoordinate(latitude: 17, longitude: 105),
        ),
        lifecycleStatus: SpatialFeatureLifecycleStatus.inactive,
        projectId: source.projectId,
        businessUnitId: source.businessUnitId,
        code: source.code,
        name: 'Tên mới ລາວ',
        createdAt: source.createdAt,
        createdBy: source.createdBy,
        updatedAt: DateTime.utc(2026, 4),
        updatedBy: 'user-3',
        schemaVersion: source.schemaVersion,
      );
      await features.update(changed);
      expectFeature(await features.findById(source.id), changed);
    });

    test('update missing throws and does not create', () async {
      await expectLater(features.update(feature('missing')), throwsStateError);
      expect(await features.findById('missing'), isNull);
    });

    test('delete existing succeeds and delete missing throws', () async {
      await features.create(feature('feature-1'));
      await features.deleteById('feature-1');
      expect(await features.findById('feature-1'), isNull);
      await expectLater(features.deleteById('feature-1'), throwsStateError);
    });

    test('FK RESTRICT rejects parent delete and preserves all rows', () async {
      final parent = feature('feature-1');
      final history = revision('revision-1', parent.id, 1);
      await features.create(parent);
      await revisions.create(history);
      await expectLater(
        features.deleteById(parent.id),
        throwsA(isA<DatabaseException>()),
      );
      expectFeature(await features.findById(parent.id), parent);
      expectRevision(await revisions.findById(history.id), history);
    });

    test(
      'corrupted scalar/payload disagreement surfaces FormatException',
      () async {
        final source = feature('feature-1');
        await features.create(source);
        await db.update(
          SqliteSpatialSchema.featuresTable,
          {'name': 'corrupt'},
          where: 'id = ?',
          whereArgs: [source.id],
        );
        await expectLater(features.findById(source.id), throwsFormatException);
      },
    );

    test('works with caller-owned Transaction and rolls back', () async {
      await expectLater(
        db.transaction((txn) async {
          final repository = SqliteSpatialFeatureRepository(txn);
          await repository.create(feature('rolled-back'));
          expectFeature(
            await repository.findById('rolled-back'),
            feature('rolled-back'),
          );
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await features.findById('rolled-back'), isNull);
    });
  });

  group('SqliteSpatialFeatureRevisionRepository', () {
    test(
      'create/findById preserves complete provenance and geometry',
      () async {
        await features.create(feature('feature-1'));
        final source = revision('revision-1', 'feature-1', 1);
        await revisions.create(source);
        expectRevision(await revisions.findById(source.id), source);
      },
    );

    test('legacy geometryReference and null geometry round-trip', () async {
      await features.create(feature('feature-1'));
      final source = revision('revision-1', 'feature-1', 1, geometry: null);
      await revisions.create(source);
      expectRevision(await revisions.findById(source.id), source);
    });

    test('duplicate id and duplicate feature/revision are rejected', () async {
      await features.create(feature('feature-1'));
      await revisions.create(revision('revision-1', 'feature-1', 1));
      await expectLater(
        revisions.create(revision('revision-1', 'feature-1', 2)),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        revisions.create(revision('revision-2', 'feature-1', 1)),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('same revision number is allowed for different features', () async {
      await features.create(feature('feature-1'));
      await features.create(feature('feature-2'));
      await revisions.create(revision('revision-1', 'feature-1', 1));
      await revisions.create(revision('revision-2', 'feature-2', 1));
      expect((await revisions.findByFeatureId('feature-1')).length, 1);
      expect((await revisions.findByFeatureId('feature-2')).length, 1);
    });

    test('orphan revision is rejected by FK', () async {
      await expectLater(
        revisions.create(revision('revision-1', 'missing', 1)),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('missing and empty read semantics are explicit', () async {
      expect(await revisions.findById('missing'), isNull);
      expect(await revisions.findByFeatureId('missing'), isEmpty);
      expect(await revisions.findLatestByFeatureId('missing'), isNull);
    });

    test('history is ASC, latest is highest, and gaps are accepted', () async {
      await features.create(feature('feature-1'));
      await revisions.create(revision('revision-3', 'feature-1', 3));
      await revisions.create(revision('revision-1', 'feature-1', 1));
      await revisions.create(revision('revision-2', 'feature-1', 2));
      final history = await revisions.findByFeatureId('feature-1');
      expect(history.map((value) => value.revision), [1, 2, 3]);
      expect((await revisions.findLatestByFeatureId('feature-1'))!.revision, 3);
      expect(history.length, 3);
    });

    test(
      'corrupted scalar/payload disagreement surfaces FormatException',
      () async {
        await features.create(feature('feature-1'));
        final source = revision('revision-1', 'feature-1', 1);
        await revisions.create(source);
        await db.update(
          SqliteSpatialSchema.revisionsTable,
          {'source_type': 'manual'},
          where: 'id = ?',
          whereArgs: [source.id],
        );
        await expectLater(revisions.findById(source.id), throwsFormatException);
      },
    );

    test('Transaction-backed insert participates in caller rollback', () async {
      await features.create(feature('feature-1'));
      await expectLater(
        db.transaction((txn) async {
          final repository = SqliteSpatialFeatureRevisionRepository(txn);
          await repository.create(revision('rolled-back', 'feature-1', 1));
          expectRevision(
            await repository.findById('rolled-back'),
            revision('rolled-back', 'feature-1', 1),
          );
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await revisions.findById('rolled-back'), isNull);
    });

    test('API exposes append-only repository contract', () {
      expect(
        SqliteSpatialFeatureRevisionRepository(db),
        isA<SqliteSpatialFeatureRevisionRepository>(),
      );
    });
  });

  test(
    'feature and revision repositories share one caller transaction',
    () async {
      await db.transaction((txn) async {
        final featureRepository = SqliteSpatialFeatureRepository(txn);
        final revisionRepository = SqliteSpatialFeatureRevisionRepository(txn);
        await featureRepository.create(feature('feature-1'));
        await revisionRepository.create(revision('revision-1', 'feature-1', 1));
      });
      expect((await features.findAll()).length, 1);
      expect((await revisions.findByFeatureId('feature-1')).length, 1);
    },
  );
}
