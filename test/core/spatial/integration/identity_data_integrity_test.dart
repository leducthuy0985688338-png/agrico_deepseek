import 'dart:convert';

import 'package:agrico_deepseek/core/spatial/data/spatial_feature_json_codec.dart';
import 'package:agrico_deepseek/core/spatial/data/spatial_feature_revision_json_codec.dart';
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
        updatedAt: updatedAt,
        updatedBy: 'user-2',
      );

  SpatialFeatureRevision buildRevision({
    required String id,
    required String featureId,
    required int revision,
    String? notes,
    SpatialSource? source,
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
        source: source ?? const SpatialSource(type: SpatialSourceType.survey),
        notes: notes,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

  // ============================================================
  // A. STABLE SpatialFeature ID across update
  // ============================================================
  group('A. Stable SpatialFeature identity', () {
    test('SpatialFeature.id is unchanged after update transaction', () async {
      // Setup SQLite + schema
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('PRAGMA foreign_keys = ON');
      await SqliteSpatialSchema.createSchema(db);

      final features = SqliteSpatialFeatureRepository(db);
      final revisions = SqliteSpatialFeatureRevisionRepository(db);
      final transaction = SqliteSpatialFeatureRevisionUpdateTransaction(db);

      // Create F1 with R1
      final f1 = buildFeature(id: 'F1', name: 'Original name');
      await features.create(f1);
      await revisions.create(
        buildRevision(id: 'R1', featureId: 'F1', revision: 1),
      );

      // Capture id before update
      final idBeforeUpdate = f1.id;
      expect(idBeforeUpdate, 'F1');

      // Perform update via real transaction flow
      final f1Updated = buildFeature(id: 'F1', name: 'Updated name');
      await transaction.update(
        feature: f1Updated,
        revision: buildRevision(id: 'R2', featureId: 'F1', revision: 2),
      );

      // Read feature back from repository
      final stored = await features.findById('F1');
      expect(stored, isNotNull);

      // Assert: id after update == id before update
      final idAfterUpdate = stored!.id;
      expect(idAfterUpdate, idBeforeUpdate);
      expect(idAfterUpdate, 'F1');

      // Sanity: name did change, only id is stable
      expect(stored.name, 'Updated name');

      await db.close();
    });
  });

  // ============================================================
  // B. Revision identity chain R1, R2, R3 → F1
  // ============================================================
  group('B. Revision identity chain', () {
    test('R1, R2, R3 all reference F1.id with revision 1, 2, 3', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('PRAGMA foreign_keys = ON');
      await SqliteSpatialSchema.createSchema(db);

      final features = SqliteSpatialFeatureRepository(db);
      final revisions = SqliteSpatialFeatureRevisionRepository(db);

      final f1 = buildFeature(id: 'F1');
      await features.create(f1);

      await revisions.create(
        buildRevision(id: 'R1', featureId: 'F1', revision: 1),
      );
      await revisions.create(
        buildRevision(id: 'R2', featureId: 'F1', revision: 2),
      );
      await revisions.create(
        buildRevision(id: 'R3', featureId: 'F1', revision: 3),
      );

      final r1 = await revisions.findById('R1');
      final r2 = await revisions.findById('R2');
      final r3 = await revisions.findById('R3');

      expect(r1, isNotNull);
      expect(r2, isNotNull);
      expect(r3, isNotNull);

      // Chain: all revisions reference F1.id
      expect(r1!.featureId, f1.id);
      expect(r2!.featureId, f1.id);
      expect(r3!.featureId, f1.id);

      // Explicit equality across revisions
      expect(r1.featureId, r2.featureId);
      expect(r2.featureId, r3.featureId);
      expect(r1.featureId, 'F1');

      // Revision numbers
      expect(r1.revision, 1);
      expect(r2.revision, 2);
      expect(r3.revision, 3);

      await db.close();
    });
  });

  // ============================================================
  // C. JSON identity round-trip
  // ============================================================
  group('C. JSON identity round-trip', () {
    test('SpatialFeature.id survives JSON round-trip exactly', () {
      final original = buildFeature(id: 'F-JSON-001');

      final encoded = SpatialFeatureJsonCodec.encode(original);
      final decoded = SpatialFeatureJsonCodec.decode(
        jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>,
      );

      expect(decoded.id, original.id);
      expect(decoded.id, 'F-JSON-001');
    });

    test(
      'SpatialFeatureRevision.id, featureId, revision survive JSON round-trip exactly',
      () {
        final original = buildRevision(
          id: 'R-JSON-007',
          featureId: 'F-JSON-001',
          revision: 7,
        );

        final encoded = SpatialFeatureRevisionJsonCodec.encode(original);
        final decoded = SpatialFeatureRevisionJsonCodec.decode(
          jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>,
        );

        expect(decoded.id, original.id);
        expect(decoded.id, 'R-JSON-007');

        expect(decoded.featureId, original.featureId);
        expect(decoded.featureId, 'F-JSON-001');

        expect(decoded.revision, original.revision);
        expect(decoded.revision, 7);
      },
    );
  });

  // ============================================================
  // D. Unicode — Vietnamese
  // ============================================================
  group('D. Unicode Vietnamese round-trip', () {
    test('SpatialFeature.name preserves Vietnamese exactly', () {
      const vietnameseName = 'Nguyễn Văn Thùy';
      final original = buildFeature(id: 'F-VN-1', name: vietnameseName);

      final encoded = SpatialFeatureJsonCodec.encode(original);
      final decoded = SpatialFeatureJsonCodec.decode(
        jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>,
      );

      expect(decoded.name, vietnameseName);
      expect(decoded.name, 'Nguyễn Văn Thùy');
    });

    test('SpatialFeatureRevision.notes preserves Vietnamese exactly', () {
      const vietnameseNotes = 'Bản Tân Lập';
      final original = buildRevision(
        id: 'R-VN-1',
        featureId: 'F-VN-1',
        revision: 1,
        notes: vietnameseNotes,
      );

      final encoded = SpatialFeatureRevisionJsonCodec.encode(original);
      final decoded = SpatialFeatureRevisionJsonCodec.decode(
        jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>,
      );

      expect(decoded.notes, vietnameseNotes);
      expect(decoded.notes, 'Bản Tân Lập');
    });
  });

  // ============================================================
  // E. Unicode — Lao
  // ============================================================
  group('E. Unicode Lao round-trip', () {
    test('SpatialFeature.name preserves Lao exactly', () {
      const laoName = 'ນາງ ສີດາ';
      final original = buildFeature(id: 'F-LAO-1', name: laoName);

      final encoded = SpatialFeatureJsonCodec.encode(original);
      final decoded = SpatialFeatureJsonCodec.decode(
        jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>,
      );

      expect(decoded.name, laoName);
      expect(decoded.name, 'ນາງ ສີດາ');
    });

    test('SpatialFeatureRevision.notes preserves Lao exactly', () {
      const laoNotes = 'ບ້ານຕາໂກ';
      final original = buildRevision(
        id: 'R-LAO-1',
        featureId: 'F-LAO-1',
        revision: 1,
        notes: laoNotes,
      );

      final encoded = SpatialFeatureRevisionJsonCodec.encode(original);
      final decoded = SpatialFeatureRevisionJsonCodec.decode(
        jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>,
      );

      expect(decoded.notes, laoNotes);
      expect(decoded.notes, 'ບ້ານຕາໂກ');
    });

    test('SpatialSource.notes preserves Lao exactly', () {
      const laoSourceNotes = 'ດິນນາຂອງຄອບຄົວ';
      final original = buildRevision(
        id: 'R-LAO-2',
        featureId: 'F-LAO-1',
        revision: 2,
        source: const SpatialSource(
          type: SpatialSourceType.survey,
          notes: laoSourceNotes,
        ),
      );

      final encoded = SpatialFeatureRevisionJsonCodec.encode(original);
      final decoded = SpatialFeatureRevisionJsonCodec.decode(
        jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>,
      );

      expect(decoded.source.notes, laoSourceNotes);
      expect(decoded.source.notes, 'ດິນນາຂອງຄອບຄົວ');
    });
  });
}