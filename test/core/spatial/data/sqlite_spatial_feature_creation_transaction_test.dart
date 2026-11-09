import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_feature_creation_transaction.dart';
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

  SpatialFeature feature(String id, {SpatialPoint? geometry = point}) => SpatialFeature(
    id: id,
    featureType: SpatialFeatureTypes.landParcel,
    geometryType: SpatialGeometryType.point,
    geometry: geometry,
    lifecycleStatus: SpatialFeatureLifecycleStatus.active,
    projectId: 'project-1',
    businessUnitId: 'unit-1',
    code: 'parcel-$id',
    name: 'Parcel $id',
    createdAt: DateTime.utc(2026, 1, 1),
    createdBy: 'user-1',
    updatedAt: DateTime.utc(2026, 1, 2),
    updatedBy: 'user-2',
  );

  SpatialFeatureRevision revision(String id, String featureId, int number,
          {SpatialPoint? geometry = point}) =>
      SpatialFeatureRevision(
        id: id,
        featureId: featureId,
        revision: number,
        geometryType: SpatialGeometryType.point,
        geometry: geometry,
        geometryReference: 'ref/$id',
        temporalState: SpatialTemporalState.asBuilt,
        effectivePeriod: SpatialEffectivePeriod(
          validFrom: DateTime.utc(2026, 2, 1),
          validTo: DateTime.utc(2027, 2, 1),
        ),
        source: SpatialSource(
          type: SpatialSourceType.survey,
          surveyedAt: DateTime.utc(2026, 1, 15),
          surveyedBy: 'surveyor-1',
          horizontalAccuracyM: 0.02,
          sourceReference: 'survey-1',
        ),
        changeReason: 'Initial survey',
        createdAt: DateTime.utc(2026, 2, 2),
        createdBy: 'user-1',
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

  group('SqliteSpatialFeatureCreationTransaction', () {
    test('rejects unequal and one-null pairs without persistence', () async {
      const different = SpatialPoint(coordinate: SpatialCoordinate(latitude: 17, longitude: 105));
      final pairs = [
        (feature('different'), revision('different-r1', 'different', 1, geometry: different)),
        (feature('feature-null', geometry: null), revision('feature-null-r1', 'feature-null', 1)),
        (feature('revision-null'), revision('revision-null-r1', 'revision-null', 1, geometry: null)),
      ];
      for (final (source, initial) in pairs) {
        await expectLater(
          SqliteSpatialFeatureCreationTransaction(db).create(feature: source, initialRevision: initial),
          throwsFormatException,
        );
        expect(await features.findById(source.id), isNull);
        expect(await revisions.findByFeatureId(source.id), isEmpty);
      }
    });

    test('accepts null/null legacy creation and persistence round-trip', () async {
      final source = feature('legacy', geometry: null);
      await SqliteSpatialFeatureCreationTransaction(db).create(
        feature: source,
        initialRevision: revision('legacy-r1', source.id, 1, geometry: null),
      );
      expect((await features.findById(source.id))!.geometry, isNull);
      expect((await revisions.findByFeatureId(source.id)).single.geometry, isNull);
    });
    test('creates feature and revision 1 atomically', () async {
      final sourceFeature = feature('feature-1');
      final sourceRevision = revision('revision-1', sourceFeature.id, 1);

      final transaction = SqliteSpatialFeatureCreationTransaction(db);

      await transaction.create(
        feature: sourceFeature,
        initialRevision: sourceRevision,
      );

      expect(await features.findById(sourceFeature.id), isNotNull);

      final history = await revisions.findByFeatureId(sourceFeature.id);
      expect(history.length, 1);
      expect(history.single.id, sourceRevision.id);
      expect(history.single.revision, 1);
    });

    test('rejects initial revision other than 1 without writing', () async {
      final sourceFeature = feature('feature-1');

      final transaction = SqliteSpatialFeatureCreationTransaction(db);

      await expectLater(
        transaction.create(
          feature: sourceFeature,
          initialRevision: revision('revision-2', sourceFeature.id, 2),
        ),
        throwsStateError,
      );

      expect(await features.findById(sourceFeature.id), isNull);
      expect(await revisions.findByFeatureId(sourceFeature.id), isEmpty);
    });

    test(
      'rejects revision belonging to another feature without writing',
      () async {
        final sourceFeature = feature('feature-1');

        final transaction = SqliteSpatialFeatureCreationTransaction(db);

        await expectLater(
          transaction.create(
            feature: sourceFeature,
            initialRevision: revision('revision-1', 'another-feature', 1),
          ),
          throwsFormatException,
        );

        expect(await features.findById(sourceFeature.id), isNull);
        expect(await revisions.findByFeatureId(sourceFeature.id), isEmpty);
      },
    );

    test('revision insert failure rolls back feature insert', () async {
      final existingFeature = feature('existing-feature');
      await features.create(existingFeature);

      await revisions.create(
        revision('duplicate-revision-id', existingFeature.id, 1),
      );

      final newFeature = feature('new-feature');

      final transaction = SqliteSpatialFeatureCreationTransaction(db);

      await expectLater(
        transaction.create(
          feature: newFeature,
          initialRevision: revision('duplicate-revision-id', newFeature.id, 1),
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(await features.findById(newFeature.id), isNull);

      expect(await revisions.findByFeatureId(newFeature.id), isEmpty);

      expect(await features.findById(existingFeature.id), isNotNull);

      expect((await revisions.findByFeatureId(existingFeature.id)).length, 1);
    });

    test('duplicate feature failure leaves existing state unchanged', () async {
      final existingFeature = feature('feature-1');
      await features.create(existingFeature);

      final transaction = SqliteSpatialFeatureCreationTransaction(db);

      await expectLater(
        transaction.create(
          feature: feature('feature-1'),
          initialRevision: revision('new-revision', 'feature-1', 1),
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(await features.findById('feature-1'), isNotNull);
      expect(await revisions.findByFeatureId('feature-1'), isEmpty);
    });

    test('reuses caller-owned Transaction without nesting', () async {
      final sourceFeature = feature('feature-1');

      await db.transaction((txn) async {
        final transaction = SqliteSpatialFeatureCreationTransaction(txn);

        await transaction.create(
          feature: sourceFeature,
          initialRevision: revision('revision-1', sourceFeature.id, 1),
        );

        final scopedFeatures = SqliteSpatialFeatureRepository(txn);
        final scopedRevisions = SqliteSpatialFeatureRevisionRepository(txn);

        expect(await scopedFeatures.findById(sourceFeature.id), isNotNull);

        expect(
          (await scopedRevisions.findByFeatureId(sourceFeature.id)).length,
          1,
        );
      });

      expect(await features.findById(sourceFeature.id), isNotNull);
      expect((await revisions.findByFeatureId(sourceFeature.id)).length, 1);
    });

    test('participates in caller-owned rollback', () async {
      final sourceFeature = feature('rolled-back-feature');

      await expectLater(
        db.transaction((txn) async {
          final transaction = SqliteSpatialFeatureCreationTransaction(txn);

          await transaction.create(
            feature: sourceFeature,
            initialRevision: revision(
              'rolled-back-revision',
              sourceFeature.id,
              1,
            ),
          );

          throw StateError('caller rollback');
        }),
        throwsStateError,
      );

      expect(await features.findById(sourceFeature.id), isNull);
      expect(await revisions.findByFeatureId(sourceFeature.id), isEmpty);
    });
  });
}
