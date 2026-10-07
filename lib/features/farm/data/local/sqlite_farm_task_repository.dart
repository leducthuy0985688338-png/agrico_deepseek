import 'package:sqflite/sqflite.dart';

import '../../domain/entities/farm_task.dart';
import '../../domain/repositories/farm_task_repository.dart';
import 'sqlite_land_parcel_repository.dart';
import 'sqlite_parcel_work_repository.dart';

class SqliteFarmTaskRepository implements FarmTaskRepository {
  const SqliteFarmTaskRepository(this.database);

  final Database database;
  static const table = 'farm_tasks_v2';

  static Future<void> createSchema(DatabaseExecutor db) async {
    await SqliteParcelWorkRepository.createSchema(db);
    await db.execute('''CREATE TABLE IF NOT EXISTS $table (
      id TEXT PRIMARY KEY,
      farm_id TEXT NOT NULL,
      title TEXT NOT NULL CHECK(length(trim(title)) > 0),
      description TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN
        ('pending', 'inProgress', 'completed', 'delayed')),
      due_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      parcel_id TEXT,
      worker_resource_id TEXT,
      machine_resource_id TEXT,
      FOREIGN KEY(parcel_id) REFERENCES ${SqliteLandParcelRepository.parcelTable}(id)
        ON DELETE RESTRICT,
      FOREIGN KEY(worker_resource_id) REFERENCES ${SqliteParcelWorkRepository.resourcesTable}(id)
        ON DELETE RESTRICT,
      FOREIGN KEY(machine_resource_id) REFERENCES ${SqliteParcelWorkRepository.resourcesTable}(id)
        ON DELETE RESTRICT
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_farm_tasks_v2_scope_due '
      'ON $table(farm_id, due_at, id)',
    );
  }

  @override
  Future<void> create(FarmTask task) async {
    task.validate();
    await database.transaction((tx) async {
      if (task.parcelId != null) {
        final parcel = await tx.query(
          SqliteLandParcelRepository.parcelTable,
          columns: ['id'],
          where: 'id = ? AND farm_id = ?',
          whereArgs: [task.parcelId, task.farmId],
          limit: 1,
        );
        if (parcel.isEmpty) {
          throw StateError('Task parcel is outside the farm.');
        }
      }
      for (final (id, kind) in [
        (task.workerResourceId, 'worker'),
        (task.machineResourceId, 'machine'),
      ]) {
        if (id == null) {
          continue;
        }
        final resource = await tx.query(
          SqliteParcelWorkRepository.resourcesTable,
          columns: ['id'],
          where: 'id = ? AND farm_id = ? AND kind = ? AND active = 1',
          whereArgs: [id, task.farmId, kind],
          limit: 1,
        );
        if (resource.isEmpty) {
          throw StateError('Task resource is unavailable in this farm.');
        }
      }
      await tx.insert(table, {
        'id': task.id,
        'farm_id': task.farmId,
        'title': task.title,
        'description': task.description,
        'status': task.status.name,
        'due_at': task.dueAt.toIso8601String(),
        'created_at': task.createdAt.toIso8601String(),
        'parcel_id': task.parcelId,
        'worker_resource_id': task.workerResourceId,
        'machine_resource_id': task.machineResourceId,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  @override
  Future<void> update(FarmTask task) async {
    task.validate();
    await database.transaction((tx) async {
      final rows = await tx.query(table,
        where: 'id = ? AND farm_id = ?', whereArgs: [task.id, task.farmId],
        limit: 1);
      if (rows.isEmpty) throw StateError('Task is missing in this farm.');
      final previous = rows.single;
      if (task.parcelId != null && task.parcelId != previous['parcel_id']) {
        final parcel = await tx.query(SqliteLandParcelRepository.parcelTable,
          columns: ['id'], where: 'id = ? AND farm_id = ? AND active = 1',
          whereArgs: [task.parcelId, task.farmId], limit: 1);
        if (parcel.isEmpty) throw StateError('Task parcel is unavailable.');
      }
      for (final (id, kind, column) in [
        (task.workerResourceId, 'worker', 'worker_resource_id'),
        (task.machineResourceId, 'machine', 'machine_resource_id'),
      ]) {
        if (id == null || id == previous[column]) continue;
        final resource = await tx.query(SqliteParcelWorkRepository.resourcesTable,
          columns: ['id'],
          where: 'id = ? AND farm_id = ? AND kind = ? AND active = 1',
          whereArgs: [id, task.farmId, kind], limit: 1);
        if (resource.isEmpty) throw StateError('Task resource is unavailable.');
      }
      final changed = await tx.update(table, {
        'title': task.title, 'description': task.description,
        'due_at': task.dueAt.toIso8601String(), 'parcel_id': task.parcelId,
        'worker_resource_id': task.workerResourceId,
        'machine_resource_id': task.machineResourceId,
      }, where: 'id = ? AND farm_id = ?', whereArgs: [task.id, task.farmId]);
      if (changed != 1) throw StateError('Task is missing in this farm.');
    });
  }

  @override
  Future<List<FarmTask>> listByFarm(String farmId) async {
    final rows = await database.query(
      table,
      where: 'farm_id = ?',
      whereArgs: [farmId],
      orderBy: 'due_at, id',
    );
    return List.unmodifiable(
      rows.map(
        (row) => FarmTask(
          id: row['id']! as String,
          farmId: row['farm_id']! as String,
          title: row['title']! as String,
          description: row['description']! as String,
          status: FarmTaskStatus.values.byName(row['status']! as String),
          dueAt: DateTime.parse(row['due_at']! as String),
          createdAt: DateTime.parse(row['created_at']! as String),
          parcelId: row['parcel_id'] as String?,
          workerResourceId: row['worker_resource_id'] as String?,
          machineResourceId: row['machine_resource_id'] as String?,
        ),
      ),
    );
  }

  @override
  Future<void> changeStatus({required String farmId, required String id,
      required FarmTaskStatus status}) async {
    if (status != FarmTaskStatus.inProgress && status != FarmTaskStatus.delayed) {
      throw const FormatException('Use the separate completion operation.');
    }
    final changed = await database.update(table, {'status': status.name},
      where: 'farm_id = ? AND id = ? AND status != ? AND status != ?',
      whereArgs: [farmId, id, FarmTaskStatus.completed.name, status.name]);
    if (changed != 1) {
      throw StateError('Task is missing, completed or already in this status.');
    }
  }

  @override
  Future<void> complete({required String farmId, required String id}) async {
    final changed = await database.update(
      table,
      {'status': FarmTaskStatus.completed.name},
      where: "farm_id = ? AND id = ? AND status != ?",
      whereArgs: [farmId, id, FarmTaskStatus.completed.name],
    );
    if (changed != 1) {
      throw StateError('Task is missing or already completed in this farm.');
    }
  }
}
