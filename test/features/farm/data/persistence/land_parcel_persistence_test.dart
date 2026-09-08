import 'package:agrico_deepseek/features/farm/data/legacy/land_parcel_legacy_migration.dart';
import 'package:agrico_deepseek/features/farm/data/legacy/legacy_field_adapter.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/models/land_parcel_mapper.dart';
import 'package:agrico_deepseek/features/farm/data/remote/land_parcel_firestore_mapper.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_parcel_repository.dart';
import 'package:agrico_deepseek/models/field_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;
  late LandParcelRepository repository;
  final occurredAt = DateTime.utc(2026, 9, 8, 4, 5, 6, 789);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteLandParcelRepository.createSchema(database);
    await SqliteLandParcelRepository.createSchema(database);
    repository = SqliteLandParcelRepository(database);
  });

  tearDown(() => database.close());

  LandParcel parcel({
    String id = 'parcel-1',
    String code = 'P-001',
    BoundaryVerificationStatus verification =
        BoundaryVerificationStatus.measured,
  }) => LandParcel.create(
    id: id,
    farmId: 'farm-1',
    parcelCode: code,
    name: 'Lô ກະສິກຳ',
    boundary: Wgs84Polygon.fromVertices(const [
      Wgs84Vertex(latitude: 16.5, longitude: 104.7, altitudeM: 120),
      Wgs84Vertex(latitude: 16.5, longitude: 104.701, altitudeM: 121),
      Wgs84Vertex(latitude: 16.501, longitude: 104.7, altitudeM: 122),
    ]),
    boundarySource: BoundarySource.gps,
    verificationStatus: verification,
    actorMembershipId: 'member-1',
    occurredAt: occurredAt,
    horizontalAccuracyM: 1.25,
    boundaryConfidence: 0.98,
    legacyMetadata: const {
      'crop': 'Lúa',
      'photoPaths': ['a.jpg'],
    },
  );

  test('repository CRUD and farm queries preserve canonical data', () async {
    final source = parcel();
    await repository.create(source);

    final byId = await repository.getById(farmId: 'farm-1', id: source.id);
    final byCode = await repository.getByParcelCode(
      farmId: 'farm-1',
      parcelCode: source.parcelCode,
    );
    final list = await repository.listByFarm('farm-1');

    expect(byId?.boundary, source.boundary);
    expect(byCode?.id, source.id);
    expect(list.map((item) => item.id), [source.id]);
    expect(byId?.horizontalAccuracyM, 1.25);
    expect(byId?.boundaryConfidence, 0.98);
    expect(byId?.createdAt, occurredAt);
    expect(byId?.verificationStatus, BoundaryVerificationStatus.measured);
  });

  test(
    'v2 schema is additive and leaves legacy field data untouched',
    () async {
      await database.execute('''
      CREATE TABLE fields (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        polygon TEXT NOT NULL
      )
    ''');
      await database.insert('fields', {
        'id': 'legacy-raw-1',
        'name': 'Original legacy value',
        'polygon': '[{"lat":16.5,"lng":104.7}]',
      });

      await SqliteLandParcelRepository.createSchema(database);

      expect(await database.query('fields'), [
        {
          'id': 'legacy-raw-1',
          'name': 'Original legacy value',
          'polygon': '[{"lat":16.5,"lng":104.7}]',
        },
      ]);
      final indexes = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );
      expect(
        indexes.map((row) => row['name']),
        containsAll([
          'idx_land_parcels_farm',
          'idx_land_parcels_farm_code',
          'idx_boundary_parcel_version',
        ]),
      );
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test('JSON round trip is lossless for parcel and immutable history', () {
    final source = parcel().replaceBoundary(
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.5, longitude: 104.7, altitudeM: 130),
        Wgs84Vertex(latitude: 16.5, longitude: 104.702, altitudeM: 131),
        Wgs84Vertex(latitude: 16.502, longitude: 104.7, altitudeM: 132),
      ]),
      source: BoundarySource.googleEarth,
      verificationStatus: BoundaryVerificationStatus.verified,
      actorMembershipId: 'member-2',
      occurredAt: occurredAt.add(const Duration(hours: 1)),
      sourceFileName: 'parcel.kml',
      sourceFileHash: 'sha256:test',
    );

    final restored = LandParcelMapper.fromJson(LandParcelMapper.toJson(source));

    expect(restored.boundary, source.boundary);
    expect(restored.centroid, source.centroid);
    expect(restored.areaM2, source.areaM2);
    expect(restored.perimeterM, source.perimeterM);
    expect(restored.boundaryVersion, 2);
    expect(restored.boundaryHistory, hasLength(2));
    expect(restored.boundaryHistory.last.sourceFileName, 'parcel.kml');
    expect(restored.boundaryHistory.last.sourceFileHash, 'sha256:test');
    expect(restored.legacyMetadata['crop'], 'Lúa');
    expect(() => restored.boundaryHistory.clear(), throwsUnsupportedError);
  });

  test('update persists new immutable boundary history atomically', () async {
    final original = parcel();
    await repository.create(original);
    final historyBefore = await database.query(
      SqliteLandParcelRepository.boundaryVersionTable,
      where: 'parcel_id = ? AND version = 1',
      whereArgs: [original.id],
    );
    final updated = original.replaceBoundary(
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.5, longitude: 104.7),
        Wgs84Vertex(latitude: 16.5, longitude: 104.702),
        Wgs84Vertex(latitude: 16.502, longitude: 104.7),
      ]),
      source: BoundarySource.manual,
      verificationStatus: BoundaryVerificationStatus.verified,
      actorMembershipId: 'member-2',
      occurredAt: occurredAt.add(const Duration(hours: 1)),
    );

    await repository.update(updated);
    final restored = await repository.getById(
      farmId: 'farm-1',
      id: original.id,
    );

    expect(restored?.boundaryVersion, 2);
    expect(restored?.boundaryHistory.map((item) => item.version), [1, 2]);
    expect(restored?.verificationStatus, BoundaryVerificationStatus.verified);
    final historyAfter = await database.query(
      SqliteLandParcelRepository.boundaryVersionTable,
      where: 'parcel_id = ? AND version = 1',
      whereArgs: [original.id],
    );
    expect(historyAfter, historyBefore);
    expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('history insert failure rolls back parent update', () async {
    final original = parcel();
    final blocker = parcel(id: 'blocker', code: 'BLOCKER');
    await repository.create(original);
    await repository.create(blocker);
    await database.insert(SqliteLandParcelRepository.boundaryVersionTable, {
      'id': 'parcel-1-boundary-2',
      'parcel_id': blocker.id,
      'version': 99,
      'schema_version': LandParcel.currentSchemaVersion,
      'payload_json': '{}',
    });
    final updated = original.replaceBoundary(
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.5, longitude: 104.7),
        Wgs84Vertex(latitude: 16.5, longitude: 104.702),
        Wgs84Vertex(latitude: 16.502, longitude: 104.7),
      ]),
      source: BoundarySource.manual,
      verificationStatus: BoundaryVerificationStatus.measured,
      actorMembershipId: 'member-2',
      occurredAt: occurredAt.add(const Duration(hours: 1)),
    );

    await expectLater(() => repository.update(updated), throwsA(anything));

    final parent = await database.query(
      SqliteLandParcelRepository.parcelTable,
      columns: ['boundary_version'],
      where: 'id = ?',
      whereArgs: [original.id],
    );
    expect(parent.single['boundary_version'], 1);
    final restored = await repository.getById(
      farmId: original.farmId,
      id: original.id,
    );
    expect(restored?.boundaryVersion, 1);
    expect(restored?.boundaryHistory, hasLength(1));
    expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('duplicate parcel code in one farm is rejected', () async {
    await repository.create(parcel());

    expect(() => repository.create(parcel(id: 'parcel-2')), throwsA(anything));
    expect(await repository.listByFarm('farm-1'), hasLength(1));
  });

  test('transaction rolls back parcel and history together', () async {
    final source = parcel();

    await expectLater(
      () => repository.transaction<void>((transaction) async {
        await transaction.create(source);
        throw StateError('force rollback');
      }),
      throwsStateError,
    );

    expect(await repository.getById(farmId: 'farm-1', id: source.id), isNull);
    final historyRows = await database.query(
      SqliteLandParcelRepository.boundaryVersionTable,
    );
    expect(historyRows, isEmpty);
  });

  test('disable keeps verified boundary audit history', () async {
    final source = parcel(verification: BoundaryVerificationStatus.verified);
    await repository.create(source);

    await repository.setActive(
      farmId: source.farmId,
      id: source.id,
      active: false,
      actorMembershipId: 'member-2',
      occurredAt: occurredAt.add(const Duration(hours: 1)),
    );

    expect(await repository.listByFarm('farm-1'), isEmpty);
    final disabled = await repository.getById(farmId: 'farm-1', id: source.id);
    expect(disabled?.active, isFalse);
    expect(disabled?.boundaryHistory, hasLength(1));
    expect(disabled?.verificationStatus, BoundaryVerificationStatus.verified);
  });

  test('Firestore contract uses separate parcel and history paths', () {
    final source = parcel();
    final document = LandParcelFirestoreMapper.parcelToDocument(source);

    expect(
      LandParcelFirestoreMapper.parcelDocumentPath(source),
      'landParcels/parcel-1',
    );
    expect(document.containsKey('boundaryHistory'), isFalse);
    expect(
      LandParcelFirestoreMapper.boundaryVersionDocumentPath(
        source.boundaryHistory.single,
      ),
      'landParcels/parcel-1/boundaryVersions/parcel-1-boundary-1',
    );
    final restored = LandParcelFirestoreMapper.parcelFromDocument(
      document,
      source.boundaryHistory.map(
        LandParcelFirestoreMapper.boundaryVersionToDocument,
      ),
    );
    expect(restored.boundary, source.boundary);
  });

  group('legacy migration', () {
    final valid = FieldModel(
      id: 'legacy-1',
      name: 'Legacy field',
      area: 999,
      crop: 'Coffee',
      status: 'legacy-status',
      polygon: const [
        LatLng(16.5, 104.7),
        LatLng(16.5, 104.701),
        LatLng(16.501, 104.7),
      ],
      photoPaths: const ['legacy.jpg'],
      perimeter: 777,
      measurementMethod: 'old-device-mode',
      gpsAccuracy: 3.5,
      measuredAt: occurredAt,
    );
    final policy = LegacyFieldMigrationPolicy(
      farmId: 'farm-1',
      actorMembershipId: 'migration-member',
      occurredAt: occurredAt,
      parcelCode: (field) => 'LEGACY-${field.id}',
      isActive: (_) => true,
      boundarySource: (_) => BoundarySource.imported,
      verificationStatus: (_) => BoundaryVerificationStatus.draft,
    );

    test(
      'is idempotent, skips malformed geometry and preserves legacy data',
      () async {
        const migration = LandParcelLegacyMigration();
        final malformed = <String, Object?>{'id': 'broken'};
        final invalidGeometry = FieldModel(
          id: 'invalid-geometry',
          name: 'Broken polygon',
          area: 0,
          crop: '',
          status: '',
          polygon: const [LatLng(16.5, 104.7), LatLng(16.5, 104.701)],
        );

        final first = await migration.migrate(
          legacyRecords: [valid, malformed, invalidGeometry],
          policy: policy,
          repository: repository,
        );
        final second = await migration.migrate(
          legacyRecords: [valid, malformed],
          policy: policy,
          repository: repository,
        );

        expect(first.migratedIds, ['legacy-1']);
        expect(
          first.skipped.map((item) => item.reason),
          containsAll([
            LegacyMigrationSkipReason.malformedRecord,
            LegacyMigrationSkipReason.invalidGeometry,
          ]),
        );
        expect(second.migratedIds, isEmpty);
        expect(
          second.skipped.map((item) => item.reason),
          containsAll([
            LegacyMigrationSkipReason.existingParcel,
            LegacyMigrationSkipReason.malformedRecord,
          ]),
        );
        final migrated = await repository.getById(
          farmId: 'farm-1',
          id: valid.id,
        );
        expect(migrated?.boundaryHistory, hasLength(1));
        expect(migrated?.legacyMetadata['crop'], valid.crop);
        expect(migrated?.legacyMetadata['reportedArea'], valid.area);
        expect(
          migrated?.legacyMetadata['measurementMethod'],
          valid.measurementMethod,
        );
        expect(valid.area, 999);
        expect(valid.polygon, hasLength(3));
      },
    );

    test(
      'reports duplicate parcel code without changing legacy records',
      () async {
        final duplicatePolicy = LegacyFieldMigrationPolicy(
          farmId: 'farm-1',
          actorMembershipId: 'migration-member',
          occurredAt: occurredAt,
          parcelCode: (_) => 'DUPLICATE',
          isActive: (_) => true,
          boundarySource: (_) => BoundarySource.imported,
          verificationStatus: (_) => BoundaryVerificationStatus.draft,
        );
        final secondField = FieldModel(
          id: 'legacy-2',
          name: 'Second',
          area: valid.area,
          crop: valid.crop,
          status: valid.status,
          polygon: valid.polygon,
          photoPaths: valid.photoPaths,
          perimeter: valid.perimeter,
          measurementMethod: valid.measurementMethod,
          gpsAccuracy: valid.gpsAccuracy,
          measuredAt: valid.measuredAt,
        );

        final report = await const LandParcelLegacyMigration().migrate(
          legacyRecords: [valid, secondField],
          policy: duplicatePolicy,
          repository: repository,
        );

        expect(report.migratedIds, ['legacy-1']);
        expect(
          report.skipped.single.reason,
          LegacyMigrationSkipReason.duplicateParcelCode,
        );
        expect(secondField.name, 'Second');
      },
    );
  });
}
