import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'local_database_snapshot.dart';

/// Web has no app-private file directory. SQLite-only backups remain usable.
class LocalMediaSnapshot {
  const LocalMediaSnapshot._();

  static Future<Uint8List> create(Database primary, Database costs) =>
      LocalDatabaseSnapshot.create(primary, costsDatabase: costs);

  static Map<String, Uint8List> validate(Uint8List bytes) {
    LocalDatabaseSnapshot.decodeDatabases(bytes);
    return {};
  }
}
