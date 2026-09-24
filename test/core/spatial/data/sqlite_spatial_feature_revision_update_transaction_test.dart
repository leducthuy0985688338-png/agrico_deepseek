import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_feature_repository.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_feature_revision_repository.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_feature_revision_update_transaction.dart';
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

  const initialPoint = SpatialPoint(
    coordinate: SpatialCoordinate(latitude: 16.5, longitude: 104.7),
  );

  const updatedPoint = SpatialPoint(
    coordinate: SpatialCoordinate(latitude: 16.6, longitude: 104.8),
  );

  SpatialFeature feature(
    String id, {
    SpatialPoint? geometry = initialPoint,
    String? featureType,
    DateTime? createdAt,
    String? createdBy,
    String? name,
    DateTime? updatedAt,
  }) => SpatialFeature(
    id: id,
    featureType: featureType ?? SpatialFeatureTypes.landParcel,
    geometryType: SpatialGeometryType.point,
    geometry: geometry,
    lifecycleStatus: SpatialFeatureLifecycleStatus.active,
    projectId: 'project-1',
    businessUnitId: 'unit-1',
    code: 'parcel-$id',
    name: name ?? 'Parcel $id',
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    createdBy: createdBy ?? 'user-1',
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 2),
    updatedBy: 'user-2',
  );

  SpatialFeature updatedFeature(
    SpatialFeature source, {
    SpatialPoint? geometry = updatedPoint,
    String? featureType,
    DateTime? createdAt,
    String? createdBy,
  }) => SpatialFeature(
    id: source.id,
    featureType: featureType ?? source.featureType,
    geometryType: source.geometryType,
    geometry: geometry,
    lifecycleStatus: SpatialFeatureLifecycleStatus.inactive,
    projectId: source.projectId,
    businessUnitId: source.businessUnitId,
    code: source.code,
    name: 'Updated ${source.id}',
    createdAt: createdAt ?? source.createdAt,
    createdBy: createdBy ?? source.createdBy,
    updatedAt: DateTime.utc(2026, 4, 1),
    updatedBy: 'user-3',
    schemaVersion: source.schemaVersion,
  );

  SpatialFeatureRevision revision(
    String id,
    String featureId,
    int number, {
    SpatialPoint? geometry,
    bool nullGeometry = false,
  }) => SpatialFeatureRevision(
    id: id,
    featureId: featureId,
    revision: number,
    geometryType: SpatialGeometryType.point,
    geometry: nullGeometry ? null : geometry ?? (number == 1 ? initialPoint : updatedPoint),
    geometryReference: 'ref/$id',
    temporalState: SpatialTemporalState.asBuilt,
    effectivePeriod: SpatialEffectivePeriod(
      validFrom: DateTime.utc(2026, 2, number),
      validTo: DateTime.utc(2027, 2, number),
    ),
    source: SpatialSource(
      type: SpatialSourceType.survey,
      surveyedAt: DateTime.utc(2026, 1, number),
      surveyedBy: 'surveyor-1',
      horizontalAccuracyM: 0.02,
      sourceReference: 'survey-$number',
    ),
    changeReason: 'Revision $number',
    createdAt: DateTime.utc(2026, 3, number),
    createdBy: 'user-$number',
  );

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

  Future<SpatialFeature> seedFeature(String id) async {
    final source = feature(id);
    await features.create(source);
    await revisions.create(revision('revision-$id-1', id, 1));
    return source;
  }

  group('SqliteSpatialFeatureRevisionUpdateTransaction', () {
    test('rejects unequal and one-null pairs without mutation or new revision', () async {
      final original = await seedFeature('pair');
      const different = SpatialPoint(coordinate: SpatialCoordinate(latitude: 17, longitude: 105));
      final pairs = [
        (updatedFeature(original), revision('wrong-r2', original.id, 2, geometry: different)),
        (updatedFeature(original, geometry: null), revision('feature-null-r2', original.id, 2)),
        (updatedFeature(original), revision('revision-null-r2', original.id, 2, nullGeometry: true)),
      ];
      for (final (changed, next) in pairs) {
        await expectLater(
          SqliteSpatialFeatureRevisionUpdateTransaction(db).update(feature: changed, revision: next),
          throwsFormatException,
        );
        expect((await features.findById(original.id))!.name, original.name);
        expect(
          ((await features.findById(original.id))!.geometry as SpatialPoint).coordinate,
          initialPoint.coordinate,
        );
        expect((await revisions.findByFeatureId(original.id)).length, 1);
      }
    });

    test('accepts null/null legacy update', () async {
      final original = feature('legacy', geometry: null);
      await features.create(original);
      await revisions.create(revision('legacy-r1', original.id, 1, nullGeometry: true));
      await SqliteSpatialFeatureRevisionUpdateTransaction(db).update(
        feature: updatedFeature(original, geometry: null),
        revision: revision('legacy-r2', original.id, 2, nullGeometry: true),
      );
      expect((await features.findById(original.id))!.geometry, isNull);
      expect((await revisions.findByFeatureId(original.id)).length, 2);
    });
    test(
      'updates snapshot and appends exact next revision atomically',
      () async {
        final original = await seedFeature('feature-1');
        final changed = updatedFeature(original);

        final transaction = SqliteSpatialFeatureRevisionUpdateTransaction(db);

        await transaction.update(
          feature: changed,
          revision: revision(
            'revision-feature-1-2',
            changed.id,
            2,
            geometry: updatedPoint,
          ),
        );

        final stored = await features.findById(changed.id);
        expect(stored, isNotNull);
        expect(stored!.name, changed.name);
        expect(stored.lifecycleStatus, changed.lifecycleStatus);
        expect(stored.updatedBy, changed.updatedBy);

        final history = await revisions.findByFeatureId(changed.id);
        expect(history.map((value) => value.revision), [1, 2]);
      },
    );

    test('rejects revision below 2 before writing', () async {
      final original = await seedFeature('feature-1');
      final changed = updatedFeature(original);

      final transaction = SqliteSpatialFeatureRevisionUpdateTransaction(db);

      await expectLater(
        transaction.update(
          feature: changed,
          revision: revision(
            'invalid-revision',
            changed.id,
            1,
            geometry: updatedPoint,
          ),
        ),
        throwsStateError,
      );

      final stored = await features.findById(original.id);
      expect(stored!.name, original.name);
      expect((await revisions.findByFeatureId(original.id)).length, 1);
    });

    test('rejects missing feature', () async {
      final missing = feature('missing', geometry: updatedPoint);

      final transaction = SqliteSpatialFeatureRevisionUpdateTransaction(db);

      await expectLater(
        transaction.update(
          feature: missing,
          revision: revision('revision-missing-2', missing.id, 2),
        ),
        throwsStateError,
      );

      expect(await features.findById(missing.id), isNull);
    });

    test('rejects feature without revision history', () async {
      final source = feature('feature-1');
      await features.create(source);

      final transaction = SqliteSpatialFeatureRevisionUpdateTransaction(db);

      await expectLater(
        transaction.update(
          feature: updatedFeature(source),
          revision: revision('revision-2', source.id, 2),
        ),
        throwsStateError,
      );

      final stored = await features.findById(source.id);
      expect(stored!.name, source.name);
      expect(await revisions.findByFeatureId(source.id), isEmpty);
    });

    test('rejects revision gaps and duplicate revision numbers', () async {
      final original = await seedFeature('feature-1');
      final changed = updatedFeature(original);

      final transaction = SqliteSpatialFeatureRevisionUpdateTransaction(db);

      await expectLater(
        transaction.update(
          feature: changed,
          revision: revision('revision-gap', changed.id, 3),
        ),
        throwsStateError,
      );

      expect((await revisions.findByFeatureId(changed.id)).length, 1);

      await transaction.update(
        feature: changed,
        revision: revision('revision-2', changed.id, 2, geometry: updatedPoint),
      );

      await expectLater(
        transaction.update(
          feature: changed,
          revision: revision(
            'another-revision-2',
            changed.id,
            2,
            geometry: updatedPoint,
          ),
        ),
        throwsStateError,
      );

      expect(
        (await revisions.findByFeatureId(
          changed.id,
        )).map((value) => value.revision),
        [1, 2],
      );
    });

    test('rejects featureType mutation', () async {
      final original = await seedFeature('feature-1');

      final changed = updatedFeature(
        original,
        featureType: SpatialFeatureTypes.road,
      );

      final transaction = SqliteSpatialFeatureRevisionUpdateTransaction(db);

      await expectLater(
        transaction.update(
          feature: changed,
          revision: revision('revision-2', changed.id, 2),
        ),
        throwsStateError,
      );

      final stored = await features.findById(original.id);
      expect(stored!.featureType, original.featureType);
      expect((await revisions.findByFeatureId(original.id)).length, 1);
    });

    test('rejects createdAt mutation', () async {
      final original = await seedFeature('feature-1');

      final changed = updatedFeature(
        original,
        createdAt: DateTime.utc(2025, 1, 1),
      );

      final transaction = SqliteSpatialFeatureRevisionUpdateTransaction(db);

      await expectLater(
        transaction.update(
          feature: changed,
          revision: revision('revision-2', changed.id, 2),
        ),
        throwsStateError,
      );

      final stored = await features.findById(original.id);
      expect(stored!.createdAt, original.createdAt);
      expect((await revisions.findByFeatureId(original.id)).length, 1);
    });

    test('rejects createdBy mutation', () async {
      final original = await seedFeature('feature-1');

      final changed = updatedFeature(original, createdBy: 'different-creator');

      final transaction = SqliteSpatialFeatureRevisionUpdateTransaction(db);

      await expectLater(
        transaction.update(
          feature: changed,
          revision: revision('revision-2', changed.id, 2),
        ),
        throwsStateError,
      );

      final stored = await features.findById(original.id);
      expect(stored!.createdBy, original.createdBy);
      expect((await revisions.findByFeatureId(original.id)).length, 1);
    });

    test('revision insert failure rolls back snapshot update', () async {
      final original = await seedFeature('feature-1');

      final other = feature('other-feature');
      await features.create(other);
      await revisions.create(revision('duplicate-revision-id', other.id, 1));

      final changed = updatedFeature(original);

      final transaction = SqliteSpatialFeatureRevisionUpdateTransaction(db);

      await expectLater(
        transaction.update(
          feature: changed,
          revision: revision(
            'duplicate-revision-id',
            changed.id,
            2,
            geometry: updatedPoint,
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );

      final stored = await features.findById(original.id);
      expect(stored, isNotNull);
      expect(stored!.name, original.name);
      expect(stored.lifecycleStatus, original.lifecycleStatus);
      expect(stored.updatedBy, original.updatedBy);

      final history = await revisions.findByFeatureId(original.id);
      expect(history.length, 1);
      expect(history.single.revision, 1);

      expect((await revisions.findByFeatureId(other.id)).length, 1);
    });

    test('reuses caller-owned Transaction without nesting', () async {
      final original = await seedFeature('feature-1');
      final changed = updatedFeature(original);

      await db.transaction((txn) async {
        final transaction = SqliteSpatialFeatureRevisionUpdateTransaction(txn);

        await transaction.update(
          feature: changed,
          revision: revision(
            'revision-2',
            changed.id,
            2,
            geometry: updatedPoint,
          ),
        );

        final scopedFeatures = SqliteSpatialFeatureRepository(txn);
        final scopedRevisions = SqliteSpatialFeatureRevisionRepository(txn);

        expect((await scopedFeatures.findById(changed.id))!.name, changed.name);

        expect((await scopedRevisions.findByFeatureId(changed.id)).length, 2);
      });

      expect((await features.findById(changed.id))!.name, changed.name);
      expect((await revisions.findByFeatureId(changed.id)).length, 2);
    });

    test('participates in caller-owned rollback', () async {
      final original = await seedFeature('feature-1');
      final changed = updatedFeature(original);

      await expectLater(
        db.transaction((txn) async {
          final transaction = SqliteSpatialFeatureRevisionUpdateTransaction(
            txn,
          );

          await transaction.update(
            feature: changed,
            revision: revision(
              'revision-2',
              changed.id,
              2,
              geometry: updatedPoint,
            ),
          );

          throw StateError('caller rollback');
        }),
        throwsStateError,
      );

      final stored = await features.findById(original.id);
      expect(stored!.name, original.name);
      expect(stored.lifecycleStatus, original.lifecycleStatus);

      final history = await revisions.findByFeatureId(original.id);
      expect(history.length, 1);
      expect(history.single.revision, 1);
    });
  });
}
