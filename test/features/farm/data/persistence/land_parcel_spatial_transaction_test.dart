import 'package:agrico_deepseek/core/identity/data/sqlite_parcel_number_sequence.dart';
import 'package:agrico_deepseek/core/spatial/data/spatial_persistence_composition.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/land_parcel_spatial_transaction.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  final occurredAt = DateTime.utc(2026, 9, 11, 8);

  LandParcel parcel({String id = 'parcel-1', String code = 'P-001'}) =>
      LandParcel.create(
        id: id,
        farmId: 'farm-1',
        parcelCode: code,
        name: 'Parcel $id',
        boundary: Wgs84Polygon.fromVertices(const [
          Wgs84Vertex(latitude: 16.5, longitude: 104.7),
          Wgs84Vertex(latitude: 16.5, longitude: 104.701),
          Wgs84Vertex(latitude: 16.501, longitude: 104.7),
        ]),
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: occurredAt,
      );

  const point = SpatialPoint(
    coordinate: SpatialCoordinate(latitude: 16.5, longitude: 104.7),
  );

  SpatialFeature feature(String id) => SpatialFeature(
    id: id,
    featureType: SpatialFeatureTypes.landParcel,
    geometryType: SpatialGeometryType.point,
    geometry: point,
    lifecycleStatus: SpatialFeatureLifecycleStatus.active,
    projectId: 'farm-1',
    code: 'P-001',
    name: 'Parcel $id',
    createdAt: occurredAt,
    createdBy: 'member-1',
    updatedAt: occurredAt,
    updatedBy: 'member-1',
  );

  SpatialFeatureRevision revision(String featureId) => SpatialFeatureRevision(
    id: '$featureId-revision-1',
    featureId: featureId,
    revision: 1,
    geometryType: SpatialGeometryType.point,
    geometry: point,
    temporalState: SpatialTemporalState.operational,
    effectivePeriod: SpatialEffectivePeriod(validFrom: occurredAt),
    source: SpatialSource(
      type: SpatialSourceType.survey,
      surveyedAt: occurredAt,
      surveyedBy: 'member-1',
    ),
    createdAt: occurredAt,
    createdBy: 'member-1',
  );

  late Database database;
  late SqliteLandParcelRepository parcels;
  late SpatialPersistenceComposition spatial;
  late LandParcelSpatialTransaction coordinator;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');
    await SqliteLandParcelRepository.createSchema(database);
    await SqliteSpatialSchema.createSchema(database);

    parcels = SqliteLandParcelRepository(database);
    spatial = SpatialPersistenceComposition(database);
    coordinator = LandParcelSpatialTransaction(database);
  });

  tearDown(() => database.close());

  test('failed spatial create rolls back its household number and row',
      () async {
    await SqliteParcelNumberSequence.createSchema(database);
    await database.execute('CREATE TABLE saved_households '
        '(code TEXT PRIMARY KEY)');
    final allocator = SqliteParcelNumberSequence();

    Future<void> prepare(Transaction tx, _) =>
        allocator.saveHousehold(tx: tx, farmId: 'farm-1',
          save: (code) async {
            await tx.insert('saved_households', {'code': code});
          });

    await expectLater(
      coordinator.run<void>((_, __, ___) async {
        throw StateError('spatial create failed');
      }, beforeCreate: prepare),
      throwsStateError,
    );
    expect(await database.query('saved_households'), isEmpty);
    expect(await database.query(SqliteParcelNumberSequence.table), isEmpty);

    await coordinator.run<void>((_, __, ___) async {},
        beforeCreate: prepare);
    expect((await database.query('saved_households')).single['code'], 'H00001');
  });

  test('commits LandParcel and SpatialFeature together', () async {
    final sourceParcel = parcel();
    final sourceFeature = feature(sourceParcel.id);

    await coordinator.run((scopedParcels, _, scopedSpatial) async {
      await scopedParcels.create(sourceParcel);
      await scopedSpatial.createFeature.execute(
        feature: sourceFeature,
        initialRevision: revision(sourceFeature.id),
      );
    });

    expect(
      await parcels.getById(farmId: sourceParcel.farmId, id: sourceParcel.id),
      isNotNull,
    );
    expect(
      await spatial.featureRepository.findById(sourceFeature.id),
      isNotNull,
    );
    expect(
      await spatial.revisionRepository.findByFeatureId(sourceFeature.id),
      hasLength(1),
    );
  });

  test('Spatial failure rolls back LandParcel and boundary history', () async {
    final sourceParcel = parcel();
    final sourceFeature = feature(sourceParcel.id);

    await expectLater(
      () => coordinator.run<void>((scopedParcels, _, scopedSpatial) async {
        await scopedParcels.create(sourceParcel);

        await scopedSpatial.createFeature.execute(
          feature: sourceFeature,
          initialRevision: revision(sourceFeature.id),
        );

        await scopedSpatial.createFeature.execute(
          feature: sourceFeature,
          initialRevision: revision(sourceFeature.id),
        );
      }),
      throwsA(anything),
    );

    expect(
      await parcels.getById(farmId: sourceParcel.farmId, id: sourceParcel.id),
      isNull,
    );
    expect(
      await database.query(SqliteLandParcelRepository.boundaryVersionTable),
      isEmpty,
    );
    expect(await spatial.featureRepository.findById(sourceFeature.id), isNull);
    expect(
      await spatial.revisionRepository.findByFeatureId(sourceFeature.id),
      isEmpty,
    );
  });

  test('LandParcel failure rolls back SpatialFeature and revision', () async {
    final existing = parcel(id: 'existing', code: 'P-001');
    await parcels.create(existing);

    final sourceParcel = parcel(id: 'parcel-2', code: 'P-001');
    final sourceFeature = feature(sourceParcel.id);

    await expectLater(
      () => coordinator.run<void>((scopedParcels, _, scopedSpatial) async {
        await scopedSpatial.createFeature.execute(
          feature: sourceFeature,
          initialRevision: revision(sourceFeature.id),
        );

        await scopedParcels.create(sourceParcel);
      }),
      throwsA(anything),
    );

    expect(await spatial.featureRepository.findById(sourceFeature.id), isNull);
    expect(
      await spatial.revisionRepository.findByFeatureId(sourceFeature.id),
      isEmpty,
    );
    expect(
      await parcels.getById(farmId: sourceParcel.farmId, id: sourceParcel.id),
      isNull,
    );

    final existingAfter = await parcels.getById(
      farmId: existing.farmId,
      id: existing.id,
    );
    expect(existingAfter, isNotNull);
  });
}
