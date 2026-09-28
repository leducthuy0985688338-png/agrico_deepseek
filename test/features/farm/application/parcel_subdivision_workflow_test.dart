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
import 'package:agrico_deepseek/features/farm/data/interchange/kml_interchange.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/parcel_subdivision_plan.dart';
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

  final threeCuts = [
    const ParcelSubdivisionCut(fragmentIndex: 0, path: [cutA, cutB]),
    const ParcelSubdivisionCut(fragmentIndex: 0, path: [
      Wgs84Vertex(latitude: 16.0005, longitude: 106.001),
      Wgs84Vertex(latitude: 16.0005, longitude: 106.002),
    ]),
  ];

  Future<List<LandParcel>> saveThree() => service.savePlan(
    subject: subject, sourceParcelId: 'source',
    villageId: 'agrico-la-svk-nong-tako', expectedBoundaryVersion: 1,
    cuts: threeCuts, names: ['A', 'B', 'C']);

  test('two cuts save three direct children in one operation', () async {
    final preview = await service.previewPlan(
      subject: subject, sourceParcelId: 'source', cuts: threeCuts);
    expect(preview.boundaries, hasLength(3));
    final children = await saveThree();
    expect(children.map((p) => p.name), ['A', 'B', 'C']);
    expect(children.map((p) => p.parcelCode), [
      'LA-SVK-NONG-TAKO-L00001', 'LA-SVK-NONG-TAKO-L00002',
      'LA-SVK-NONG-TAKO-L00003']);
    expect(children.every((p) => p.spatialFeatureId != null), isTrue);
    final derivations = await history.derivations('farm', 'source');
    expect(derivations.where((d) => d.sourceParcelId == 'source'), hasLength(3));
    expect(await parcels.listByFarm('farm'), hasLength(3));
  });

  test('enclosed polygon saves a child and a remainder with a persisted hole', () async {
    final interior = Wgs84Polygon.fromVertices(const [
      Wgs84Vertex(latitude: 16.0002, longitude: 106.0004),
      Wgs84Vertex(latitude: 16.0002, longitude: 106.0008),
      Wgs84Vertex(latitude: 16.0006, longitude: 106.0008),
      Wgs84Vertex(latitude: 16.0006, longitude: 106.0004),
    ]);
    final operations = [ParcelSubdivisionCut.enclosed(
      fragmentIndex: 0, polygon: interior)];
    final source = (await parcels.getById(farmId: 'farm', id: 'source'))!;
    final preview = await service.previewPlan(subject: subject,
      sourceParcelId: source.id, cuts: operations);
    expect(preview.boundaries.first.holes, hasLength(1));
    expect(preview.areasM2.reduce((a, b) => a + b),
      closeTo(source.areaM2, 0.01));
    final created = await service.savePlan(subject: subject,
      sourceParcelId: source.id, villageId: 'agrico-la-svk-nong-tako',
      expectedBoundaryVersion: source.boundaryVersion,
      cuts: operations, names: ['Còn lại', 'Lô giữa']);
    final remainder = (await parcels.getById(
      farmId: 'farm', id: created.first.id))!;
    expect(remainder.boundary.holes.single, interior.vertices);
    expect(remainder.areaM2 + created.last.areaM2,
      closeTo(source.areaM2, 0.01));
    expect((await history.derivations('farm', 'source')), hasLength(2));
  });

  test('adjacent enclosed parcels retain their shared edge and three identities', () async {
    Wgs84Polygon box(double west, double east) => Wgs84Polygon.fromVertices([
      Wgs84Vertex(latitude: 16.0002, longitude: west),
      Wgs84Vertex(latitude: 16.0002, longitude: east),
      Wgs84Vertex(latitude: 16.0006, longitude: east),
      Wgs84Vertex(latitude: 16.0006, longitude: west),
    ]);
    final first = box(106.0004, 106.0008);
    final second = box(106.0008, 106.0012);
    final operations = [
      ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: first),
      ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: second),
    ];
    final source = (await parcels.getById(farmId: 'farm', id: 'source'))!;
    final preview = await service.previewPlan(subject: subject,
      sourceParcelId: source.id, cuts: operations);
    expect(preview.boundaries, hasLength(3));
    expect(preview.boundaries.first.holes, hasLength(1));
    final children = await service.savePlan(subject: subject,
      sourceParcelId: source.id, villageId: 'agrico-la-svk-nong-tako',
      expectedBoundaryVersion: source.boundaryVersion,
      cuts: operations, names: ['Còn lại', 'A', 'B']);
    expect(children, hasLength(3));
    expect((await parcels.getById(farmId: 'farm', id: children.first.id))!
      .boundary.holes, hasLength(1));
    final remainder = (await parcels.getById(
      farmId: 'farm', id: children.first.id))!;
    const codec = KmlInterchangeCodec();
    expect(codec.importKml(codec.exportKml(remainder)).previews.single.boundary,
      remainder.boundary);
    expect(children.map((child) => child.areaM2).reduce((a, b) => a + b),
      closeTo(source.areaM2, 0.01));
    expect((await history.derivations('farm', 'source')), hasLength(3));
  });

  test('all split parcels round trip through Google Earth KML and KMZ', () async {
    final source = (await parcels.getById(farmId: 'farm', id: 'source'))!;
    final children = await saveThree();
    const codec = KmlInterchangeCodec();
    for (final child in children) {
      expect(child.boundary.crs, Wgs84Polygon.crsCode);
      expect(child.boundary.isClosed, isTrue);
      expect(child.boundarySource, BoundarySource.manual);
      final kml = codec.exportKml(child);
      expect(kml, contains('http://www.opengis.net/kml/2.2'));
      final fromKml = codec.importKml(kml).previews.single;
      expect(fromKml.boundary, child.boundary);
      expect(fromKml.metadata.parcelCode, child.parcelCode);
      expect(fromKml.metadata.parcelName, child.name);
      final fromKmz = codec.importKmz(codec.exportKmz(child)).previews.single;
      expect(fromKmz.boundary, child.boundary);
      expect(fromKmz.metadata.parcelCode, child.parcelCode);
    }
    final original = (await parcels.getById(farmId: 'farm', id: 'source'))!;
    expect(original.boundary, source.boundary);
    expect(original.boundarySource, source.boundarySource);
    expect(original.boundaryVersion, source.boundaryVersion);
  });

  test('third lineage failure rolls back all three children and numbers', () async {
    await db.execute('''CREATE TRIGGER reject_third_split
      BEFORE INSERT ON parcel_derivations
      WHEN (SELECT COUNT(*) FROM parcel_derivations) = 2
      BEGIN SELECT RAISE(ABORT, 'third lineage rejected'); END''');
    await expectLater(saveThree(), throwsA(isA<Exception>()));
    expect(await parcels.listByFarm('farm'), hasLength(1));
    expect(await history.derivations('farm', 'source'), isEmpty);
    expect(await db.query(SqliteParcelNumberSequence.locationTable), isEmpty);
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

  test('repeatedly splits a child into three active fragments', () async {
    final children = await save();
    final grandchildren = await service.save(
      subject: subject, sourceParcelId: children.first.id,
      villageId: 'agrico-la-svk-nong-tako', expectedBoundaryVersion: 1,
      cutStart: const Wgs84Vertex(latitude: 16.0005, longitude: 106.001),
      cutEnd: const Wgs84Vertex(latitude: 16.0005, longitude: 106.002),
      firstName: 'Mảnh thứ ba', secondName: 'Mảnh thứ tư',
    );
    expect(grandchildren, hasLength(2));
    expect(await parcels.listByFarm('farm'), hasLength(3));
    expect((await history.derivations('farm', children.first.id)), hasLength(3));
  });

  test('stale source revision prevents both children', () async {
    await expectLater(service.save(subject: subject,
      sourceParcelId: 'source', villageId: 'agrico-la-svk-nong-tako',
      expectedBoundaryVersion: 2, cutStart: cutA, cutEnd: cutB,
      firstName: 'A', secondName: 'B'), throwsStateError);
    expect(await parcels.listByFarm('farm'), hasLength(1));
  });
}
