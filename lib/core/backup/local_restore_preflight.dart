import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'local_database_snapshot.dart';

class RestorePreflightException implements Exception {
  const RestorePreflightException(this.reason, {this.database, this.step});

  final String reason;
  final String? database;
  final String? step;
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
      final path =
          '$temporaryDirectory/agrico-restore-'
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
    var step = 'schema';
    try {
      final versionRows = await current.rawQuery('PRAGMA user_version');
      final version = versionRows.single['user_version'];
      if (payload['databaseVersion'] != version) {
        throw RestorePreflightException(
          'schemaVersion',
          database: databaseName,
        );
      }
      final schema = await current.rawQuery(
        "SELECT type, name, sql FROM sqlite_master WHERE type IN ('table', 'index') "
        "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' "
        "AND sql IS NOT NULL ORDER BY type DESC, name",
      );
      final tables = <String>{
        for (final row in schema)
          if (row['type'] == 'table') row['name']! as String,
      };
      // Android owns this locale table and may create it when opening the
      // disposable database. Older backups included it; do not recreate it.
      final saved = Map<String, dynamic>.from(
        payload['tables'] as Map<String, dynamic>,
      )..remove('android_metadata');
      // Backups made before land-only parcel numbering lack the empty v3
      // counter table. Its CREATE TABLE comes from the current app schema.
      final optionalMissing = databaseName == 'agrico.db'
          ? {
              'agrico_location_parcel_sequences_v3',
              'parcel_work_resources',
              'parcel_work_events',
              'parcel_work_assignments',
              'parcel_stage_snapshots',
              'parcel_derivations',
              'farm_tasks_v2',
              'agrico_production_parcel_sequences_v4',
              'agrico_production_standalone_plot_sequences_v1',
              'inventory_items_v2',
              'inventory_movements_v2',
            }
          : <String>{};
      final missing = tables.difference(saved.keys.toSet());
      final productionCode = RegExp(r'^(.+)-L([0-9]{3,})(?:-T([0-9]{3,}))?$');
      final standaloneProductionCode = RegExp(r'^(.+)-T([0-9]{3,})$');
      final productionRows = (saved['land_parcels'] as List? ?? const []).where(
        (raw) {
          final row = raw as Map;
          final code = row['parcel_code']?.toString() ?? '';
          final match = productionCode.firstMatch(code);
          if (match == null) {
            return false;
          }
          // Exclude issued administrative codes from the previous allocator.
          final metadata = row['payload_json'] is String
              ? jsonDecode(row['payload_json'] as String)
                    as Map<String, dynamic>
              : <String, dynamic>{};
          final location = [
            metadata['countryCode'],
            metadata['provinceCode'],
            metadata['districtCode'],
            metadata['villageCode'],
          ];
          return !(match.group(3) == null &&
              location.every((value) => value != null) &&
              match.group(1) == location.join('-'));
        },
      );
      final standaloneProductionRows =
          (saved['land_parcels'] as List? ?? const []).where((raw) {
            final row = raw as Map;
            final code = row['parcel_code']?.toString() ?? '';
            return productionCode.firstMatch(code) == null &&
                standaloneProductionCode.hasMatch(code);
          });
      if (missing.contains('agrico_production_parcel_sequences_v4') &&
          productionRows.isNotEmpty) {
        throw RestorePreflightException('tables', database: databaseName);
      }
      if (missing.contains('agrico_production_standalone_plot_sequences_v1') &&
          standaloneProductionRows.isNotEmpty) {
        throw RestorePreflightException('tables', database: databaseName);
      }
      const inventoryTables = {'inventory_items_v2', 'inventory_movements_v2'};
      if (missing.intersection(inventoryTables).isNotEmpty &&
          inventoryTables.any(
            (name) => (saved[name] as List? ?? const []).isNotEmpty,
          )) {
        throw RestorePreflightException('tables', database: databaseName);
      }
      if (missing.intersection({
            'parcel_work_resources',
            'parcel_work_events',
            'parcel_work_assignments',
          }).isNotEmpty &&
          [
            'parcel_work_resources',
            'parcel_work_events',
            'parcel_work_assignments',
          ].any((name) => (saved[name] as List? ?? const []).isNotEmpty)) {
        throw RestorePreflightException('tables', database: databaseName);
      }
      if (missing.intersection({
            'parcel_stage_snapshots',
            'parcel_derivations',
          }).isNotEmpty &&
          [
            'parcel_stage_snapshots',
            'parcel_derivations',
          ].any((name) => (saved[name] as List? ?? const []).isNotEmpty)) {
        throw RestorePreflightException('tables', database: databaseName);
      }
      if (missing.contains('agrico_location_parcel_sequences_v3') &&
          (saved['land_parcels'] as List? ?? const []).any(
            (row) => RegExp(
              r'-L[0-9]{5}$',
            ).hasMatch((row as Map)['parcel_code']?.toString() ?? ''),
          )) {
        throw RestorePreflightException('tables', database: databaseName);
      }
      if (!tables.containsAll(saved.keys) ||
          !optionalMissing.containsAll(missing)) {
        throw RestorePreflightException('tables', database: databaseName);
      }
      staged = await factory.openDatabase(path);
      await staged.execute('PRAGMA foreign_keys = OFF');
      for (final row in schema.where((row) => row['type'] == 'table')) {
        step = 'table ${row['name']}';
        await staged.execute(row['sql']! as String);
      }
      step = 'rows';
      await staged.transaction((tx) async {
        for (final table in saved.entries) {
          step = 'rows ${table.key}';
          if (!RegExp(r'^[a-zA-Z_][a-zA-Z_0-9]*$').hasMatch(table.key)) {
            throw const FormatException('Invalid table name.');
          }
          for (final item in table.value as List) {
            final values = (item as Map<String, dynamic>).map((key, value) {
              if (value is Map<String, dynamic>) {
                if (value.length != 1 || value['blobBase64'] is! String) {
                  throw const FormatException('Invalid binary data.');
                }
                return MapEntry(
                  key,
                  base64Decode(value['blobBase64'] as String),
                );
              }
              return MapEntry(key, value);
            });
            await tx.insert(table.key, values);
          }
        }
      });
      for (final row in schema.where((row) => row['type'] == 'index')) {
        step = 'index ${row['name']}';
        await staged.execute(row['sql']! as String);
      }
      if (databaseName == 'agrico.db' &&
          tables.contains('agrico_production_parcel_sequences_v4')) {
        step = 'production numbering';
        final counters = await staged.query(
          'agrico_production_parcel_sequences_v4',
        );
        for (final raw in productionRows) {
          final row = raw as Map;
          final match = productionCode.firstMatch(
            row['parcel_code'] as String,
          )!;
          final block = int.parse(match.group(2)!);
          final plot = match.group(3) == null
              ? null
              : int.parse(match.group(3)!);
          final project = match.group(1)!;
          bool covers(int parent, int number) => counters.any(
            (counter) =>
                counter['farm_id'] == row['farm_id'] &&
                counter['project_code'] == project &&
                counter['parent_block_number'] == parent &&
                (counter['last_sequence']! as int) >= number,
          );
          if (block < 1 ||
              (plot != null && plot < 1) ||
              !covers(0, block) ||
              (plot != null && !covers(block, plot))) {
            throw RestorePreflightException(
              'integrity',
              database: databaseName,
              step: step,
            );
          }
        }
      }
      if (databaseName == 'agrico.db' &&
          tables.contains('agrico_production_standalone_plot_sequences_v1')) {
        step = 'production numbering';
        final standaloneCounters = await staged.query(
          'agrico_production_standalone_plot_sequences_v1',
        );
        for (final raw in standaloneProductionRows) {
          final row = raw as Map;
          final match = standaloneProductionCode.firstMatch(
            row['parcel_code'] as String,
          )!;
          final project = match.group(1)!;
          final plot = int.parse(match.group(2)!);
          final covered = standaloneCounters.any(
            (counter) =>
                counter['farm_id'] == row['farm_id'] &&
                counter['project_code'] == project &&
                (counter['last_sequence']! as int) >= plot,
          );
          if (plot < 1 || !covered) {
            throw RestorePreflightException(
              'integrity',
              database: databaseName,
              step: step,
            );
          }
        }
      }
      step = 'integrity';
      if ((await staged.rawQuery(
            'PRAGMA integrity_check',
          )).single.values.single !=
          'ok') {
        throw RestorePreflightException('integrity', database: databaseName);
      }
      if ((await staged.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw RestorePreflightException('foreignKeys', database: databaseName);
      }
      if (databaseName == 'agrico.db' && tables.containsAll(inventoryTables)) {
        step = 'inventory reconciliation';
        final wrongFarm = await staged.rawQuery('''
          SELECT m.id FROM inventory_movements_v2 m
          JOIN inventory_items_v2 i ON i.id = m.item_id
          WHERE m.farm_id != i.farm_id LIMIT 1
        ''');
        final wrongStock = await staged.rawQuery('''
          SELECT i.id FROM inventory_items_v2 i
          LEFT JOIN inventory_movements_v2 m ON m.item_id = i.id
          GROUP BY i.id, i.stock
          HAVING i.stock != COALESCE(SUM(
            CASE m.kind WHEN 'receipt' THEN m.quantity
                        WHEN 'issue' THEN -m.quantity ELSE 0 END
          ), 0) LIMIT 1
        ''');
        if (wrongFarm.isNotEmpty || wrongStock.isNotEmpty) {
          throw RestorePreflightException(
            'integrity',
            database: databaseName,
            step: step,
          );
        }
      }
    } on RestorePreflightException {
      rethrow;
    } on DatabaseException {
      throw RestorePreflightException(
        'sqlite',
        database: databaseName,
        step: step,
      );
    } finally {
      await staged?.close();
      await factory.deleteDatabase(path);
    }
  }
}
