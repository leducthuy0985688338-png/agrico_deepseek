import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/workspace.dart';

class SqliteWorkspaceStore implements WorkspaceStore {
  SqliteWorkspaceStore(this.db);
  final Database db;
  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS company_workspace_outbox_v1 (farm TEXT NOT NULL, uid TEXT NOT NULL, id TEXT NOT NULL, entity TEXT NOT NULL, body TEXT NOT NULL, error TEXT, PRIMARY KEY(farm,uid,id))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS company_workspace_cache_v1 (farm TEXT NOT NULL, uid TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(farm,uid,id))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS company_workspace_device_v1 (farm TEXT NOT NULL, uid TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(farm,uid,id))',
    );
  }

  List<Object> args(String f, String u) => [f, u];
  @override
  Future<List<Json>> pending(String f, String u) async =>
      (await db.query(
            'company_workspace_outbox_v1',
            where: 'farm=? AND uid=?',
            whereArgs: args(f, u),
            orderBy: 'id',
          ))
          .map(
            (r) => {
              ...jsonMap(jsonDecode(r['body'] as String)),
              'error': r['error'],
            },
          )
          .toList();
  @override
  Future<void> enqueue(String f, String u, Json c) =>
      db.transaction((tx) async {
        final old = await tx.query(
          'company_workspace_outbox_v1',
          where: 'farm=? AND uid=? AND id=?',
          whereArgs: [f, u, c['id']],
        );
        if (old.isNotEmpty) {
          if (old.first['body'] != canonical(c)) {
            throw const WorkspaceFailure('conflict');
          }
          return;
        }
        final busy = await tx.query(
          'company_workspace_outbox_v1',
          where: 'farm=? AND uid=? AND entity=? AND error IS NULL',
          whereArgs: [f, u, c['entityId']],
        );
        if (busy.isNotEmpty) throw const WorkspaceFailure('pending');
        await tx.insert('company_workspace_outbox_v1', {
          'farm': f,
          'uid': u,
          'id': c['id'],
          'entity': c['entityId'],
          'body': canonical(c),
        });
      });
  Future<void> cache(DatabaseExecutor tx, String f, String u, Json r) async {
    final id = '${r['kind']}~${r['id']}';
    final old = await tx.query(
      'company_workspace_cache_v1',
      where: 'farm=? AND uid=? AND id=?',
      whereArgs: [f, u, id],
    );
    if (old.isNotEmpty &&
        (jsonMap(jsonDecode(old.first['body'] as String))['revision'] as int) >
            (r['revision'] as int)) {
      return;
    }
    await tx.insert('company_workspace_cache_v1', {
      'farm': f,
      'uid': u,
      'id': id,
      'body': canonical(r),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> accept(String f, String u, String id, Json response) =>
      db.transaction((tx) async {
        final result = jsonMap(response['result'] ?? {});
        for (final key in ['record', 'room']) {
          if (result[key] is Map) await cache(tx, f, u, jsonMap(result[key]));
        }
        final old = await tx.query(
          'company_workspace_device_v1',
          where: 'farm=? AND uid=? AND id=?',
          whereArgs: [f, u, 'generation'],
        );
        final generation = old.isEmpty
            ? 0
            : jsonMap(jsonDecode(old.first['body'] as String))['value'] as int;
        final next = response['inboxGeneration'] as int? ?? 0;
        if (next > generation) {
          await tx.insert('company_workspace_device_v1', {
            'farm': f,
            'uid': u,
            'id': 'generation',
            'body': jsonEncode({'value': next}),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await tx.delete(
          'company_workspace_outbox_v1',
          where: 'farm=? AND uid=? AND id=?',
          whereArgs: [f, u, id],
        );
      });
  @override
  Future<void> reject(String f, String u, String id, String error) async {
    await db.update(
      'company_workspace_outbox_v1',
      {'error': error},
      where: 'farm=? AND uid=? AND id=?',
      whereArgs: [f, u, id],
    );
  }

  @override
  Future<void> discard(String f, String u, String id) async {
    await db.delete(
      'company_workspace_outbox_v1',
      where: 'farm=? AND uid=? AND id=? AND error IS NOT NULL',
      whereArgs: [f, u, id],
    );
  }

  @override
  Future<List<Json>> records(String f, String u) async => (await db.query(
    'company_workspace_cache_v1',
    where: 'farm=? AND uid=?',
    whereArgs: [f, u],
  )).map((r) => jsonMap(jsonDecode(r['body'] as String))).toList();
  @override
  Future<void> replace(
    String f,
    String u,
    List<Json> records,
    int generation,
  ) => db.transaction((tx) async {
    final old = await tx.query(
      'company_workspace_device_v1',
      where: 'farm=? AND uid=? AND id=?',
      whereArgs: [f, u, 'generation'],
    );
    if (old.isNotEmpty &&
        (jsonMap(jsonDecode(old.first['body'] as String))['value'] as int) >
            generation) {
      return;
    }
    await tx.delete(
      'company_workspace_cache_v1',
      where: 'farm=? AND uid=?',
      whereArgs: [f, u],
    );
    for (final r in records) {
      await cache(tx, f, u, r);
    }
    await tx.insert('company_workspace_device_v1', {
      'farm': f,
      'uid': u,
      'id': 'generation',
      'body': jsonEncode({'value': generation}),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });
  @override
  Future<Json?> value(String f, String u, String key) async {
    final rows = await db.query(
      'company_workspace_device_v1',
      where: 'farm=? AND uid=? AND id=?',
      whereArgs: [f, u, key],
    );
    return rows.isEmpty
        ? null
        : jsonMap(jsonDecode(rows.first['body'] as String));
  }

  @override
  Future<void> putValue(String f, String u, String key, Json value) async {
    await db.insert('company_workspace_device_v1', {
      'farm': f,
      'uid': u,
      'id': key,
      'body': canonical(value),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> clearCache(String f, String u) async {
    await db.delete(
      'company_workspace_cache_v1',
      where: 'farm=? AND uid=?',
      whereArgs: [f, u],
    );
    await db.delete(
      'company_workspace_device_v1',
      where: "farm=? AND uid=? AND id!='snapshot_baseline'",
      whereArgs: [f, u],
    );
  }
}
