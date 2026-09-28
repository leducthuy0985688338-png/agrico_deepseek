import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_parcel_work_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteParcelWorkRepository work;
  final now = DateTime.utc(2026, 9, 28);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteParcelWorkRepository.createSchema(db);
    work = SqliteParcelWorkRepository(db);
    await SqliteLandParcelRepository(db).create(LandParcel.create(
      id: 'parcel-1', farmId: 'farm-1', parcelCode: 'LA-SVK-NONG-TAKO-L00001',
      name: 'Lô đất',
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.5, longitude: 104.7),
        Wgs84Vertex(latitude: 16.5, longitude: 104.701),
        Wgs84Vertex(latitude: 16.501, longitude: 104.7),
      ]),
      boundarySource: BoundarySource.gps,
      verificationStatus: BoundaryVerificationStatus.measured,
      actorMembershipId: 'actor', occurredAt: now,
    ));
    await work.register(const WorkResource(
      id: 'machine-1', farmId: 'farm-1', kind: WorkResourceKind.machine,
      code: 'M001', name: 'Máy khai hoang',
    ));
    await work.register(const WorkResource(
      id: 'worker-1', farmId: 'farm-1', kind: WorkResourceKind.worker,
      code: 'NV001', name: 'Đội khai hoang',
    ));
  });
  tearDown(() => db.close());

  ParcelWorkEvent event({List<String> machines = const ['machine-1'],
      List<String> workers = const ['worker-1']}) => ParcelWorkEvent(
    id: 'work-1', farmId: 'farm-1', parcelId: 'parcel-1',
    phase: ParcelWorkPhase.clearing, description: 'Dọn thực bì',
    occurredAt: now, actorMembershipId: 'actor',
    machineIds: machines, workerIds: workers, areaM2: 500,
  );

  test('reopens phase-specific machine and worker assignments', () async {
    await work.record(event());
    final reopened = SqliteParcelWorkRepository(db);
    final result = (await reopened.events('farm-1', 'parcel-1')).single;
    expect(result.phase, ParcelWorkPhase.clearing);
    expect(result.machineIds, ['machine-1']);
    expect(result.workerIds, ['worker-1']);
    expect(result.areaM2, 500);
    expect(await reopened.events('other-farm', 'parcel-1'), isEmpty);
  });

  test('wrong resource kind or farm rolls back work and assignments', () async {
    await expectLater(work.record(event(machines: ['worker-1'])),
        throwsStateError);
    expect(await work.events('farm-1', 'parcel-1'), isEmpty);
    expect(await db.query(SqliteParcelWorkRepository.assignmentsTable), isEmpty);
    await work.register(const WorkResource(
      id: 'foreign-machine', farmId: 'other-farm',
      kind: WorkResourceKind.machine, code: 'M001', name: 'Máy khác',
    ));
    await expectLater(work.record(event(machines: ['foreign-machine'])),
        throwsStateError);
    expect(await work.events('farm-1', 'parcel-1'), isEmpty);
  });
}
