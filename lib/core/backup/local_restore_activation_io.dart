import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'local_database_snapshot.dart';
import 'local_restore_preflight.dart';

/// The pending file is written only after the user confirms a preflighted
/// backup. Applying it runs before the application's database providers open.
class LocalRestoreActivation {
  LocalRestoreActivation(this.directory, this.factory);

  final Directory directory;
  final DatabaseFactory factory;

  File get _pending => File(p.join(directory.path, 'agrico-restore-pending.json'));
  File get _result => File(p.join(directory.path, 'agrico-restore-result.json'));

  Future<void> schedule(Uint8List bytes) async {
    final data = LocalDatabaseSnapshot.decodeDatabases(bytes);
    if (data.length != 2 || !data.containsKey('agrico_costs.db')) {
      throw const RestorePreflightException('missingCosts');
    }
    if (await _pending.exists()) {
      throw StateError('A restore is already scheduled.');
    }
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final temporary = File('${_pending.path}.tmp');
    await temporary.writeAsString(jsonEncode({
      'id': id,
      'backup': base64Encode(bytes),
    }), flush: true);
    await temporary.rename(_pending.path);
  }

  Future<bool> applyPending() async {
    if (!await _pending.exists()) return false;
    final pending = jsonDecode(await _pending.readAsString())
        as Map<String, dynamic>;
    final id = pending['id'] as String;
    if (!RegExp(r'^\d+$').hasMatch(id)) {
      throw const FormatException('Invalid restore identifier.');
    }
    final bytes = base64Decode(pending['backup'] as String);
    final primaryPath = p.join(directory.path, 'agrico.db');
    final costsPath = p.join(directory.path, 'agrico_costs.db');
    final previous = File(p.join(directory.path, 'agrico-before-restore-$id.json'));
    Database? primary;
    Database? costs;
    try {
      primary = await factory.openDatabase(primaryPath);
      costs = await factory.openDatabase(costsPath);
      await LocalRestorePreflight.validate(
        bytes: Uint8List.fromList(bytes),
        primary: primary,
        costs: costs,
        factory: factory,
        temporaryDirectory: directory.path,
      );
      if (!await previous.exists()) {
        final old = await LocalDatabaseSnapshot.create(primary,
          costsDatabase: costs);
        await previous.writeAsBytes(old, flush: true);
      }
      await primary.close();
      primary = null;
      await costs.close();
      costs = null;
      await _replaceBoth(primaryPath, costsPath, Uint8List.fromList(bytes));
      await _writeResult('applied');
      await _pending.delete();
      return true;
    } catch (_) {
      await _writeResult('failed');
      // Keep the old snapshot for recovery, but avoid retrying a bad import
      // automatically on every launch.
      if (await _pending.exists()) {
        await _pending.rename('${_pending.path}.$id.failed');
      }
      rethrow;
    } finally {
      await primary?.close();
      await costs?.close();
    }
  }

  Future<void> _replaceBoth(String mainPath, String costsPath,
      Uint8List bytes) async {
    final data = LocalDatabaseSnapshot.decodeDatabases(bytes);
    final db = await factory.openDatabase(mainPath);
    var committed = false;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      if ((await db.rawQuery('PRAGMA journal_mode=DELETE')).single.values.single
          .toString().toLowerCase() != 'delete') {
        throw StateError('Main database cannot use rollback journal.');
      }
      await db.execute('PRAGMA synchronous=FULL');
      await db.execute('PRAGMA foreign_keys=OFF');
      await db.execute('ATTACH DATABASE ? AS restore_costs', [costsPath]);
      await db.rawQuery('PRAGMA restore_costs.wal_checkpoint(TRUNCATE)');
      if ((await db.rawQuery('PRAGMA restore_costs.journal_mode=DELETE'))
          .single.values.single.toString().toLowerCase() != 'delete') {
        throw StateError('Costs database cannot use rollback journal.');
      }
      await db.execute('PRAGMA restore_costs.synchronous=FULL');
      await db.transaction((tx) async {
        for (final entry in <String, String>{
          'agrico.db': 'main',
          'agrico_costs.db': 'restore_costs',
        }.entries) {
          final tables = data[entry.key]!['tables'] as Map<String, dynamic>;
          for (final table in tables.keys) {
            if (table == 'android_metadata') continue;
            _checkName(table);
            await tx.execute('DELETE FROM ${entry.value}."$table"');
          }
          for (final table in tables.entries) {
            if (table.key == 'android_metadata') continue;
            for (final item in table.value as List) {
              final row = item as Map<String, dynamic>;
              final columns = row.keys.toList();
              for (final column in columns) { _checkName(column); }
              final names = columns.map((name) => '"$name"').join(', ');
              final placeholders = List.filled(columns.length, '?').join(', ');
              await tx.rawInsert(
                'INSERT INTO ${entry.value}."${table.key}" ($names) '
                'VALUES ($placeholders)',
                columns.map((name) => _sqliteValue(row[name])).toList(),
              );
            }
          }
        }
        for (final alias in ['main', 'restore_costs']) {
          if ((await tx.rawQuery('PRAGMA $alias.foreign_key_check')).isNotEmpty) {
            throw const FormatException('Restored foreign keys are invalid.');
          }
          if ((await tx.rawQuery('PRAGMA $alias.integrity_check'))
              .single.values.single != 'ok') {
            throw const FormatException('Restored SQLite integrity check failed.');
          }
        }
      });
      committed = true;
    } finally {
      try {
        await db.close();
      } catch (_) {
        // A completed transaction is already committed. Closing an attached
        // connection must not turn that success into a reported rollback.
        if (!committed) rethrow;
      }
    }
  }

  static void _checkName(String name) {
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z_0-9]*$').hasMatch(name)) {
      throw const FormatException('Invalid SQLite identifier.');
    }
  }

  static Object? _sqliteValue(dynamic value) {
    if (value is Map<String, dynamic>) {
      if (value.length != 1 || value['blobBase64'] is! String) {
        throw const FormatException('Invalid binary value.');
      }
      return base64Decode(value['blobBase64'] as String);
    }
    return value;
  }

  Future<void> _writeResult(String status) async {
    await _result.writeAsString(jsonEncode({'status': status}), flush: true);
  }
}

Future<void> applyPendingRestore() async {
  final directory = await getApplicationDocumentsDirectory();
  final activation = LocalRestoreActivation(directory, databaseFactory);
  try {
    await activation.applyPending();
  } catch (_) {
    final pending = File(p.join(directory.path, 'agrico-restore-pending.json'));
    if (await pending.exists()) {
      await pending.rename('${pending.path}.${DateTime.now().microsecondsSinceEpoch}.failed');
    }
    await activation._writeResult('failed');
  }
}

Future<void> scheduleLocalRestore(Uint8List bytes) async {
  final directory = await getApplicationDocumentsDirectory();
  await LocalRestoreActivation(directory, databaseFactory).schedule(bytes);
}

Future<String?> localRestoreStatus() async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File(p.join(directory.path, 'agrico-restore-result.json'));
  if (!await file.exists()) return null;
  final value = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  return value['status'] as String?;
}
