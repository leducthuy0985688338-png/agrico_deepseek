import 'package:sqflite/sqflite.dart';

import '../../domain/entities/parcel_work.dart';
import '../../domain/repositories/task_work_repository.dart';
import 'sqlite_parcel_work_repository.dart';

class SqliteTaskWorkRepository implements TaskWorkRepository {
  const SqliteTaskWorkRepository(this.database);
  final Database database;
  static const linksTable = 'farm_task_work_links_v1';
  static const tasksTable = 'farm_tasks_v2';

  /// Called after the task and parcel work tables have been created.
  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS $linksTable (
      event_id TEXT NOT NULL PRIMARY KEY,
      task_id TEXT NOT NULL,
      FOREIGN KEY(event_id) REFERENCES ${SqliteParcelWorkRepository.eventsTable}(id)
        ON DELETE RESTRICT,
      FOREIGN KEY(task_id) REFERENCES $tasksTable(id) ON DELETE RESTRICT
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_farm_task_work_links_v1_task '
      'ON $linksTable(task_id, event_id)',
    );
  }

  @override
  Future<void> record(String taskId, ParcelWorkEvent event) async {
    if (taskId.trim().isEmpty) {
      throw const FormatException('Task identity is required.');
    }
    event.validate();
    await database.transaction((tx) async {
      final tasks = await tx.query(
        tasksTable,
        columns: ['parcel_id'],
        where: 'id = ? AND farm_id = ?',
        whereArgs: [taskId, event.farmId],
        limit: 1,
      );
      if (tasks.isEmpty || tasks.single['parcel_id'] != event.parcelId) {
        throw StateError(
          'Task and work must belong to the same farm and parcel.',
        );
      }
      await SqliteParcelWorkRepository.recordInTransaction(tx, event);
      await tx.insert(linksTable, {
        'task_id': taskId,
        'event_id': event.id,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  @override
  Future<List<ParcelWorkEvent>> events(String farmId, String taskId) async {
    final tasks = await database.query(
      tasksTable,
      columns: ['parcel_id'],
      where: 'id = ? AND farm_id = ?',
      whereArgs: [taskId, farmId],
      limit: 1,
    );
    if (tasks.isEmpty) {
      throw StateError('Task is missing in this farm.');
    }
    final parcelId = tasks.single['parcel_id'] as String?;
    if (parcelId == null) {
      return const [];
    }
    final links = await database.query(
      linksTable,
      columns: ['event_id'],
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
    final ids = {for (final row in links) row['event_id'] as String};
    final events = await SqliteParcelWorkRepository(
      database,
    ).events(farmId, parcelId);
    return List.unmodifiable(events.where((event) => ids.contains(event.id)));
  }
}
