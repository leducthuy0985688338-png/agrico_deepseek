import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_parcel_land_history_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_land_history.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteParcelLandHistoryRepository history;
  final date = DateTime.utc(2026, 9, 28);

  LandParcel parcel(String id, String farm, String code) => LandParcel.create(
    id: id, farmId: farm, parcelCode: code, name: id,
    boundary: Wgs84Polygon.fromVertices(const [
      Wgs84Vertex(latitude: 16.5, longitude: 104.7),
      Wgs84Vertex(latitude: 16.5, longitude: 104.701),
      Wgs84Vertex(latitude: 16.501, longitude: 104.7),
    ]),
    boundarySource: BoundarySource.gps,
    verificationStatus: BoundaryVerificationStatus.measured,
    actorMembershipId: 'actor', occurredAt: date,
  );

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteParcelLandHistoryRepository.createSchema(db);
    history = SqliteParcelLandHistoryRepository(db);
    final parcels = SqliteLandParcelRepository(db);
    await parcels.create(parcel('before', 'farm-1', 'OLD'));
    await parcels.create(parcel('after', 'farm-1', 'NEW'));
    await parcels.create(parcel('foreign', 'other-farm', 'OTHER'));
  });
  tearDown(() => db.close());

  test('stage refers to retained boundary revision and keeps old parcel', () async {
    final old = (await SqliteLandParcelRepository(db)
        .getById(farmId: 'farm-1', id: 'before'))!;
    final stage = ParcelStageSnapshot(
      id: 'stage-1', farmId: 'farm-1', parcelId: 'before',
      stage: ParcelLandStage.beforeClearing, boundaryVersion: 1,
      areaM2: old.areaM2, recordedAt: date, actorMembershipId: 'actor',
    );
    await history.capture(stage);
    expect((await history.snapshots('farm-1', 'before')).single.areaM2,
        old.areaM2);
    await expectLater(history.capture(ParcelStageSnapshot(
      id: 'stage-invalid', farmId: 'farm-1', parcelId: 'before',
      stage: ParcelLandStage.afterClearing, boundaryVersion: 2,
      areaM2: old.areaM2, recordedAt: date, actorMembershipId: 'actor',
    )), throwsStateError);
    expect((await SqliteLandParcelRepository(db)
        .getById(farmId: 'farm-1', id: 'before'))!.parcelCode, 'OLD');
  });

  test('subdivision links two parcel IDs and rejects cross-farm', () async {
    final area = (await SqliteLandParcelRepository(db)
        .getById(farmId: 'farm-1', id: 'after'))!.areaM2;
    await history.link(ParcelDerivation(
      id: 'link-1', farmId: 'farm-1',
      sourceParcelId: 'before', targetParcelId: 'after',
      kind: ParcelDerivationKind.subdivision,
      derivedAreaM2: area, occurredAt: date, actorMembershipId: 'actor',
    ));
    expect((await history.derivations('farm-1', 'before')).single.targetParcelId,
        'after');
    await expectLater(history.link(ParcelDerivation(
      id: 'link-2', farmId: 'farm-1',
      sourceParcelId: 'foreign', targetParcelId: 'after',
      kind: ParcelDerivationKind.merge,
      derivedAreaM2: area, occurredAt: date, actorMembershipId: 'actor',
    )), throwsStateError);
    expect(await history.derivations('other-farm', 'before'), isEmpty);
  });
}
