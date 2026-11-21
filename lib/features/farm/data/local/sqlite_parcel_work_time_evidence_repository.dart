import 'package:sqflite/sqflite.dart';
import '../../application/parcel_work_time_productivity.dart';
import 'sqlite_parcel_work_repository.dart';

/// Persistent time evidence. Use only through an authorized application service.
class SqliteParcelWorkTimeEvidenceRepository {
  const SqliteParcelWorkTimeEvidenceRepository(this.database);
  final Database database;
  static const table = 'parcel_work_time_evidence';

  static Future<void> createSchema(DatabaseExecutor db) async {
    await SqliteParcelWorkRepository.createSchema(db);
    await db.execute("""CREATE TABLE IF NOT EXISTS $table (
      farm_id TEXT NOT NULL, parcel_id TEXT NOT NULL,
      event_id TEXT NOT NULL, resource_id TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('worker', 'machine')),
      minutes INTEGER NOT NULL CHECK(minutes > 0 AND minutes <= 2147483647),
      evidence_reference TEXT NOT NULL CHECK(length(trim(evidence_reference)) > 0),
      actor_membership_id TEXT NOT NULL, created_at TEXT NOT NULL,
      PRIMARY KEY(farm_id, event_id, kind, resource_id),
      FOREIGN KEY(event_id) REFERENCES ${SqliteParcelWorkRepository.eventsTable}(id),
      FOREIGN KEY(resource_id) REFERENCES ${SqliteParcelWorkRepository.resourcesTable}(id)
    )""");
  }

  Future<void> record({
    required String farmId,
    required String parcelId,
    required String actorMembershipId,
    required WorkTimeEvidence evidence,
  }) async {
    if (farmId.trim().isEmpty ||
        parcelId.trim().isEmpty ||
        actorMembershipId.trim().isEmpty ||
        evidence.eventId.trim().isEmpty ||
        evidence.resourceId.trim().isEmpty ||
        evidence.evidenceReference.trim().isEmpty ||
        evidence.minutes <= 0 ||
        evidence.minutes > 2147483647) {
      throw const FormatException('Invalid work time evidence.');
    }
    await database.transaction((tx) async {
      final event = await tx.query(
        SqliteParcelWorkRepository.eventsTable,
        columns: ['id'],
        where: 'id = ? AND farm_id = ? AND parcel_id = ?',
        whereArgs: [evidence.eventId, farmId, parcelId],
        limit: 1,
      );
      if (event.isEmpty) throw StateError('Work event outside parcel scope.');
      final assigned = await tx.rawQuery(
        """
        SELECT r.id FROM ${SqliteParcelWorkRepository.resourcesTable} r
        INNER JOIN ${SqliteParcelWorkRepository.assignmentsTable} a
          ON a.resource_id = r.id
        WHERE a.event_id = ? AND r.id = ? AND r.farm_id = ? AND r.kind = ?
        LIMIT 1
      """,
        [evidence.eventId, evidence.resourceId, farmId, evidence.kind.name],
      );
      if (assigned.isEmpty) throw StateError('Resource not assigned to event.');
      await tx.insert(table, {
        'farm_id': farmId,
        'parcel_id': parcelId,
        'event_id': evidence.eventId,
        'resource_id': evidence.resourceId,
        'kind': evidence.kind.name,
        'minutes': evidence.minutes,
        'evidence_reference': evidence.evidenceReference.trim(),
        'actor_membership_id': actorMembershipId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  Future<List<WorkTimeEvidence>> read({
    required String farmId,
    required String parcelId,
  }) async {
    final rows = await database.query(
      table,
      where: 'farm_id = ? AND parcel_id = ?',
      whereArgs: [farmId, parcelId],
      orderBy: 'event_id, kind, resource_id',
    );
    return List.unmodifiable(
      rows.map(
        (row) => WorkTimeEvidence(
          eventId: row['event_id']! as String,
          resourceId: row['resource_id']! as String,
          kind: WorkTimeResourceKind.values.byName(row['kind']! as String),
          minutes: row['minutes']! as int,
          evidenceReference: row['evidence_reference']! as String,
        ),
      ),
    );
  }
}
