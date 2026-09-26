import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

/// A versioned, read-only logical snapshot of the local AGRICO SQLite file.
/// It includes SQLite rows, not external photographs referenced by file paths.
class LocalDatabaseSnapshot {
  const LocalDatabaseSnapshot._();

  static const format = 'agrico-local-sqlite';
  static const version = 1;

  static Future<Uint8List> create(Database database) async {
    final payload = await database.transaction((tx) async {
      final schema = await tx.rawQuery('PRAGMA user_version');
      final tables = await tx.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      final data = <String, Object?>{};
      for (final table in tables) {
        final name = table['name']! as String;
        if (!RegExp(r'^[a-zA-Z_][a-zA-Z_0-9]*$').hasMatch(name)) {
          throw const FormatException('Invalid SQLite table name.');
        }
        final rows = await tx.rawQuery('SELECT * FROM "$name"');
        data[name] = rows.map((row) => row.map((key, value) =>
            MapEntry(key, value is Uint8List
                ? {'blobBase64': base64Encode(value)} : value))).toList();
      }
      return <String, Object?>{
        'databaseVersion': schema.first['user_version'],
        'tables': data,
      };
    });
    final body = jsonEncode(payload);
    final envelope = <String, Object?>{
      'format': format,
      'version': version,
      'sha256': sha256.convert(utf8.encode(body)).toString(),
      'payload': body,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  /// Validate without writing to SQLite. The caller can show table counts
  /// before a separate, explicitly confirmed restore workflow is introduced.
  static Map<String, int> inspect(Uint8List bytes) {
    final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (root['format'] != format || root['version'] != version) {
      throw const FormatException('Unsupported AGRICO backup format.');
    }
    final body = root['payload'];
    if (body is! String ||
        sha256.convert(utf8.encode(body)).toString() != root['sha256']) {
      throw const FormatException('AGRICO backup integrity check failed.');
    }
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final tables = payload['tables'] as Map<String, dynamic>;
    return tables.map((key, value) => MapEntry(key, (value as List).length));
  }
}
