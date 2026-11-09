import 'dart:convert';
import 'package:sqflite/sqflite.dart';

/// Historical reset for explicitly confirmed disposable test fixtures only.
/// Application startup must use the read-only [validateStartup] guard instead.
/// A missing marker is never authorization to reset installed business data.
/// Never touches parcels, geometry, shared catalog, finance, tasks, identity,
/// external media, backups or cloud data.
class ProductionV2TestCleanup {
  static const table = 'production_v2_test_cleanup_v1';
  static const legacyPrimaryTables = [
    'inventory_cost_outbox_v2',
    'production_field_links_v1',
    'production_logs',
    'production_seasons',
    'field_measurement_history',
    'fields',
  ];

  /// Inspect historical state without creating tables, advancing a marker or
  /// touching either database's business rows. Interrupted/unknown resets need
  /// an explicit recovery decision; startup must never resume their deletions.
  static Future<void> validateStartup(DatabaseExecutor primary) async {
    final installed = await primary.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    if (installed.isEmpty) return;
    // An empty table is safe to accept only after recognizing its historical
    // shape. Never create or repair an unknown marker schema during startup.
    final columns = await primary.rawQuery('PRAGMA table_info($table)');
    const expectedTypes = {
      'id': 'INTEGER',
      'phase': 'TEXT',
      'counts_json': 'TEXT',
      'completed_at': 'TEXT',
    };
    if (columns.length != expectedTypes.length ||
        columns.any(
          (c) =>
              expectedTypes[c['name']] != c['type'].toString().toUpperCase() ||
              (c['name'] == 'id' ? c['pk'] != 1 : c['pk'] != 0),
        )) {
      throw StateError('Invalid legacy cleanup marker schema; data preserved.');
    }
    final rows = await primary.query(table);
    if (rows.isEmpty) return;
    if (rows.length != 1) {
      throw StateError('Invalid legacy cleanup marker; data preserved.');
    }
    final row = rows.single;
    Object? counts;
    try {
      counts = jsonDecode(row['counts_json'] as String);
    } catch (_) {
      throw StateError('Invalid legacy cleanup marker; data preserved.');
    }
    if (row['id'] != 1 ||
        counts is! Map ||
        counts.entries.any(
          (e) => e.key is! String || e.value is! int || (e.value as int) < 0,
        ) ||
        !['main_done', 'complete'].contains(row['phase']) ||
        (row['phase'] == 'complete' &&
            (row['completed_at'] is! String ||
                DateTime.tryParse(row['completed_at'] as String) == null))) {
      throw StateError('Invalid legacy cleanup marker; data preserved.');
    }
    if (row['phase'] == 'main_done') {
      throw StateError(
        'Interrupted legacy test cleanup; automatic reset is disabled. '
        'Preserve both databases and review recovery.',
      );
    }
  }

  /// This destructive historical helper is retained for synthetic fixtures.
  /// No application route or startup path calls it. Confirmation must come
  /// from the fixture owner, never from the absence of a completion marker.
  static Future<void> run({
    required Database primary,
    required Database legacyCosts,
    required String farmId,
    required bool confirmedDisposableTestData,
  }) async {
    if (!confirmedDisposableTestData) {
      throw StateError(
        'Destructive reset requires explicitly confirmed disposable test data.',
      );
    }
    // The current composition has exactly one approved local farm. Do not
    // broaden the unscoped legacy-data deletion to future multi-farm installs.
    if (farmId != 'local-farm') throw StateError('Unsupported cleanup farm.');
    await primary.execute('''CREATE TABLE IF NOT EXISTS $table (
      id INTEGER PRIMARY KEY CHECK(id=1),
      phase TEXT NOT NULL CHECK(phase IN ('main_done','complete')),
      counts_json TEXT NOT NULL,
      completed_at TEXT
    )''');
    final state = await primary.query(table, where: 'id=1');
    if (state.isNotEmpty && state.single['phase'] == 'complete') return;
    if (state.isEmpty) {
      await primary.transaction((tx) async {
        final other = await tx.query(
          'inventory_items_v2',
          columns: ['id'],
          where: 'farm_id<>?',
          whereArgs: [farmId],
          limit: 1,
        );
        if (other.isNotEmpty) {
          throw StateError('Other-farm inventory requires separate cleanup.');
        }
        // Never erase records already created under the new model.
        for (final name in [
          'production_seasons_v2',
          'production_material_costs_v2',
        ]) {
          if ((await tx.query(name, limit: 1)).isNotEmpty) {
            throw StateError(
              'V2 production already exists without a cutover marker.',
            );
          }
        }
        final counts = <String, int>{};
        final tables = (await tx.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        )).map((r) => r['name']).toSet();
        for (final name in legacyPrimaryTables) {
          if (!tables.contains(name)) continue;
          final count = await tx.rawQuery('SELECT COUNT(*) AS n FROM "$name"');
          counts[name] = (count.single['n']! as num).toInt();
          await tx.delete(name);
        }
        if (tables.contains('inventory_transfers_v1') &&
            (await tx.query(
              'inventory_transfers_v1',
              where: 'farm_id=?',
              whereArgs: [farmId],
              limit: 1,
            )).isNotEmpty)
          throw StateError(
            'Warehouse transfers already exist without a cutover marker.',
          );
        if (tables.contains('inventory_warehouse_stock_v1'))
          await tx.delete(
            'inventory_warehouse_stock_v1',
            where: 'farm_id=?',
            whereArgs: [farmId],
          );
        counts['inventory_movements_v2'] = await tx.delete(
          'inventory_movements_v2',
          where: 'farm_id=?',
          whereArgs: [farmId],
        );
        final itemColumns = await tx.rawQuery(
          'PRAGMA table_info(inventory_items_v2)',
        );
        await tx.update(
          'inventory_items_v2',
          {
            'stock': 0,
            if (itemColumns.any((c) => c['name'] == 'stock_units'))
              'stock_units': 0,
          },
          where: 'farm_id=?',
          whereArgs: [farmId],
        );
        await tx.delete(
          'monthly_document_sequences',
          where: "organization_id=? AND kind IN ('NHAP','XUAT')",
          whereArgs: [farmId],
        );
        await tx.insert(table, {
          'id': 1,
          'phase': 'main_done',
          'counts_json': jsonEncode(counts),
        });
      });
    }
    // Separate legacy database: retry this idempotent clear after a crash.
    // Bootstrap awaits complete before exposing the new production screens.
    final tables = await legacyCosts.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='production_costs'",
    );
    if (tables.isNotEmpty) {
      await legacyCosts.transaction((tx) => tx.delete('production_costs'));
    }
    await primary.update(table, {
      'phase': 'complete',
      'completed_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'id=1');
  }
}
