import 'package:agrico_deepseek/features/farm/application/parcel_work_time_productivity.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_parcel_work_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_parcel_work_time_evidence_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteParcelWorkRepository work;
  late SqliteParcelWorkTimeEvidenceRepository store;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteParcelWorkTimeEvidenceRepository.createSchema(db);
    work = SqliteParcelWorkRepository(db);
    store = SqliteParcelWorkTimeEvidenceRepository(db);
    await SqliteLandParcelRepository(db).create(
      LandParcel.create(
        id: 'p1',
        farmId: 'f1',
        parcelCode: 'LA-SVK-NONG-TAKO-L00001',
        name: 'Plot',
        boundary: Wgs84Polygon.fromVertices(const [
          Wgs84Vertex(latitude: 16.5, longitude: 104.7),
          Wgs84Vertex(latitude: 16.5, longitude: 104.701),
          Wgs84Vertex(latitude: 16.501, longitude: 104.7),
        ]),
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'actor',
        occurredAt: DateTime.utc(2026, 11, 20),
      ),
    );
    await work.register(
      const WorkResource(
        id: 'w1',
        farmId: 'f1',
        kind: WorkResourceKind.worker,
        code: 'W1',
        name: 'Worker',
      ),
    );
    await work.record(
      ParcelWorkEvent(
        id: 'e1',
        farmId: 'f1',
        parcelId: 'p1',
        phase: ParcelWorkPhase.clearing,
        description: 'Clearing',
        occurredAt: DateTime.utc(2026, 11, 20),
        actorMembershipId: 'actor',
        machineIds: const [],
        workerIds: const ['w1'],
        areaM2: 500,
      ),
    );
  });
  tearDown(() => db.close());

  const entry = WorkTimeEvidence(
    eventId: 'e1',
    resourceId: 'w1',
    kind: WorkTimeResourceKind.worker,
    minutes: 90,
    evidenceReference: 'timesheet-001',
  );
  Future<void> save(
    WorkTimeEvidence e, {
    String farm = 'f1',
    String parcel = 'p1',
  }) => store.record(
    farmId: farm,
    parcelId: parcel,
    actorMembershipId: 'actor',
    evidence: e,
  );

  test('SQLite roundtrip, farm isolation and duplicate rejection', () async {
    await save(entry);
    final reopened = SqliteParcelWorkTimeEvidenceRepository(db);
    final result = await reopened.read(farmId: 'f1', parcelId: 'p1');
    expect(result.single.minutes, 90);
    expect(result.single.evidenceReference, 'timesheet-001');
    expect(await reopened.read(farmId: 'other', parcelId: 'p1'), isEmpty);
    await expectLater(save(entry), throwsA(isA<Exception>()));
    expect(
      await db.query(SqliteParcelWorkTimeEvidenceRepository.table),
      hasLength(1),
    );
  });

  test('cross-farm, wrong parcel and unassigned resource rejected', () async {
    await expectLater(save(entry, farm: 'other'), throwsStateError);
    await expectLater(save(entry, parcel: 'other'), throwsStateError);
    await expectLater(
      save(
        const WorkTimeEvidence(
          eventId: 'e1',
          resourceId: 'missing',
          kind: WorkTimeResourceKind.worker,
          minutes: 60,
          evidenceReference: 'ref',
        ),
      ),
      throwsStateError,
    );
    expect(
      await db.query(SqliteParcelWorkTimeEvidenceRepository.table),
      isEmpty,
    );
  });

  test('invalid duration and blank reference rejected', () async {
    await expectLater(
      save(
        const WorkTimeEvidence(
          eventId: 'e1',
          resourceId: 'w1',
          kind: WorkTimeResourceKind.worker,
          minutes: 0,
          evidenceReference: 'ref',
        ),
      ),
      throwsFormatException,
    );
    await expectLater(
      save(
        const WorkTimeEvidence(
          eventId: 'e1',
          resourceId: 'w1',
          kind: WorkTimeResourceKind.worker,
          minutes: 60,
          evidenceReference: '  ',
        ),
      ),
      throwsFormatException,
    );
  });
}
