import 'dart:convert';

import 'package:agrico_deepseek/core/project/agrico_project.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;
  final occurredAt = DateTime.utc(2026, 10, 1, 8);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteLandParcelRepository.createSchema(database);
  });

  tearDown(() => database.close());

  Wgs84Polygon triangle() => Wgs84Polygon.fromVertices(const [
    Wgs84Vertex(latitude: 16.5, longitude: 104.7),
    Wgs84Vertex(latitude: 16.5, longitude: 104.701),
    Wgs84Vertex(latitude: 16.501, longitude: 104.7),
  ]);

  LandParcel block({
    String id = 'block-1',
    String? projectId,
    String farmId = 'farm-1',
  }) => LandParcel.create(
    id: id,
    farmId: farmId,
    parcelCode: 'AGR-NONG-L001',
    name: 'Lô',
    boundary: triangle(),
    boundarySource: BoundarySource.gps,
    verificationStatus: BoundaryVerificationStatus.measured,
    actorMembershipId: 'member-1',
    occurredAt: occurredAt,
    projectId: projectId,
    kind: ParcelLayer.landBlock,
  );

  test('AgricoProject keeps id and code distinct', () {
    expect(AgricoProject.defaultProject.id, isNot(AgricoProject.defaultProject.code));
    expect(AgricoProject.defaultProject.code, 'AGR-NONG');
    expect(AgricoProject.defaultProject.id, isNotEmpty);
  });

  test('project id round-trips through SQLite', () async {
    final repo = SqliteLandParcelRepository(database);
    await repo.create(block(projectId: AgricoProject.defaultProject.id));
    final restored = await repo.getById(farmId: 'farm-1', id: 'block-1');
    expect(restored?.projectId, AgricoProject.defaultProject.id);
  });

  test('project NULL round-trips through SQLite', () async {
    final repo = SqliteLandParcelRepository(database);
    await repo.create(block(projectId: null));
    final restored = await repo.getById(farmId: 'farm-1', id: 'block-1');
    expect(restored?.projectId, isNull);
  });

  test('typed column wins over stale projectId in payload', () async {
    final repo = SqliteLandParcelRepository(database);
    await repo.create(block(projectId: 'PROJ-A'));
    // Tamper with the payload to claim a different project id.
    final rows = await database.query('land_parcels');
    final payload = jsonDecode(rows.single['payload_json'] as String) as Map;
    payload['projectId'] = 'PROJ-X';
    await database.update(
      'land_parcels',
      {'payload_json': jsonEncode(payload)},
      where: 'id = ?',
      whereArgs: ['block-1'],
    );
    final restored = await repo.getById(farmId: 'farm-1', id: 'block-1');
    expect(restored?.projectId, 'PROJ-A');
  });
}