import 'package:sqflite/sqflite.dart';

import '../../domain/entities/parcel_land_history.dart';
import '../../domain/repositories/parcel_land_history_repository.dart';
import 'sqlite_land_parcel_repository.dart';

class SqliteParcelLandHistoryRepository implements ParcelLandHistoryRepository {
  const SqliteParcelLandHistoryRepository(this.database);
  final Database database;

  static const snapshotsTable = 'parcel_stage_snapshots';
  static const derivationsTable = 'parcel_derivations';

  static Future<void> createSchema(DatabaseExecutor db) async {
    await SqliteLandParcelRepository.createSchema(db);
    await db.execute('''CREATE TABLE IF NOT EXISTS $snapshotsTable (
      id TEXT PRIMARY KEY, farm_id TEXT NOT NULL, parcel_id TEXT NOT NULL,
      stage TEXT NOT NULL, boundary_version INTEGER NOT NULL,
      area_m2 REAL NOT NULL, recorded_at TEXT NOT NULL,
      actor_membership_id TEXT NOT NULL,
      UNIQUE(parcel_id, stage, boundary_version),
      FOREIGN KEY(parcel_id) REFERENCES ${SqliteLandParcelRepository.parcelTable}(id)
        ON DELETE RESTRICT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS $derivationsTable (
      id TEXT PRIMARY KEY, farm_id TEXT NOT NULL,
      source_parcel_id TEXT NOT NULL, target_parcel_id TEXT NOT NULL,
      kind TEXT NOT NULL, derived_area_m2 REAL NOT NULL,
      occurred_at TEXT NOT NULL, actor_membership_id TEXT NOT NULL,
      UNIQUE(source_parcel_id, target_parcel_id),
      FOREIGN KEY(source_parcel_id) REFERENCES ${SqliteLandParcelRepository.parcelTable}(id)
        ON DELETE RESTRICT,
      FOREIGN KEY(target_parcel_id) REFERENCES ${SqliteLandParcelRepository.parcelTable}(id)
        ON DELETE RESTRICT)''');
  }

  @override
  Future<void> capture(ParcelStageSnapshot snapshot) async {
    snapshot.validate();
    await database.transaction((tx) async {
      final parcel = await SqliteLandParcelRepository(tx).getById(
        farmId: snapshot.farmId, id: snapshot.parcelId);
      final versions = parcel?.boundaryHistory.where((version) =>
          version.version == snapshot.boundaryVersion).toList() ?? [];
      if (versions.length != 1 ||
          (versions.single.areaM2 - snapshot.areaM2).abs() > 0.001) {
        throw StateError('Stage must reference an existing parcel boundary.');
      }
      await tx.insert(snapshotsTable, {
        'id': snapshot.id, 'farm_id': snapshot.farmId,
        'parcel_id': snapshot.parcelId, 'stage': snapshot.stage.name,
        'boundary_version': snapshot.boundaryVersion,
        'area_m2': snapshot.areaM2,
        'recorded_at': snapshot.recordedAt.toUtc().toIso8601String(),
        'actor_membership_id': snapshot.actorMembershipId,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  @override
  Future<List<ParcelStageSnapshot>> snapshots(String farmId, String parcelId) async {
    final rows = await database.query(snapshotsTable,
      where: 'farm_id = ? AND parcel_id = ?', whereArgs: [farmId, parcelId],
      orderBy: 'recorded_at, id');
    return List.unmodifiable(rows.map((row) => ParcelStageSnapshot(
      id: row['id']! as String, farmId: farmId, parcelId: parcelId,
      stage: ParcelLandStage.values.byName(row['stage']! as String),
      boundaryVersion: row['boundary_version']! as int,
      areaM2: (row['area_m2']! as num).toDouble(),
      recordedAt: DateTime.parse(row['recorded_at']! as String),
      actorMembershipId: row['actor_membership_id']! as String,
    )));
  }

  @override
  Future<void> link(ParcelDerivation derivation) async {
    await database.transaction((tx) => linkScoped(tx, derivation));
  }

  /// Joins a caller-owned parcel/spatial transaction for atomic subdivision.
  static Future<void> linkScoped(
      DatabaseExecutor tx, ParcelDerivation derivation) async {
    derivation.validate();
    final parcels = SqliteLandParcelRepository(tx);
    final source = await parcels.getById(
          farmId: derivation.farmId, id: derivation.sourceParcelId);
    final target = await parcels.getById(
          farmId: derivation.farmId, id: derivation.targetParcelId);
    if (source == null || target == null ||
          derivation.derivedAreaM2 > source.areaM2 + 0.001 ||
          derivation.derivedAreaM2 > target.areaM2 + 0.001) {
      throw StateError('Derivation must link parcels in one farm with valid area.');
    }
    await tx.insert(derivationsTable, {
        'id': derivation.id, 'farm_id': derivation.farmId,
        'source_parcel_id': derivation.sourceParcelId,
        'target_parcel_id': derivation.targetParcelId,
        'kind': derivation.kind.name,
        'derived_area_m2': derivation.derivedAreaM2,
        'occurred_at': derivation.occurredAt.toUtc().toIso8601String(),
        'actor_membership_id': derivation.actorMembershipId,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  @override
  Future<List<ParcelDerivation>> derivations(String farmId, String parcelId) async {
    final rows = await database.query(derivationsTable,
      where: 'farm_id = ? AND (source_parcel_id = ? OR target_parcel_id = ?)',
      whereArgs: [farmId, parcelId, parcelId], orderBy: 'occurred_at, id');
    return List.unmodifiable(rows.map((row) => ParcelDerivation(
      id: row['id']! as String, farmId: farmId,
      sourceParcelId: row['source_parcel_id']! as String,
      targetParcelId: row['target_parcel_id']! as String,
      kind: ParcelDerivationKind.values.byName(row['kind']! as String),
      derivedAreaM2: (row['derived_area_m2']! as num).toDouble(),
      occurredAt: DateTime.parse(row['occurred_at']! as String),
      actorMembershipId: row['actor_membership_id']! as String,
    )));
  }
}
