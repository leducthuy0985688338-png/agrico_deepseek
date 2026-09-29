import 'package:agrico_deepseek/core/spatial/data/spatial_persistence_composition.dart';
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

  SpatialFeature feature({
    required String id,
    DateTime? updatedAt,
    String? updatedBy,
    String? name,
  }) => SpatialFeature(
    id: id,
    featureType: SpatialFeatureTypes.landParcel,
    geometryType: SpatialGeometryType.point,
    geometry: point,
    lifecycleStatus: SpatialFeatureLifecycleStatus.active,
    projectId: 'project-1',
    businessUnitId: 'unit-1',
    code: 'parcel-$id',
    name: name ?? 'Parcel $id',
    createdAt: DateTime.utc(2026, 1, 1),
    createdBy: 'user-1',
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 2),
    updatedBy: updatedBy ?? 'user-2',
  );

  SpatialFeatureRevision revision({
    required String id,
    required String featureId,
    required int number,
  }) => SpatialFeatureRevision(
    id: id,
    featureId: featureId,
    revision: number,
    geometryType: SpatialGeometryType.point,
    geometry: point,
    geometryReference: 'ref/$id',
    temporalState: SpatialTemporalState.asBuilt,
    effectivePeriod: SpatialEffectivePeriod(
      validFrom: DateTime.utc(2026, number, 1),
      validTo: DateTime.utc(2027, number, 1),
    ),
    source: SpatialSource(
      type: SpatialSourceType.survey,
      surveyedAt: DateTime.utc(2026, 1, 15),
      surveyedBy: 'surveyor-1',
      horizontalAccuracyM: 0.02,
      sourceReference: 'survey-$number',
    ),
    changeReason: 'Revision $number',
    createdAt: DateTime.utc(2026, number, 2),
    createdBy: 'user-1',
  );

  late Database db;
  late SpatialPersistenceComposition spatial;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await SqliteSpatialSchema.createSchema(db);

    spatial = SpatialPersistenceComposition(db);
  });

  tearDown(() => db.close());

  test('wires SQLite repositories and atomic create workflow', () async {
    final sourceFeature = feature(id: 'feature-1');
    final initialRevision = revision(
      id: 'revision-1',
      featureId: sourceFeature.id,
      number: 1,
    );

    await spatial.createFeature.execute(
      feature: sourceFeature,
      initialRevision: initialRevision,
    );

    final storedFeature = await spatial.featureRepository.findById(
      sourceFeature.id,
    );
    final history = await spatial.revisionRepository.findByFeatureId(
      sourceFeature.id,
    );

    expect(storedFeature, isNotNull);
    expect(storedFeature!.id, sourceFeature.id);
    expect(history.length, 1);
    expect(history.single.revision, 1);
  });

  test('wires atomic update workflow to the same persistence store', () async {
    final original = feature(id: 'feature-1');

    await spatial.createFeature.execute(
      feature: original,
      initialRevision: revision(
        id: 'revision-1',
        featureId: original.id,
        number: 1,
      ),
    );

    final updated = feature(
      id: original.id,
      name: 'Updated parcel',
      updatedAt: DateTime.utc(2026, 3, 1),
      updatedBy: 'user-3',
    );

    await spatial.updateFeature.execute(
      feature: updated,
      revision: revision(id: 'revision-2', featureId: updated.id, number: 2),
    );

    final storedFeature = await spatial.featureRepository.findById(updated.id);
    final history = await spatial.revisionRepository.findByFeatureId(
      updated.id,
    );

    expect(storedFeature, isNotNull);
    expect(storedFeature!.name, 'Updated parcel');
    expect(storedFeature.updatedBy, 'user-3');

    expect(history.length, 2);
    expect(history.map((item) => item.revision).toList(), [1, 2]);
  });
}
