import 'dart:convert';
import 'package:sqflite/sqflite.dart';

/// Explicitly authorized removal of incompatible local test data for the V2
/// production cutover. A durable phase prevents clearing new stock on retry.
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

  static Future<void> run({
    required Database primary,
    required Database legacyCosts,
    required String farmId,
  }) async {
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
