import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'local_database_snapshot.dart';

class RestorePreflightException implements Exception {
  const RestorePreflightException(this.reason, {this.database});

  final String reason;
  final String? database;
}

/// Builds disposable SQLite files from a checked backup and the current
/// schema. Live databases are only queried; they are never changed here.
class LocalRestorePreflight {
  const LocalRestorePreflight._();

  static Future<Map<String, int>> validate({
    required Uint8List bytes,
    required Database primary,
    required Database costs,
    required DatabaseFactory factory,
    required String temporaryDirectory,
  }) async {
    final data = LocalDatabaseSnapshot.decodeDatabases(bytes);
    if (data.length != 2 || !data.containsKey('agrico_costs.db')) {
      throw const RestorePreflightException('missingCosts');
    }
    var index = 0;
    for (final entry in <String, Database>{
      'agrico.db': primary,
      'agrico_costs.db': costs,
    }.entries) {
      final path = '$temporaryDirectory/agrico-restore-'
          '${DateTime.now().microsecondsSinceEpoch}-${index++}.db';
      await _validateDatabase(
        path: path,
        factory: factory,
        current: entry.value,
        payload: data[entry.key]!,
        databaseName: entry.key,
      );
    }
    return LocalDatabaseSnapshot.inspect(bytes);
  }

  static Future<void> _validateDatabase({
    required String path,
    required DatabaseFactory factory,
    required Database current,
    required Map<String, dynamic> payload,
    required String databaseName,
  }) async {
    Database? staged;
    try {
      final versionRows = await current.rawQuery('PRAGMA user_version');
      final version = versionRows.single['user_version'];
      if (payload['databaseVersion'] != version) {
        throw RestorePreflightException('schemaVersion', database: databaseName);
      }
      final schema = await current.rawQuery(
        "SELECT type, name, sql FROM sqlite_master WHERE type IN ('table', 'index') "
        "AND name NOT LIKE 'sqlite_%' AND sql IS NOT NULL ORDER BY type DESC, name",
      );
      final tables = <String>{
        for (final row in schema)
          if (row['type'] == 'table') row['name']! as String,
      };
      final saved = payload['tables'] as Map<String, dynamic>;
      if (tables.length != saved.length || !tables.containsAll(saved.keys)) {
        throw RestorePreflightException('tables', database: databaseName);
      }
      staged = await factory.openDatabase(path);
      await staged.execute('PRAGMA foreign_keys = OFF');
      for (final row in schema.where((row) => row['type'] == 'table')) {
        await staged.execute(row['sql']! as String);
      }
      await staged.transaction((tx) async {
        for (final table in saved.entries) {
          if (!RegExp(r'^[a-zA-Z_][a-zA-Z_0-9]*$').hasMatch(table.key)) {
            throw const FormatException('Invalid table name.');
          }
          for (final item in table.value as List) {
            final values = (item as Map<String, dynamic>).map((key, value) {
              if (value is Map<String, dynamic>) {
                if (value.length != 1 || value['blobBase64'] is! String) {
                  throw const FormatException('Invalid binary data.');
                }
                return MapEntry(key, base64Decode(value['blobBase64'] as String));
              }
              return MapEntry(key, value);
            });
            await tx.insert(table.key, values);
          }
        }
      });
      for (final row in schema.where((row) => row['type'] == 'index')) {
        await staged.execute(row['sql']! as String);
      }
      if ((await staged.rawQuery('PRAGMA integrity_check')).single.values.single
          != 'ok') {
        throw RestorePreflightException('integrity', database: databaseName);
      }
      if ((await staged.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw RestorePreflightException('foreignKeys', database: databaseName);
      }
    } on RestorePreflightException {
      rethrow;
    } on DatabaseException {
      throw RestorePreflightException('sqlite', database: databaseName);
    } finally {
      await staged?.close();
      await factory.deleteDatabase(path);
    }
  }
}
