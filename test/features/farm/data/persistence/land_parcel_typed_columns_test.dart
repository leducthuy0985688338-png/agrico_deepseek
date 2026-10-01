import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/models/land_parcel_mapper.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;
  final occurredAt = DateTime.utc(2026, 9, 30, 6, 0, 0);

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

  LandParcel block({String id = 'block-1', String code = 'AGR-NONG-L001'}) =>
      LandParcel.create(
        id: id,
        farmId: 'farm-1',
        parcelCode: code,
        name: 'Lô ກະສິກຳ',
        boundary: triangle(),
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: occurredAt,
        kind: ParcelLayer.landBlock,
      );

  LandParcel plot({
    String id = 'plot-1',
    String code = 'AGR-NONG-T001',
    String? parentBlockId,
  }) => LandParcel.create(
    id: id,
    farmId: 'farm-1',
    parcelCode: code,
    name: 'Thửa ດິນ',
    boundary: triangle(),
    boundarySource: BoundarySource.gps,
    verificationStatus: BoundaryVerificationStatus.measured,
    actorMembershipId: 'member-1',
    occurredAt: occurredAt,
    kind: ParcelLayer.fieldPlot,
    parentBlockId: parentBlockId,
  );

  group('fresh database schema', () {
    test('land_parcels has typed P02A columns', () async {
      final cols = await database.rawQuery(
        'PRAGMA table_info(${SqliteLandParcelRepository.parcelTable})',
      );
      final names = cols.map((r) => r['name'] as String).toSet();
      expect(names, contains('project_id'));
      expect(names, contains('kind'));
      expect(names, contains('parent_block_id'));
    });

    test('P02A indexes exist', () async {
      final indexes = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );
      final names = indexes.map((row) => row['name'] as String).toSet();
      expect(names, contains('idx_land_parcels_project_kind'));
      expect(names, contains('idx_land_parcels_parent'));
    });

    test('migration ledger table exists', () async {
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'agrico_schema_migrations'",
      );
      expect(tables, hasLength(1));
    });
  });

  group('typed columns are written and read', () {
    test('land block stores kind=landBlock, parent_block_id NULL', () async {
      final source = block();
      await SqliteLandParcelRepository(database).create(source);

      final rows = await database.query(
        SqliteLandParcelRepository.parcelTable,
        where: 'id = ?',
        whereArgs: [source.id],
      );
      expect(rows.single['kind'], 'landBlock');
      expect(rows.single['parent_block_id'], isNull);
      expect(rows.single['project_id'], isNull);

      final restored = await SqliteLandParcelRepository(database)
          .getById(farmId: 'farm-1', id: source.id);
      expect(restored?.kind, ParcelLayer.landBlock);
      expect(restored?.parentBlockId, isNull);
      expect(restored?.projectId, isNull);
    });

    test('field plot with parent stores kind=fieldPlot, parent_block_id', () async {
      await SqliteLandParcelRepository(database).create(block());
      final child = plot(parentBlockId: 'block-1');
      await SqliteLandParcelRepository(database).create(child);

      final rows = await database.query(
        SqliteLandParcelRepository.parcelTable,
        where: 'id = ?',
        whereArgs: [child.id],
      );
      expect(rows.single['kind'], 'fieldPlot');
      expect(rows.single['parent_block_id'], 'block-1');

      final restored = await SqliteLandParcelRepository(database)
          .getById(farmId: 'farm-1', id: child.id);
      expect(restored?.kind, ParcelLayer.fieldPlot);
      expect(restored?.parentBlockId, 'block-1');
    });

    test('project_id round-trips through SQLite', () async {
      final source = LandParcel.create(
        id: 'block-1',
        farmId: 'farm-1',
        parcelCode: 'AGR-NONG-L001',
        name: 'Lô',
        boundary: triangle(),
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: occurredAt,
        projectId: 'AGR-NONG',
      );
      await SqliteLandParcelRepository(database).create(source);

      final restored = await SqliteLandParcelRepository(database)
          .getById(farmId: 'farm-1', id: source.id);
      expect(restored?.projectId, 'AGR-NONG');
    });
  });

  group('column wins over stale metadata', () {
    test('typed kind overrides stale legacyMetadata parcelLayer', () {
      final source = block();
      final json = LandParcelMapper.toJson(source);
      // Simulate a stale mirror that claims fieldPlot.
      final legacy = Map<String, Object?>.from(
        json['legacyMetadata']! as Map,
      );
      legacy['parcelLayer'] = 'fieldPlot';
      json['legacyMetadata'] = legacy;
      json['kind'] = 'landBlock';

      final restored = LandParcelMapper.fromJson(json);
      expect(restored.kind, ParcelLayer.landBlock);
      expect(restored.parentBlockId, isNull);
    });

    test('present-but-null parentBlockId is not restored from metadata', () {
      final source = plot(parentBlockId: null);
      final json = LandParcelMapper.toJson(source);
      // Inject a stale parent into metadata.
      final legacy = Map<String, Object?>.from(
        json['legacyMetadata']! as Map,
      );
      legacy['parentLandBlockId'] = 'block-999';
      json['legacyMetadata'] = legacy;
      json['parentBlockId'] = null;
      json['kind'] = 'fieldPlot';

      final restored = LandParcelMapper.fromJson(json);
      expect(restored.kind, ParcelLayer.fieldPlot);
      expect(restored.parentBlockId, isNull);
    });

    test('legacy payload without kind falls back to metadata', () {
      final source = plot(parentBlockId: 'block-1');
      final json = LandParcelMapper.toJson(source);
      json.remove('kind');
      json.remove('parentBlockId');
      json.remove('projectId');
      final legacy = Map<String, Object?>.from(
        json['legacyMetadata']! as Map,
      );
      legacy['parcelLayer'] = 'fieldPlot';
      legacy['parentLandBlockId'] = 'block-1';
      json['legacyMetadata'] = legacy;

      final restored = LandParcelMapper.fromJson(json);
      expect(restored.kind, ParcelLayer.fieldPlot);
      expect(restored.parentBlockId, 'block-1');
    });

    test('mapper drops stale parent key before writing canonical value', () {
      final source = plot(parentBlockId: null);
      final json = LandParcelMapper.toJson(source);
      final legacy = json['legacyMetadata']! as Map;
      expect(legacy.containsKey('parentLandBlockId'), isFalse);
      expect(legacy.containsKey('parcelLayer'), isTrue);
      expect(legacy['parcelLayer'], 'fieldPlot');
    });

    test('unknown kind value is rejected, not silently defaulted', () {
      final source = block();
      final json = LandParcelMapper.toJson(source);
      json['kind'] = 'unknown';
      expect(
        () => LandParcelMapper.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('unknown legacy parcelLayer value is rejected', () {
      final source = block();
      final json = LandParcelMapper.toJson(source);
      json.remove('kind');
      final legacy = Map<String, Object?>.from(
        json['legacyMetadata']! as Map,
      );
      legacy['parcelLayer'] = 'odd-layer';
      json['legacyMetadata'] = legacy;
      expect(
        () => LandParcelMapper.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('unicode and identity preservation', () {
    test('Lao and Vietnamese names survive SQLite round trip', () async {
      final source = LandParcel.create(
        id: 'unicode-1',
        farmId: 'farm-1',
        parcelCode: 'AGR-NONG-T001',
        name: 'Thửa ດິນ ກະສິກຳ',
        boundary: triangle(),
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: occurredAt,
        kind: ParcelLayer.fieldPlot,
      );
      await SqliteLandParcelRepository(database).create(source);
      final restored = await SqliteLandParcelRepository(database)
          .getById(farmId: 'farm-1', id: source.id);
      expect(restored?.name, 'Thửa ດິນ ກະສິກຳ');
      expect(restored?.id, 'unicode-1');
      expect(restored?.parcelCode, 'AGR-NONG-T001');
      expect(restored?.farmId, 'farm-1');
    });
  });

  group('updateKind', () {
    test('link plot to block via updateKind, then detach', () async {
      await SqliteLandParcelRepository(database).create(block());
      final repo = SqliteLandParcelRepository(database);
      final standalone = plot(parentBlockId: null);
      await repo.create(standalone);

      final linked = standalone.updateKind(
        kind: ParcelLayer.fieldPlot,
        parentBlockId: 'block-1',
        actorMembershipId: 'member-2',
        occurredAt: occurredAt.add(const Duration(hours: 1)),
      );
      await repo.update(linked);
      final restored = await repo.getById(
        farmId: 'farm-1',
        id: standalone.id,
      );
      expect(restored?.parentBlockId, 'block-1');

      final detached = restored!.updateKind(
        kind: ParcelLayer.fieldPlot,
        parentBlockId: null,
        actorMembershipId: 'member-3',
        occurredAt: occurredAt.add(const Duration(hours: 2)),
      );
      await repo.update(detached);
      final after = await repo.getById(
        farmId: 'farm-1',
        id: standalone.id,
      );
      expect(after?.parentBlockId, isNull);
      // Identity is preserved across detach.
      expect(after?.id, standalone.id);
      expect(after?.parcelCode, standalone.parcelCode);
    });

    test('land block cannot receive a parent through updateKind', () {
      final source = block();
      expect(
        () => source.updateKind(
          kind: ParcelLayer.landBlock,
          parentBlockId: 'block-2',
          actorMembershipId: 'member-1',
          occurredAt: occurredAt,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}