import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;
  final occurredAt = DateTime.utc(2026, 9, 30, 8, 0, 0);

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

  LandParcel make({
    required String id,
    required String code,
    ParcelLayer kind = ParcelLayer.landBlock,
    String? parentBlockId,
    String? projectId,
    String farmId = 'farm-1',
  }) => LandParcel.create(
    id: id,
    farmId: farmId,
    parcelCode: code,
    name: 'Parcel $id',
    boundary: triangle(),
    boundarySource: BoundarySource.gps,
    verificationStatus: BoundaryVerificationStatus.measured,
    actorMembershipId: 'member-1',
    occurredAt: occurredAt,
    kind: kind,
    parentBlockId: parentBlockId,
    projectId: projectId,
  );

  Future<void> insert(LandParcel parcel) async {
    await SqliteLandParcelRepository(database).create(parcel);
  }

  group('kind trigger', () {
    test('rejects unknown kind via raw SQL insert', () async {
      await expectLater(
        () => database.rawInsert(
          'INSERT INTO land_parcels '
          '(id, farm_id, parcel_code, active, boundary_version, '
          'schema_version, payload_json, kind) '
          "VALUES ('x', 'farm-1', 'X', 1, 1, 3, '{}', 'nonsense')",
        ),
        throwsA(anything),
      );
    });
  });

  group('parent trigger', () {
    test('rejects landBlock with a parent via SQL', () async {
      await insert(make(id: 'block-1', code: 'B1'));
      await expectLater(
        () => database.rawInsert(
          'INSERT INTO land_parcels '
          '(id, farm_id, parcel_code, active, boundary_version, '
          'schema_version, payload_json, kind, parent_block_id) '
          "VALUES ('x', 'farm-1', 'X', 1, 1, 3, '{}', 'landBlock', 'block-1')",
        ),
        throwsA(anything),
      );
    });

    test('rejects parent that does not exist via SQL', () async {
      await expectLater(
        () => database.rawInsert(
          'INSERT INTO land_parcels '
          '(id, farm_id, parcel_code, active, boundary_version, '
          'schema_version, payload_json, kind, parent_block_id) '
          "VALUES ('plot-x', 'farm-1', 'TX', 1, 1, 3, '{}', 'fieldPlot', 'missing')",
        ),
        throwsA(anything),
      );
    });

    test('rejects parent that is not a land block', () async {
      await insert(
        make(id: 'plot-1', code: 'T1', kind: ParcelLayer.fieldPlot),
      );
      await expectLater(
        () => database.rawInsert(
          'INSERT INTO land_parcels '
          '(id, farm_id, parcel_code, active, boundary_version, '
          'schema_version, payload_json, kind, parent_block_id) '
          "VALUES ('plot-2', 'farm-1', 'T2', 1, 1, 3, '{}', 'fieldPlot', 'plot-1')",
        ),
        throwsA(anything),
      );
    });

    test('rejects parent from a different farm', () async {
      await insert(make(id: 'block-1', code: 'B1', farmId: 'farm-1'));
      await expectLater(
        () => database.rawInsert(
          'INSERT INTO land_parcels '
          '(id, farm_id, parcel_code, active, boundary_version, '
          'schema_version, payload_json, kind, parent_block_id) '
          "VALUES ('plot-x', 'farm-2', 'TX', 1, 1, 3, '{}', 'fieldPlot', 'block-1')",
        ),
        throwsA(anything),
      );
    });

    test('rejects parent with conflicting project_id', () async {
      await insert(
        make(id: 'block-1', code: 'B1', projectId: 'PROJ-A'),
      );
      await expectLater(
        () => database.rawInsert(
          'INSERT INTO land_parcels '
          '(id, farm_id, parcel_code, active, boundary_version, '
          'schema_version, payload_json, kind, parent_block_id, project_id) '
          "VALUES ('plot-x', 'farm-1', 'TX', 1, 1, 3, '{}', 'fieldPlot', 'block-1', 'PROJ-B')",
        ),
        throwsA(anything),
      );
    });

    test('allows project_id = NULL on either side', () async {
      await insert(make(id: 'block-1', code: 'B1', projectId: null));
      await expectLater(
        () => database.rawInsert(
          'INSERT INTO land_parcels '
          '(id, farm_id, parcel_code, active, boundary_version, '
          'schema_version, payload_json, kind, parent_block_id, project_id) '
          "VALUES ('plot-x', 'farm-1', 'TX', 1, 1, 3, '{}', 'fieldPlot', 'block-1', 'PROJ-A')",
        ),
        returnsNormally,
      );
    });

    test('rejects self-reference via SQL', () async {
      await expectLater(
        () => database.rawInsert(
          'INSERT INTO land_parcels '
          '(id, farm_id, parcel_code, active, boundary_version, '
          'schema_version, payload_json, kind, parent_block_id) '
          "VALUES ('plot-x', 'farm-1', 'TX', 1, 1, 3, '{}', 'fieldPlot', 'plot-x')",
        ),
        throwsA(anything),
      );
    });

    test('rejects deleting a block with linked plots', () async {
      await insert(make(id: 'block-1', code: 'B1'));
      await insert(
        make(
          id: 'plot-1',
          code: 'T1',
          kind: ParcelLayer.fieldPlot,
          parentBlockId: 'block-1',
        ),
      );
      await expectLater(
        () => database.delete(
          'land_parcels',
          where: 'id = ?',
          whereArgs: ['block-1'],
        ),
        throwsA(anything),
      );
    });

    test('rejects changing kind on a block with children', () async {
      await insert(make(id: 'block-1', code: 'B1'));
      await insert(
        make(
          id: 'plot-1',
          code: 'T1',
          kind: ParcelLayer.fieldPlot,
          parentBlockId: 'block-1',
        ),
      );
      await expectLater(
        () => database.update(
          'land_parcels',
          {'kind': 'fieldPlot'},
          where: 'id = ?',
          whereArgs: ['block-1'],
        ),
        throwsA(anything),
      );
    });

    test('rejects changing farm_id on a block with children', () async {
      await insert(make(id: 'block-1', code: 'B1'));
      await insert(
        make(
          id: 'plot-1',
          code: 'T1',
          kind: ParcelLayer.fieldPlot,
          parentBlockId: 'block-1',
        ),
      );
      await expectLater(
        () => database.update(
          'land_parcels',
          {'farm_id': 'other-farm'},
          where: 'id = ?',
          whereArgs: ['block-1'],
        ),
        throwsA(anything),
      );
    });

    test('rejects changing project_id on a block with children', () async {
      await insert(
        make(id: 'block-1', code: 'B1', projectId: 'PROJ-A'),
      );
      await insert(
        make(
          id: 'plot-1',
          code: 'T1',
          kind: ParcelLayer.fieldPlot,
          parentBlockId: 'block-1',
          projectId: 'PROJ-A',
        ),
      );
      await expectLater(
        () => database.update(
          'land_parcels',
          {'project_id': 'PROJ-B'},
          where: 'id = ?',
          whereArgs: ['block-1'],
        ),
        throwsA(anything),
      );
    });

    test('rejects changing id on a block with children', () async {
      await insert(make(id: 'block-1', code: 'B1'));
      await insert(
        make(
          id: 'plot-1',
          code: 'T1',
          kind: ParcelLayer.fieldPlot,
          parentBlockId: 'block-1',
        ),
      );
      await expectLater(
        () => database.update(
          'land_parcels',
          {'id': 'block-renamed'},
          where: 'id = ?',
          whereArgs: ['block-1'],
        ),
        throwsA(anything),
      );
    });

    test('allows NULL -> X on a block with NULL children', () async {
      await insert(make(id: 'block-1', code: 'B1', projectId: null));
      await insert(
        make(
          id: 'plot-1',
          code: 'T1',
          kind: ParcelLayer.fieldPlot,
          parentBlockId: 'block-1',
          projectId: null,
        ),
      );
      await expectLater(
        () => database.update(
          'land_parcels',
          {'project_id': 'PROJ-A'},
          where: 'id = ?',
          whereArgs: ['block-1'],
        ),
        returnsNormally,
      );
      final block = await database.query(
        'land_parcels',
        where: 'id = ?',
        whereArgs: ['block-1'],
      );
      expect(block.single['project_id'], 'PROJ-A');
    });

    test('allows NULL -> X when children already carry X', () async {
      await insert(make(id: 'block-1', code: 'B1', projectId: null));
      await insert(
        make(
          id: 'plot-1',
          code: 'T1',
          kind: ParcelLayer.fieldPlot,
          parentBlockId: 'block-1',
          projectId: 'PROJ-A',
        ),
      );
      await expectLater(
        () => database.update(
          'land_parcels',
          {'project_id': 'PROJ-A'},
          where: 'id = ?',
          whereArgs: ['block-1'],
        ),
        returnsNormally,
      );
    });

    test('rejects X -> NULL when children carry X', () async {
      await insert(make(id: 'block-1', code: 'B1', projectId: 'PROJ-A'));
      await insert(
        make(
          id: 'plot-1',
          code: 'T1',
          kind: ParcelLayer.fieldPlot,
          parentBlockId: 'block-1',
          projectId: 'PROJ-A',
        ),
      );
      await expectLater(
        () => database.update(
          'land_parcels',
          {'project_id': null},
          where: 'id = ?',
          whereArgs: ['block-1'],
        ),
        throwsA(anything),
      );
    });
  });
}