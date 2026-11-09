import '../periods/period_lock.dart';
import '../approval/sqlite_document_approval.dart';
import '../approval/native_approval_guard.dart';
import '../../features/integration/data/period_close_repository.dart';

import 'dart:convert';
import '../production/source_governance.dart';
import '../../features/integration/data/production_cost_workflow_repository.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'local_database_snapshot.dart';
import 'local_media_snapshot.dart';
import 'local_restore_preflight.dart';

/// The pending file is written only after the user confirms a preflighted
/// backup. Applying it runs before the application's database providers open.
class LocalRestoreActivation {
  LocalRestoreActivation(this.directory, this.factory);

  final Directory directory;
  final DatabaseFactory factory;
  String _step = 'pending.read';

  File get _pending =>
      File(p.join(directory.path, 'agrico-restore-pending.json'));
  File get _result =>
      File(p.join(directory.path, 'agrico-restore-result.json'));

  Future<void> schedule(Uint8List bytes) async {
    LocalMediaSnapshot.validate(bytes);
    final data = LocalDatabaseSnapshot.decodeDatabases(bytes);
    if (data.length != 2 || !data.containsKey('agrico_costs.db')) {
      throw const RestorePreflightException('missingCosts');
    }
    if (await _pending.exists()) {
      throw StateError('A restore is already scheduled.');
    }
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final temporary = File('${_pending.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'id': id, 'backup': base64Encode(bytes)}),
      flush: true,
    );
    await temporary.rename(_pending.path);
  }

  Future<bool> applyPending() async {
    _step = 'pending.read';
    if (!await _pending.exists()) return false;
    final pending =
        jsonDecode(await _pending.readAsString()) as Map<String, dynamic>;
    final id = pending['id'] as String;
    if (!RegExp(r'^\d+$').hasMatch(id)) {
      throw const FormatException('Invalid restore identifier.');
    }
    final bytes = base64Decode(pending['backup'] as String);
    LocalMediaSnapshot.validate(Uint8List.fromList(bytes));
    final primaryPath = p.join(directory.path, 'agrico.db');
    final costsPath = p.join(directory.path, 'agrico_costs.db');
    final previous = File(
      p.join(directory.path, 'agrico-before-restore-$id.json'),
    );
    Database? primary;
    Database? costs;
    try {
      _step = 'database.open';
      primary = await factory.openDatabase(primaryPath);
      costs = await factory.openDatabase(costsPath);
      _step = 'preflight';
      await LocalRestorePreflight.validate(
        bytes: Uint8List.fromList(bytes),
        primary: primary,
        costs: costs,
        factory: factory,
        temporaryDirectory: directory.path,
      );
      if (!await previous.exists()) {
        _step = 'previous.snapshot';
        final old = await LocalMediaSnapshot.create(primary, costs);
        await previous.writeAsBytes(old, flush: true);
      }
      _step = 'database.close';
      await primary.close();
      primary = null;
      await costs.close();
      costs = null;
      _step = 'media.materialize';
      final materialized = await LocalMediaSnapshot.materialize(
        Uint8List.fromList(bytes),
        directory,
      );
      await _replaceBoth(primaryPath, costsPath, materialized);
      // The SQLite commit has completed. A later status-file or cleanup error
      // must not be reported as a rolled-back restore.
      try {
        await _writeResult('applied');
      } catch (_) {
        // The committed database state remains authoritative.
      }
      try {
        await _pending.delete();
      } catch (_) {
        // A retry on the next launch applies the same snapshot idempotently.
      }
      return true;
    } catch (failure) {
      await _writeResult('failed', failure: failure);
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

  Future<void> _replaceBoth(
    String mainPath,
    String costsPath,
    Uint8List bytes,
  ) async {
    final data = LocalDatabaseSnapshot.decodeDatabases(bytes);
    final db = await factory.openDatabase(mainPath);
    var committed = false;
    try {
      _step = 'main.journal';
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      if ((await db.rawQuery(
            'PRAGMA journal_mode=DELETE',
          )).single.values.single.toString().toLowerCase() !=
          'delete') {
        throw StateError('Main database cannot use rollback journal.');
      }
      await db.execute('PRAGMA synchronous=FULL');
      await db.execute('PRAGMA foreign_keys=OFF');
      _step = 'costs.attach';
      await db.execute('ATTACH DATABASE ? AS restore_costs', [costsPath]);
      _step = 'costs.journal';
      await db.rawQuery('PRAGMA restore_costs.wal_checkpoint(TRUNCATE)');
      if ((await db.rawQuery(
            'PRAGMA restore_costs.journal_mode=DELETE',
          )).single.values.single.toString().toLowerCase() !=
          'delete') {
        throw StateError('Costs database cannot use rollback journal.');
      }
      await db.execute('PRAGMA restore_costs.synchronous=FULL');
      await db.transaction((tx) async {
        final requireApprovalB = await NativeApprovalGuard.enabled(tx);
        await PeriodLock.removeGuards(tx);
        await NativeApprovalGuard.removeForRestore(tx);
        await SourceGovernance.removeStorageGuardsForRestore(tx);
        for (final entry in <String, String>{
          'agrico.db': 'main',
          'agrico_costs.db': 'restore_costs',
        }.entries) {
          final tables = Map<String, dynamic>.from(
            data[entry.key]!['tables'] as Map<String, dynamic>,
          );
          if (entry.key == 'agrico.db') {
            // An accepted older empty snapshot must not retain newer scope
            // assignments or warehouse balances from the current database.
            for (final table in [
              ...PeriodLock.tables,
              NativeApprovalGuard.lease,
              'inventory_warehouses_v1',
              'inventory_warehouse_sequences_v1',
              'inventory_warehouse_stock_v1',
              'inventory_transfers_v1',
              'personnel_departments_v1',
              'personnel_department_sequences_v1',
              'personnel_payroll_adjustments_v1',
              'personnel_payroll_adjustment_costs_v1',
              'personnel_payroll_adjustment_sequences_v1',
              'personnel_payroll_refunds_v1',
            ]) {
              if (!tables.containsKey(table)) {
                final installed = await tx.rawQuery(
                  "SELECT name FROM main.sqlite_master WHERE type='table' AND name=?",
                  [table],
                );
                if (installed.isNotEmpty) tables[table] = <dynamic>[];
              }
            }

            if (!tables.containsKey('farm_task_work_links_v1')) {
              final links = await tx.rawQuery(
                "SELECT name FROM main.sqlite_master WHERE type='table' "
                "AND name='farm_task_work_links_v1'",
              );
              if (links.isNotEmpty) {
                tables['farm_task_work_links_v1'] = <dynamic>[];
              }
            }
            final installed = await tx.rawQuery(
              "SELECT name FROM main.sqlite_master WHERE type='table' AND name='company_catalog_entries_v1'",
            );
            if (installed.isNotEmpty &&
                !tables.containsKey('company_catalog_entries_v1')) {
              for (final name in [
                'company_catalog_entries_v1',
                'company_catalog_requests_v1',
                'company_catalog_audit_v1',
                'company_catalog_bootstrap_v1',
              ]) {
                tables[name] = <dynamic>[];
              }
            }
          }
          for (final table in tables.keys) {
            if (table == 'android_metadata') continue;
            _checkName(table);
            _step = '${entry.key}.delete.$table';
            if (entry.key == 'agrico.db' && table == 'land_parcels') {
              final columns = await tx.rawQuery(
                'PRAGMA main.table_info(land_parcels)',
              );
              if (columns.any(
                (column) => column['name'] == 'parent_block_id',
              )) {
                await tx.execute(
                  'DELETE FROM main.land_parcels WHERE parent_block_id IS NOT NULL',
                );
              }
            }
            await tx.execute('DELETE FROM ${entry.value}."$table"');
          }
          for (final table in tables.entries) {
            if (table.key == 'android_metadata') continue;
            final rows = List<dynamic>.from(table.value as List);
            if (entry.key == 'agrico.db' && table.key == 'land_parcels') {
              // Typed parcel hierarchy has one level: landBlock -> fieldPlot.
              rows.sort((a, b) {
                final aChild = (a as Map)['parent_block_id'] != null ? 1 : 0;
                final bChild = (b as Map)['parent_block_id'] != null ? 1 : 0;
                return aChild.compareTo(bChild);
              });
            }
            for (final item in rows) {
              final row = item as Map<String, dynamic>;
              final columns = row.keys.toList();
              for (final column in columns) {
                _checkName(column);
              }
              final names = columns.map((name) => '"$name"').join(', ');
              final placeholders = List.filled(columns.length, '?').join(', ');
              _step = '${entry.key}.insert.${table.key}';
              await tx.rawInsert(
                'INSERT INTO ${entry.value}."${table.key}" ($names) '
                'VALUES ($placeholders)',
                columns.map((name) => _sqliteValue(row[name])).toList(),
              );
            }
          }
        }
        await PeriodCloseRepository.validate(tx);
        await PeriodLock.install(tx);
        final sourceTables = (await tx.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        )).map((r) => r['name']).toSet();
        if (sourceTables.contains(SourceGovernance.versions)) {
          await SourceGovernance.createSchema(tx);
        }
        if (sourceTables.contains(ProductionCostWorkflowRepository.policies)) {
          await ProductionCostWorkflowRepository.createSchema(tx);
        }
        await ProductionCostWorkflowRepository.validate(tx);
        await SqliteDocumentApproval.validate(tx);
        await NativeApprovalGuard.validate(tx);
        // Current application enforcement cannot be disabled by an older backup.
        if (requireApprovalB || await NativeApprovalGuard.enabled(tx))
          await NativeApprovalGuard.install(tx);
        if (sourceTables.contains(SqliteDocumentApproval.requests)) {
          await SqliteDocumentApproval.createSchema(tx);
        }
        _step = 'catalog.quarantine';
        // Device send authority cannot be resurrected by a backup restore.
        final syncTables = await tx.rawQuery(
          "SELECT name FROM main.sqlite_master WHERE type='table' "
          "AND (name LIKE 'company_catalog_sync_%' OR name LIKE 'company_workspace_%')",
        );
        for (final row in syncTables) {
          final table = row['name']! as String;
          _checkName(table);
          await tx.execute('DELETE FROM main."$table"');
        }
        if (syncTables.any(
          (r) => r['name'] == 'company_catalog_sync_device_v1',
        )) {
          await tx.execute('''INSERT INTO company_catalog_sync_device_v1
            (farm_id,restore_blocked) SELECT DISTINCT farm_id,1
            FROM company_catalog_entries_v1
            UNION SELECT DISTINCT farm_id,1 FROM company_catalog_requests_v1
            UNION SELECT 'local-farm',1''');
        }
        for (final alias in ['main', 'restore_costs']) {
          _step = '$alias.integrity';
          if ((await tx.rawQuery(
            'PRAGMA $alias.foreign_key_check',
          )).isNotEmpty) {
            throw const FormatException('Restored foreign keys are invalid.');
          }
          if ((await tx.rawQuery(
                'PRAGMA $alias.integrity_check',
              )).single.values.single !=
              'ok') {
            throw const FormatException(
              'Restored SQLite integrity check failed.',
            );
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

  Future<void> _writeResult(String status, {Object? failure}) async {
    await _result.writeAsString(
      jsonEncode({
        'status': status,
        if (failure != null) 'step': _step,
        if (failure != null) 'diagnostic': _diagnostic(failure),
      }),
      flush: true,
    );
  }

  // Store categories only, never SQL arguments, business data or passwords.
  static String _diagnostic(Object failure) {
    if (failure is RestorePreflightException) {
      return 'preflight:${failure.reason}:${failure.database}:${failure.step}';
    }
    final message = failure.toString().toLowerCase();
    for (final category in [
      'foreign key constraint',
      'unique constraint',
      'not null constraint',
      'check constraint',
      'no such table',
      'no such column',
      'database is locked',
      'database is busy',
      'readonly database',
      'disk is full',
      'rollback journal',
      'cannot change',
      'cannot delete',
      'immutable',
      'append-only',
    ]) {
      if (message.contains(category)) return '${failure.runtimeType}:$category';
    }
    return failure.runtimeType.toString();
  }

  Future<Uint8List?> previousBackup() async {
    final previous =
        directory
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  p.basename(file.path).startsWith('agrico-before-restore-') &&
                  p.basename(file.path).endsWith('.json'),
            )
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    return previous.isEmpty ? null : previous.first.readAsBytes();
  }
}

Future<void> applyPendingRestore() async {
  final directory = await getApplicationDocumentsDirectory();
  final activation = LocalRestoreActivation(directory, databaseFactory);
  try {
    await activation.applyPending();
  } catch (failure) {
    final pending = File(p.join(directory.path, 'agrico-restore-pending.json'));
    if (await pending.exists()) {
      await pending.rename(
        '${pending.path}.${DateTime.now().microsecondsSinceEpoch}.failed',
      );
    }
    await activation._writeResult('failed', failure: failure);
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

Future<Uint8List?> previousLocalRestoreBackup() async {
  final directory = await getApplicationDocumentsDirectory();
  return LocalRestoreActivation(directory, databaseFactory).previousBackup();
}

Future<String?> localRestoreDiagnostic() async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File(p.join(directory.path, 'agrico-restore-result.json'));
  if (!await file.exists()) return null;
  final value = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  if (value['status'] != 'failed' || value['step'] == null) return null;
  return '${value['step']} | ${value['diagnostic']}';
}
