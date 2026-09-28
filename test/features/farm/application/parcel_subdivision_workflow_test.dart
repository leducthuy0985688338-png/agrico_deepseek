import 'package:agrico_deepseek/core/geography/data/sqlite_administrative_catalog.dart';
import 'package:agrico_deepseek/core/identity/data/sqlite_parcel_number_sequence.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_spatial_sync_workflow.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_subdivision_service.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/default_land_parcel_spatial_projection.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/land_parcel_spatial_transaction.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_spatial_link_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_survey_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_parcel_land_history_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/spatial/support/sequential_spatial_identity_generator.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteLandParcelRepository parcels;
  late SqliteParcelLandHistoryRepository history;
  late ParcelSubdivisionService service;
  const subject = AuthorizationSubject(
    userId: 'user', membershipId: 'member', farmId: 'farm',
    permissionCodes: {PermissionCodes.fieldView,
      PermissionCodes.fieldEdit, PermissionCodes.fieldCreate},
    dataScopes: {DataScope.allFarm},
  );
  const cutA = Wgs84Vertex(latitude: 16, longitude: 106.001);
  const cutB = Wgs84Vertex(latitude: 16.001, longitude: 106.001);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteLandParcelRepository.createSchema(db);
    await SqliteLandSurveyRepository.createSchema(db);
    await SqliteSpatialSchema.createSchema(db);
    await SqliteLandParcelSpatialLinkRepository.createSchema(db);
    await SqliteParcelNumberSequence.createSchema(db);
    await SqliteParcelLandHistoryRepository.createSchema(db);
    await SqliteAdministrativeCatalog.createSchema(db);
    await SqliteAdministrativeCatalog(db).seedInitialLocation();
    parcels = SqliteLandParcelRepository(db);
    history = SqliteParcelLandHistoryRepository(db);
    final workflow = LandParcelSpatialSyncWorkflow(
      transaction: LandParcelSpatialTransaction(db),
      projection: const DefaultLandParcelSpatialProjection(),
      identityGenerator: SequentialSpatialIdentityGenerator(),
    );
    service = ParcelSubdivisionService(parcels: parcels, workflow: workflow);
    await workflow.create(
      parcel: LandParcel.create(
        id: 'source', farmId: 'farm', parcelCode: 'SOURCE', name: 'Nguồn',
        boundary: Wgs84Polygon.fromVertices(const [
          Wgs84Vertex(latitude: 16, longitude: 106),
          Wgs84Vertex(latitude: 16, longitude: 106.002),
          Wgs84Vertex(latitude: 16.001, longitude: 106.002),
          Wgs84Vertex(latitude: 16.001, longitude: 106),
        ]), boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member', occurredAt: DateTime.utc(2026, 9, 28),
        countryCode: 'LA', provinceCode: 'SVK', districtCode: 'NONG',
        villageCode: 'TAKO',
      ), temporalState: SpatialTemporalState.baseline,
    );
  });

  tearDown(() => db.close());

  Future<List<LandParcel>> save() => service.save(
    subject: subject, sourceParcelId: 'source',
    villageId: 'agrico-la-svk-nong-tako', expectedBoundaryVersion: 1,
    cutStart: cutA, cutEnd: cutB,
    firstName: 'Lô trái', secondName: 'Lô phải',
  );

  test('creates both spatially linked children and retains source', () async {
    final source = (await parcels.getById(farmId: 'farm', id: 'source'))!;
    final preview = await service.preview(subject: subject,
      sourceParcelId: source.id, cutStart: cutA, cutEnd: cutB);
    expect(preview.areasM2[0] + preview.areasM2[1],
        closeTo(source.areaM2, 0.01));
    final children = await save();
    expect(children.map((p) => p.parcelCode), [
      'LA-SVK-NONG-TAKO-L00001', 'LA-SVK-NONG-TAKO-L00002']);
    expect(children.every((p) => p.spatialFeatureId != null), isTrue);
    expect((await history.derivations('farm', 'source')), hasLength(2));
    final retained = (await parcels.getById(farmId: 'farm', id: 'source'))!;
    expect(retained.spatialFeatureId, source.spatialFeatureId);
    expect(retained.boundaryVersion, source.boundaryVersion);
    expect(retained.boundary, source.boundary);
    expect(retained.active, isFalse);
    expect(await parcels.listByFarm('farm'), hasLength(2));
    await expectLater(save(), throwsStateError);
    expect(await history.derivations('farm', 'source'), hasLength(2));
  });

  test('failed second lineage rolls back both children and both numbers', () async {
    await db.execute('''CREATE TRIGGER reject_second_split
      BEFORE INSERT ON parcel_derivations
      WHEN (SELECT COUNT(*) FROM parcel_derivations) = 1
      BEGIN SELECT RAISE(ABORT, 'second lineage rejected'); END''');
    await expectLater(save(), throwsA(isA<Exception>()));
    expect(await parcels.listByFarm('farm'), hasLength(1));
    expect(await history.derivations('farm', 'source'), isEmpty);
    expect(await db.query(SqliteParcelNumberSequence.locationTable), isEmpty);
    expect((await parcels.getById(farmId: 'farm', id: 'source'))!.boundaryVersion, 1);
  });

  test('stale source revision prevents both children', () async {
    await expectLater(service.save(subject: subject,
      sourceParcelId: 'source', villageId: 'agrico-la-svk-nong-tako',
      expectedBoundaryVersion: 2, cutStart: cutA, cutEnd: cutB,
      firstName: 'A', secondName: 'B'), throwsStateError);
    expect(await parcels.listByFarm('farm'), hasLength(1));
  });
}
