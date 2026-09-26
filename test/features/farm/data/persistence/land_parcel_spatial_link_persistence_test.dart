import 'package:agrico_deepseek/core/spatial/domain/repositories/spatial_feature_repository.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_feature_repository.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_spatial_link_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel_spatial_link.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  final occurredAt = DateTime.utc(2026, 9, 11, 8);

  late Database database;
  late SqliteLandParcelRepository parcels;
  late SpatialFeatureRepository features;
  late SqliteLandParcelSpatialLinkRepository links;

  LandParcel parcel({String id = 'parcel-1', String code = 'P-001'}) {
    return LandParcel.create(
      id: id,
      farmId: 'farm-1',
      parcelCode: code,
      name: 'Parcel $id',
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.5000, longitude: 104.7000),
        Wgs84Vertex(latitude: 16.5000, longitude: 104.7010),
        Wgs84Vertex(latitude: 16.5010, longitude: 104.7010),
        Wgs84Vertex(latitude: 16.5010, longitude: 104.7000),
      ]),
      boundarySource: BoundarySource.gps,
      verificationStatus: BoundaryVerificationStatus.measured,
      actorMembershipId: 'member-1',
      occurredAt: occurredAt,
    );
  }

  SpatialFeature feature(String id) {
    return SpatialFeature(
      id: id,
      featureType: SpatialFeatureTypes.landParcel,
      geometryType: SpatialGeometryType.polygon,
      lifecycleStatus: SpatialFeatureLifecycleStatus.active,
      createdAt: occurredAt,
      createdBy: 'member-1',
      updatedAt: occurredAt,
      updatedBy: 'member-1',
    );
  }

  LandParcelSpatialLink link({
    String id = 'link-1',
    String landParcelId = 'parcel-1',
    String spatialFeatureId = 'spatial-1',
  }) {
    return LandParcelSpatialLink(
      id: id,
      landParcelId: landParcelId,
      spatialFeatureId: spatialFeatureId,
      createdAt: occurredAt,
      createdBy: 'member-1',
    );
  }

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');

    await SqliteLandParcelRepository.createSchema(database);
    await SqliteSpatialSchema.createSchema(database);
    await SqliteLandParcelSpatialLinkRepository.createSchema(database);

    parcels = SqliteLandParcelRepository(database);
    features = SqliteSpatialFeatureRepository(database);
    links = SqliteLandParcelSpatialLinkRepository(database);
  });

  tearDown(() => database.close());

  Future<void> createParents({
    String parcelId = 'parcel-1',
    String parcelCode = 'P-001',
    String featureId = 'spatial-1',
  }) async {
    await parcels.create(parcel(id: parcelId, code: parcelCode));
    await features.create(feature(featureId));
  }

  test('round-trips a stable LandParcel SpatialFeature link', () async {
    await createParents();

    final value = link();
    await links.create(value);

    final byId = await links.findById(value.id);
    final byParcel = await links.findByLandParcelId(value.landParcelId);
    final byFeature = await links.findBySpatialFeatureId(
      value.spatialFeatureId,
    );

    expect(byId!.id, value.id);
    expect(byParcel!.spatialFeatureId, value.spatialFeatureId);
    expect(byFeature!.landParcelId, value.landParcelId);
    expect(byId.createdAt, value.createdAt);
    expect(byId.createdBy, value.createdBy);
    expect(byId.schemaVersion, value.schemaVersion);
  });

  test('rejects a second link for the same LandParcel', () async {
    await createParents();
    await features.create(feature('spatial-2'));

    await links.create(link());

    await expectLater(
      () => links.create(link(id: 'link-2', spatialFeatureId: 'spatial-2')),
      throwsA(anything),
    );
  });

  test('rejects a second LandParcel for the same SpatialFeature', () async {
    await createParents();
    await parcels.create(parcel(id: 'parcel-2', code: 'P-002'));

    await links.create(link());

    await expectLater(
      () => links.create(link(id: 'link-2', landParcelId: 'parcel-2')),
      throwsA(anything),
    );
  });

  test('rejects a link whose LandParcel does not exist', () async {
    await features.create(feature('spatial-1'));

    await expectLater(() => links.create(link()), throwsA(anything));
  });

  test('rejects a link whose SpatialFeature does not exist', () async {
    await parcels.create(parcel());

    await expectLater(() => links.create(link()), throwsA(anything));
  });

  test('foreign keys restrict deleting linked LandParcel', () async {
    await createParents();
    await links.create(link());

    await expectLater(
      () => database.delete(
        SqliteLandParcelRepository.parcelTable,
        where: 'id = ?',
        whereArgs: ['parcel-1'],
      ),
      throwsA(anything),
    );
  });

  test('foreign keys restrict deleting linked SpatialFeature', () async {
    await createParents();
    await links.create(link());

    await expectLater(
      () => features.deleteById('spatial-1'),
      throwsA(anything),
    );
  });

  test('caller-owned transaction rolls back link creation', () async {
    await createParents();

    await expectLater(
      () => database.transaction((transaction) async {
        final transactionalLinks = SqliteLandParcelSpatialLinkRepository(
          transaction,
        );

        await transactionalLinks.create(link());

        throw StateError('force rollback');
      }),
      throwsA(isA<StateError>()),
    );

    expect(await links.findById('link-1'), isNull);
  });
}
