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

  const point = SpatialPoint(
    coordinate: SpatialCoordinate(latitude: 16.5, longitude: 104.7),
  );

  final createdAt = DateTime.utc(2026, 1, 1);
  final updatedAt = DateTime.utc(2026, 6, 1);

  SpatialFeature buildFeature({
    String id = 'F1',
    String? name,
    DateTime? updateTime,
  }) =>
      SpatialFeature(
        id: id,
        featureType: SpatialFeatureTypes.landParcel,
        geometryType: SpatialGeometryType.point,
        geometry: point,
        lifecycleStatus: SpatialFeatureLifecycleStatus.active,
        name: name,
        createdAt: createdAt,
        createdBy: 'user-1',
        updatedAt: updateTime ?? updatedAt,
        updatedBy: 'user-2',
      );

  SpatialFeatureRevision buildRevision({
    required String id,
    required String featureId,
    required int revision,
  }) =>
      SpatialFeatureRevision(
        id: id,
        featureId: featureId,
        revision: revision,
        geometryType: SpatialGeometryType.point,
        geometry: point,
        geometryReference: 'ref/$id',
        temporalState: revision == 1
            ? SpatialTemporalState.baseline
            : SpatialTemporalState.operational,
        effectivePeriod: SpatialEffectivePeriod(validFrom: createdAt),
        source: const SpatialSource(type: SpatialSourceType.survey),
        createdAt: createdAt,
        createdBy: 'user-1',
      );

  late Database db;
  late SqliteSpatialFeatureRepository features;
  late SqliteSpatialFeatureRevisionRepository revisions;
  late SqliteSpatialFeatureRevisionUpdateTransaction transaction;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await SqliteSpatialSchema.createSchema(db);

    features = SqliteSpatialFeatureRepository(db);
    revisions = SqliteSpatialFeatureRevisionRepository(db);
    transaction = SqliteSpatialFeatureRevisionUpdateTransaction(db);
  });

  tearDown(() => db.close());

  Future<void> seedF1WithR1() async {
    await features.create(buildFeature(id: 'F1', name: 'Original'));
    await revisions.create(
      buildRevision(id: 'R1', featureId: 'F1', revision: 1),
    );
  }

  // ============================================================
  // A. REVISION SEQUENCE CONTRACT
  // ============================================================
  group('A. Revision sequence contract', () {
    // ----------------------------------------------------------
    // A1: F1 + R1 → R2 → R3 qua real SQLite transaction
    //     Assert: identity + sequence + persistence
    // ----------------------------------------------------------
    test(
      'A1. R1 → R2 → R3: identity, sequence, and persistence intact',
      () async {
        await seedF1WithR1();

        // Update to R2
        await transaction.update(
          feature: buildFeature(id: 'F1', name: 'After R2'),
          revision: buildRevision(id: 'R2', featureId: 'F1', revision: 2),
        );

        // Update to R3
        await transaction.update(
          feature: buildFeature(id: 'F1', name: 'After R3'),
          revision: buildRevision(id: 'R3', featureId: 'F1', revision: 3),
        );

        // Re-read from SQLite
        final f1 = await features.findById('F1');
        final r1 = await revisions.findById('R1');
        final r2 = await revisions.findById('R2');
        final r3 = await revisions.findById('R3');
        final history = await revisions.findByFeatureId('F1');

        // Identity: F1.id must remain "F1"
        expect(f1, isNotNull);
        expect(f1!.id, 'F1');

        // Persistence: all 3 revisions exist
        expect(r1, isNotNull);
        expect(r2, isNotNull);
        expect(r3, isNotNull);

        // Identity chain: all revisions reference F1.id
        expect(r1!.featureId, f1.id);
        expect(r2!.featureId, f1.id);
        expect(r3!.featureId, f1.id);
        expect(r1.featureId, 'F1');
        expect(r2.featureId, 'F1');
        expect(r3.featureId, 'F1');

        // Sequence: 1, 2, 3
        expect(r1.revision, 1);
        expect(r2.revision, 2);
        expect(r3.revision, 3);

        // History: exactly 3 revisions in order
        expect(history.map((r) => r.revision).toList(), [1, 2, 3]);

        // Latest: R3
        final latest = await revisions.findLatestByFeatureId('F1');
        expect(latest, isNotNull);
        expect(latest!.revision, 3);
        expect(latest.id, 'R3');
      },
    );

    // ----------------------------------------------------------
    // A2: Reject gap — attempt R3 when latest = R1
    // ----------------------------------------------------------
    test('A2. rejects gap: R3 when latest is R1', () async {
      await seedF1WithR1();

      await expectLater(
        transaction.update(
          feature: buildFeature(id: 'F1', name: 'Gap attempt'),
          revision: buildRevision(id: 'R3', featureId: 'F1', revision: 3),
        ),
        throwsStateError,
      );

      // State unchanged
      final f1 = await features.findById('F1');
      final history = await revisions.findByFeatureId('F1');

      expect(f1, isNotNull);
      expect(f1!.name, 'Original');
      expect(history.length, 1);
      expect(history.single.revision, 1);

      // R3 must NOT exist
      expect(await revisions.findById('R3'), isNull);
    });

    // ----------------------------------------------------------
    // A3: Reject duplicate — attempt R2 when R2 already exists
    // ----------------------------------------------------------
    test('A3. rejects duplicate: R2 when R2 already exists', () async {
      await seedF1WithR1();

      // First, create R2 legitimately
      await transaction.update(
        feature: buildFeature(id: 'F1', name: 'After R2'),
        revision: buildRevision(id: 'R2', featureId: 'F1', revision: 2),
      );

      // Attempt duplicate R2 (with different id) → expect failure
      await expectLater(
        transaction.update(
          feature: buildFeature(id: 'F1', name: 'Duplicate R2 attempt'),
          revision: buildRevision(id: 'R2-dup', featureId: 'F1', revision: 2),
        ),
        throwsStateError,
      );

      // State must remain at R2 (latest = 2), not advance to R3
      final history = await revisions.findByFeatureId('F1');
      expect(history.length, 2);
      expect(history.map((r) => r.revision).toList(), [1, 2]);
      expect(await revisions.findById('R2-dup'), isNull);
    });

    // ----------------------------------------------------------
    // A4: Reject backward — attempt R1 when latest = R2
    // ----------------------------------------------------------
    test('A4. rejects backward: R1 when latest is R2', () async {
      await seedF1WithR1();

      // Create R2 legitimately
      await transaction.update(
        feature: buildFeature(id: 'F1', name: 'After R2'),
        revision: buildRevision(id: 'R2', featureId: 'F1', revision: 2),
      );

      // Attempt backward R1 (with different id)
      await expectLater(
        transaction.update(
          feature: buildFeature(id: 'F1', name: 'Backward attempt'),
          revision: buildRevision(id: 'R1-back', featureId: 'F1', revision: 1),
        ),
        throwsStateError,
      );

      // State unchanged: still R1, R2
      final history = await revisions.findByFeatureId('F1');
      expect(history.length, 2);
      expect(history.map((r) => r.revision).toList(), [1, 2]);
      expect(await revisions.findById('R1-back'), isNull);
    });
  });

  // ============================================================
  // B. ATOMIC UPDATE
  // ============================================================
  group('B. Atomic update', () {
    // ----------------------------------------------------------
    // B1: Successful atomic transaction
    // ----------------------------------------------------------
    test('B1. successful atomic update persists both feature and revision',
        () async {
      await seedF1WithR1();

      await transaction.update(
        feature: buildFeature(id: 'F1', name: 'Updated'),
        revision: buildRevision(id: 'R2', featureId: 'F1', revision: 2),
      );

      // Feature snapshot updated
      final f1 = await features.findById('F1');
      expect(f1, isNotNull);
      expect(f1!.name, 'Updated');

      // Revision history: R1 + R2
      final history = await revisions.findByFeatureId('F1');
      expect(history.length, 2);
      expect(history.map((r) => r.revision).toList(), [1, 2]);
    });

    // ----------------------------------------------------------
    // B2: Revision failure → feature rollback
    //     Use duplicate revision id (existing legitimate mechanism)
    // ----------------------------------------------------------
    test('B2. revision failure rolls back feature update', () async {
      await seedF1WithR1();

      // Create a conflicting revision on a different feature (legitimate)
      await features.create(buildFeature(id: 'F-other', name: 'Other'));
      await revisions.create(
        buildRevision(id: 'duplicate-revision-id', featureId: 'F-other', revision: 1),
      );

      // Attempt update on F1 with duplicate revision id → expect DB failure
      await expectLater(
        transaction.update(
          feature: buildFeature(id: 'F1', name: 'Should rollback'),
          revision: buildRevision(
            id: 'duplicate-revision-id',
            featureId: 'F1',
            revision: 2,
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );

      // Feature F1 must remain at "Original"
      final f1 = await features.findById('F1');
      expect(f1, isNotNull);
      expect(f1!.name, 'Original');

      // F1 must still have only R1
      final history = await revisions.findByFeatureId('F1');
      expect(history.length, 1);
      expect(history.single.revision, 1);
    });
        // ----------------------------------------------------------
    // B3: Each spatial feature maintains an independent sequence
    //     (migrated from spatial_feature_revision_sequence_test.dart)
    // ----------------------------------------------------------
    test('B3. each spatial feature maintains independent revision sequence',
        () async {
      // Seed F1 + R1
      await features.create(buildFeature(id: 'F1', name: 'Feature 1'));
      await revisions.create(
        buildRevision(id: 'F1-R1', featureId: 'F1', revision: 1),
      );

      // Seed F2 + R1
      await features.create(buildFeature(id: 'F2', name: 'Feature 2'));
      await revisions.create(
        buildRevision(id: 'F2-R1', featureId: 'F2', revision: 1),
      );

      // Update F1 to revision 2
      await transaction.update(
        feature: buildFeature(id: 'F1', name: 'Feature 1 v2'),
        revision: buildRevision(id: 'F1-R2', featureId: 'F1', revision: 2),
      );

      // Update F2 to revision 2
      await transaction.update(
        feature: buildFeature(id: 'F2', name: 'Feature 2 v2'),
        revision: buildRevision(id: 'F2-R2', featureId: 'F2', revision: 2),
      );

      // Read back both sequences from SQLite
      final f1History = await revisions.findByFeatureId('F1');
      final f2History = await revisions.findByFeatureId('F2');
      final f1Latest = await revisions.findLatestByFeatureId('F1');
      final f2Latest = await revisions.findLatestByFeatureId('F2');

      // F1 history: R1, R2
      expect(f1History.map((r) => r.revision).toList(), [1, 2]);
      expect(f1History.every((r) => r.featureId == 'F1'), isTrue);
      expect(f1Latest, isNotNull);
      expect(f1Latest!.revision, 2);

      // F2 history: R1, R2
      expect(f2History.map((r) => r.revision).toList(), [1, 2]);
      expect(f2History.every((r) => r.featureId == 'F2'), isTrue);
      expect(f2Latest, isNotNull);
      expect(f2Latest!.revision, 2);

      // Sequences are independent: F1's R2 does not affect F2's sequence
      expect(f1History.length, 2);
      expect(f2History.length, 2);
    });
  });
}