import 'package:sqflite/sqflite.dart';

import '../../domain/entities/parcel_work.dart';
import '../../domain/repositories/parcel_work_repository.dart';
import 'sqlite_land_parcel_repository.dart';

/// Persistent, farm-scoped work resources and parcel activity history.
class SqliteParcelWorkRepository implements ParcelWorkRepository {
  const SqliteParcelWorkRepository(this.database);

  final Database database;
  static const resourcesTable = 'parcel_work_resources';
  static const eventsTable = 'parcel_work_events';
  static const assignmentsTable = 'parcel_work_assignments';

  static Future<void> createSchema(DatabaseExecutor db) async {
    await SqliteLandParcelRepository.createSchema(db);
    await db.execute('''CREATE TABLE IF NOT EXISTS $resourcesTable (
      id TEXT PRIMARY KEY, farm_id TEXT NOT NULL, kind TEXT NOT NULL,
      code TEXT NOT NULL, name TEXT NOT NULL, active INTEGER NOT NULL,
      UNIQUE(farm_id, kind, code))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS $eventsTable (
      id TEXT PRIMARY KEY, farm_id TEXT NOT NULL, parcel_id TEXT NOT NULL,
      phase TEXT NOT NULL, description TEXT NOT NULL,
      occurred_at TEXT NOT NULL, actor_membership_id TEXT NOT NULL,
      area_m2 REAL, notes TEXT,
      FOREIGN KEY(parcel_id) REFERENCES ${SqliteLandParcelRepository.parcelTable}(id)
        ON DELETE RESTRICT)''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_parcel_work_events '
        'ON $eventsTable(farm_id, parcel_id, occurred_at)');
    await db.execute('''CREATE TABLE IF NOT EXISTS $assignmentsTable (
      event_id TEXT NOT NULL, resource_id TEXT NOT NULL,
      PRIMARY KEY(event_id, resource_id),
      FOREIGN KEY(event_id) REFERENCES $eventsTable(id) ON DELETE RESTRICT,
      FOREIGN KEY(resource_id) REFERENCES $resourcesTable(id) ON DELETE RESTRICT)''');
  }

  @override
  Future<void> register(WorkResource resource) async {
    resource.validate();
    await database.insert(resourcesTable, {
      'id': resource.id, 'farm_id': resource.farmId,
      'kind': resource.kind.name, 'code': resource.code,
      'name': resource.name, 'active': resource.active ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  @override
  Future<List<WorkResource>> resources(String farmId) async {
    final rows = await database.query(resourcesTable,
        where: 'farm_id = ?', whereArgs: [farmId], orderBy: 'kind, code');
    return List.unmodifiable(rows.map((row) => WorkResource(
      id: row['id']! as String, farmId: row['farm_id']! as String,
      kind: WorkResourceKind.values.byName(row['kind']! as String),
      code: row['code']! as String, name: row['name']! as String,
      active: row['active'] == 1,
    )));
  }

  @override
  Future<void> record(ParcelWorkEvent event) async {
    event.validate();
    await database.transaction((tx) async {
      final parcel = await tx.query(SqliteLandParcelRepository.parcelTable,
          columns: ['id'], where: 'id = ? AND farm_id = ?',
          whereArgs: [event.parcelId, event.farmId], limit: 1);
      if (parcel.isEmpty) throw StateError('Parcel is outside the current farm.');
      for (final (kind, ids) in [
        (WorkResourceKind.machine, event.machineIds),
        (WorkResourceKind.worker, event.workerIds),
      ]) {
        for (final id in ids) {
          final resource = await tx.query(resourcesTable, columns: ['id'],
            where: 'id = ? AND farm_id = ? AND kind = ? AND active = 1',
            whereArgs: [id, event.farmId, kind.name], limit: 1);
          if (resource.isEmpty) {
            throw StateError('Work resource is unavailable in this farm.');
          }
        }
      }
      await tx.insert(eventsTable, {
        'id': event.id, 'farm_id': event.farmId,
        'parcel_id': event.parcelId, 'phase': event.phase.name,
        'description': event.description,
        'occurred_at': event.occurredAt.toUtc().toIso8601String(),
        'actor_membership_id': event.actorMembershipId,
        'area_m2': event.areaM2, 'notes': event.notes,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      for (final id in [...event.machineIds, ...event.workerIds]) {
        await tx.insert(assignmentsTable, {
          'event_id': event.id, 'resource_id': id,
        });
      }
    });
  }

  @override
  Future<List<ParcelWorkEvent>> events(String farmId, String parcelId) async {
    final rows = await database.query(eventsTable,
      where: 'farm_id = ? AND parcel_id = ?', whereArgs: [farmId, parcelId],
      orderBy: 'occurred_at, id',
    );
    final resourcesById = {for (final r in await resources(farmId)) r.id: r};
    final result = <ParcelWorkEvent>[];
    for (final row in rows) {
      final assignments = await database.query(assignmentsTable,
        columns: ['resource_id'], where: 'event_id = ?',
        whereArgs: [row['id']], orderBy: 'resource_id');
      final assigned = assignments.map((item) =>
          resourcesById[item['resource_id'] as String]).whereType<WorkResource>();
      result.add(ParcelWorkEvent(
        id: row['id']! as String, farmId: farmId, parcelId: parcelId,
        phase: ParcelWorkPhase.values.byName(row['phase']! as String),
        description: row['description']! as String,
        occurredAt: DateTime.parse(row['occurred_at']! as String),
        actorMembershipId: row['actor_membership_id']! as String,
        areaM2: (row['area_m2'] as num?)?.toDouble(),
        notes: row['notes'] as String?,
        machineIds: assigned.where((r) => r.kind == WorkResourceKind.machine)
            .map((r) => r.id).toList(),
        workerIds: assigned.where((r) => r.kind == WorkResourceKind.worker)
            .map((r) => r.id).toList(),
      ));
    }
    return List.unmodifiable(result);
  }
}
