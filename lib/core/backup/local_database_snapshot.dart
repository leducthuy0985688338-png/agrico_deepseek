import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

/// A versioned, read-only logical snapshot of local AGRICO SQLite files.
/// It includes SQLite rows, not external photographs referenced by file paths.
class LocalDatabaseSnapshot {
  const LocalDatabaseSnapshot._();

  static const format = 'agrico-local-sqlite';
  static const version = 2;

  static Future<Uint8List> create(
    Database database, {
    Database? costsDatabase,
  }) async {
    final primary = await _read(database);
    final costs = costsDatabase == null ? null : await _read(costsDatabase);
    final payload = <String, Object?>{
      'databases': <String, Object?>{
        'agrico.db': primary,
        if (costs != null) 'agrico_costs.db': costs,
      },
    };
    final body = jsonEncode(payload);
    final envelope = <String, Object?>{
      'format': format,
      'version': version,
      'sha256': sha256.convert(utf8.encode(body)).toString(),
      'payload': body,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  static Future<Map<String, Object?>> _read(Database database) =>
      database.transaction((tx) async {
        final schema = await tx.rawQuery('PRAGMA user_version');
        final tables = await tx.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' "
          "ORDER BY name",
        );
        final data = <String, Object?>{};
        for (final table in tables) {
          final name = table['name']! as String;
          if (!RegExp(r'^[a-zA-Z_][a-zA-Z_0-9]*$').hasMatch(name)) {
            throw const FormatException('Invalid SQLite table name.');
          }
          final rows = await tx.rawQuery('SELECT * FROM "$name"');
          data[name] = rows.map((row) => row.map((key, value) => MapEntry(
                key,
                value is Uint8List ? {'blobBase64': base64Encode(value)} : value,
              ))).toList();
        }
        return <String, Object?>{
          'databaseVersion': schema.first['user_version'],
          'tables': data,
        };
      });

  /// Validate without writing to SQLite. The caller can show table counts
  /// before a separate, explicitly confirmed restore workflow is introduced.
  static Map<String, int> inspect(Uint8List bytes) {
    final databases = decodeDatabases(bytes);
    final counts = <String, int>{};
    for (final entry in databases.entries) {
      final tables = entry.value['tables'] as Map<String, dynamic>;
      for (final table in tables.entries) {
        if (table.key == 'android_metadata') continue;
        counts['${entry.key}/${table.key}'] = (table.value as List).length;
      }
    }
    return counts;
  }

  /// Checked data for preflight. A v1 backup intentionally lacks costs.
  static Map<String, Map<String, dynamic>> decodeDatabases(Uint8List bytes) {
    final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (root['format'] != format ||
        (root['version'] != 1 && root['version'] != version)) {
      throw const FormatException('Unsupported AGRICO backup format.');
    }
    final body = root['payload'];
    if (body is! String ||
        sha256.convert(utf8.encode(body)).toString() != root['sha256']) {
      throw const FormatException('AGRICO backup integrity check failed.');
    }
    final payload = jsonDecode(body) as Map<String, dynamic>;
    if (root['version'] == 1) {
      return {'agrico.db': payload};
    }
    final databases = payload['databases'] as Map<String, dynamic>;
    if (!databases.containsKey('agrico.db')) {
      throw const FormatException('Missing primary database.');
    }
    final checked = <String, Map<String, dynamic>>{};
    for (final entry in databases.entries) {
      if (entry.key != 'agrico.db' && entry.key != 'agrico_costs.db') {
        throw const FormatException('Unknown database.');
      }
      checked[entry.key] = entry.value as Map<String, dynamic>;
    }
    return checked;
  }
}
