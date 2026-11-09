import 'sqlite_warehouse_stock.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/entities/exact_decimal.dart';
import '../../domain/entities/production_plan.dart';
import 'sqlite_production_planning_repository.dart';

/// Read-only checks used on disposable restore databases; never changes live data.
abstract final class ProductionInventoryIntegrity {
  static Future<void> validate(DatabaseExecutor db) async {
    await SqliteWarehouseStock.validate(db);
    final plans = await db.query('production_plans_v1');
    final byPlan = {for (final r in plans) r['id']: r};
    for (final r in plans) {
      final p = SqliteProductionPlanningRepository.planFromRow(r);
      p.validate();
      final valid = await db.rawQuery(
        'SELECT s.id FROM production_seasons_v2 s JOIN land_parcels l '
        'ON l.id=s.parcel_id AND l.farm_id=s.farm_id WHERE s.id=? AND s.farm_id=? AND s.parcel_id=? AND s.starts_on<=?',
        [p.seasonId, p.farmId, p.parcelId, p.startsOn],
      );
      if (valid.length != 1) throw StateError('Invalid plan destination.');
      final code = RegExp(r'^KH-(\d{6})-(\d{3,})$').firstMatch(p.code ?? '');
      if (code == null ||
          code.group(1) != p.startsOn.substring(0, 7).replaceAll('-', '')) {
        throw StateError('Invalid plan code.');
      }
      final counters = await db.query(
        'production_plan_sequences_v1',
        where: 'farm_id=? AND month=?',
        whereArgs: [p.farmId, code.group(1)],
      );
      if (counters.length != 1 ||
          (counters.single['last_value']! as int) < int.parse(code.group(2)!)) {
        throw StateError('Missing plan counter.');
      }
    }
    for (final t in await db.query('production_plan_tasks_v1')) {
      final p = byPlan[t['plan_id']];
      final core = await db.query(
        'farm_tasks_v2',
        where: 'id=?',
        whereArgs: [t['id']],
      );
      if (p == null ||
          core.length != 1 ||
          p['farm_id'] != t['farm_id'] ||
          core.single['farm_id'] != t['farm_id'] ||
          core.single['parcel_id'] != p['parcel_id']) {
        throw StateError('Invalid shared plan task.');
      }
      final f = core.single;
      ProductionPlanTask(
        id: t['id']! as String,
        farmId: t['farm_id']! as String,
        planId: t['plan_id']! as String,
        title: f['title']! as String,
        stage: t['stage']! as String,
        quantity: t['quantity']! as String,
        unit: t['unit']! as String,
        revision: t['revision']! as int,
      ).validate();
    }
    final stock = <String, int>{};
    final movements = await db.query('inventory_movements_v2');
    final byMovement = {for (final m in movements) m['id']: m};
    for (final m in movements) {
      final q = m['quantity_units'];
      if (q is! int ||
          q <= 0 ||
          q != ExactDecimal.quantityUnits(m['quantity']! as num)) {
        throw StateError('Invalid movement precision.');
      }
      final item = m['item_id']! as String;
      stock[item] = (stock[item] ?? 0) + (m['kind'] == 'receipt' ? q : -q);
      if (m['unit_price_text'] != null) {
        ExactDecimal.validatePrice(
          m['unit_price_text']! as String,
          m['currency']! as String,
        );
        final amount =
            ExactDecimal.parse(m['quantity'].toString()) *
            ExactDecimal.parse(m['unit_price_text']! as String);
        if (amount.toString() != m['amount_text'] ||
            (m['priced_by'] as String?)?.isNotEmpty != true) {
          throw StateError('Invalid price snapshot.');
        }
        if (amount.coefficient == BigInt.zero &&
            m['zero_price_confirmed'] != 1) {
          throw StateError('Unconfirmed zero price.');
        }
      } else if (m['kind'] == 'issue' && m['transfer_id'] == null) {
        throw StateError('Unpriced historical issue is incompatible.');
      }
    }
    for (final i in await db.query('inventory_items_v2')) {
      if (i['stock_units'] is! int ||
          i['stock_units'] != (stock[i['id']] ?? 0) ||
          i['stock_units'] != ExactDecimal.quantityUnits(i['stock']! as num)) {
        throw StateError('Stock does not reconcile.');
      }
    }
    for (final c in await db.query('production_material_costs_v2')) {
      final p = byPlan[c['plan_id']];
      final m = byMovement[c['movement_id']];
      if (p == null ||
          m == null ||
          p['farm_id'] != c['farm_id'] ||
          p['parcel_id'] != c['parcel_id'] ||
          p['season_id'] != c['season_id'] ||
          p['currency'] != c['currency'] ||
          m['kind'] != 'issue') {
        throw StateError('Invalid production cost destination.');
      }
      for (final key in [
        'quantity_units',
        'unit_price_text',
        'amount_text',
        'currency',
        'priced_by',
        'plan_id',
        'item_id',
        'farm_id',
        'occurred_at',
        'zero_price_confirmed',
      ]) {
        if (c[key] != m[key]) {
          throw StateError('Cost differs from source movement.');
        }
      }
      final amount =
          ExactDecimal.parse(c['quantity'].toString()) *
          ExactDecimal.parse(c['unit_price_text']! as String);
      if (amount.toString() != c['amount_text'] ||
          c['quantity_units'] !=
              ExactDecimal.quantityUnits(c['quantity']! as num)) {
        throw StateError('Cost arithmetic mismatch.');
      }
    }
    for (final m in movements.where((m) => m['plan_id'] != null)) {
      final costs = await db.query(
        'production_material_costs_v2',
        where: 'movement_id=?',
        whereArgs: [m['id']],
      );
      if (costs.length != 1) {
        throw StateError('Production movement requires its cost.');
      }
    }
  }
}
