import 'package:sqflite/sqflite.dart';
import '../periods/period_lock.dart';

/// Metadata over native sources. No amounts or parallel financial journal.
abstract final class SourceGovernance {
  static const versions = 'production_source_versions_v2';
  static const audit = 'production_source_audit_v2';
  static const tables = {versions, audit};
  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS $versions(
      farm_id TEXT NOT NULL,source_type TEXT NOT NULL,source_id TEXT NOT NULL,
      revision INTEGER NOT NULL CHECK(revision>0),day TEXT NOT NULL,
      payload_digest TEXT NOT NULL,creator TEXT NOT NULL,created_at TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('draft','approved')),approver TEXT,approved_at TEXT,
      CHECK((status='draft' AND approver IS NULL AND approved_at IS NULL) OR
        (status='approved' AND approver IS NOT NULL AND approved_at IS NOT NULL)),
      PRIMARY KEY(farm_id,source_type,source_id))''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $audit(id INTEGER PRIMARY KEY,
      farm_id TEXT NOT NULL,source_type TEXT NOT NULL,source_id TEXT NOT NULL,
      revision INTEGER NOT NULL,action TEXT NOT NULL,actor_id TEXT NOT NULL,
      occurred_at TEXT NOT NULL,payload_digest TEXT NOT NULL,
      UNIQUE(farm_id,source_type,source_id,revision))''',
    );
    for (final op in ['UPDATE', 'DELETE']) {
      await db.execute(
        "CREATE TRIGGER IF NOT EXISTS production_source_audit_${op.toLowerCase()} BEFORE $op ON $audit BEGIN SELECT RAISE(ABORT,'IMMUTABLE_SOURCE_AUDIT'); END",
      );
    }
    await db.execute(
      "CREATE TRIGGER IF NOT EXISTS production_source_no_delete BEFORE DELETE ON $versions BEGIN SELECT RAISE(ABORT,'IMMUTABLE_SOURCE_IDENTITY'); END",
    );
    await db.execute(
      '''CREATE TRIGGER IF NOT EXISTS production_source_approval_transition
      BEFORE UPDATE ON $versions WHEN OLD.status<>'draft' OR NEW.status<>'approved'
        OR NEW.revision<>OLD.revision+1 OR NEW.farm_id<>OLD.farm_id
        OR NEW.source_type<>OLD.source_type OR NEW.source_id<>OLD.source_id
        OR NEW.payload_digest<>OLD.payload_digest OR NEW.creator<>OLD.creator
        OR NEW.created_at<>OLD.created_at OR NEW.day<>OLD.day
      BEGIN SELECT RAISE(ABORT,'INVALID_SOURCE_TRANSITION'); END''',
    );
  }

  static String digest(Object? payload) => PeriodLock.digest(payload);
  static Map<String, Object?> pick(
    Map<String, Object?> row,
    List<String> keys,
  ) => {for (final k in keys) k: row[k]};
  static Object material(Map<String, Object?> m, Map<String, Object?> c) => {
    'movement': pick(m, [
      'id',
      'farm_id',
      'code',
      'item_id',
      'warehouse_id',
      'plan_id',
      'kind',
      'quantity_units',
      'unit_price_text',
      'amount_text',
      'currency',
      'priced_by',
      'zero_price_confirmed',
      'occurred_at',
    ]),
    'cost': pick(c, [
      'movement_id',
      'farm_id',
      'parcel_id',
      'season_id',
      'item_id',
      'plan_id',
      'quantity_units',
      'unit_price_text',
      'amount_text',
      'currency',
      'priced_by',
      'zero_price_confirmed',
      'occurred_at',
    ]),
  };
  static Object payroll(
    Map<String, Object?> r,
    List<Map<String, Object?>> lines,
  ) => {
    'payroll': pick(r, [
      'id',
      'farm_id',
      'worker_id',
      'period',
      'currency',
      'code',
      'regular',
      'overtime',
      'piece',
      'allowance',
      'bonus',
      'advance',
      'deduction',
      'net',
      'adjustment_plan_id',
      'extra_cost_day',
    ]),
    'lines': (lines.map((r) => pick(r, ['entry_id', 'amount'])).toList()
      ..sort((a, b) => '${a['entry_id']}'.compareTo('${b['entry_id']}'))),
  };
  static Object correction(
    Map<String, Object?> r,
    List<Map<String, Object?>> costs,
  ) => {
    'adjustment': pick(r, [
      'id',
      'farm_id',
      'payroll_id',
      'currency',
      'day',
      'delta',
      'kind',
      'reason',
      'expected_revision',
      'before_net',
    ]),
    'costs': (costs.map((r) => pick(r, ['plan_id', 'amount'])).toList()
      ..sort((a, b) => '${a['plan_id']}'.compareTo('${b['plan_id']}'))),
  };
  static Object expenseSource(Map<String, Object?> r) => pick(r, [
    'id',
    'farm_id',
    'kind',
    'code',
    'day',
    'party_id',
    'plan_id',
    'currency',
    'total',
    'reference',
    'body',
  ]);
  static Object expenseReversal(Map<String, Object?> row) => {
    'document': expenseSource(row),
    'void_day': row['void_day'],
    'revision': row['revision'],
    'status': row['status'],
  };
  static Object policyPayload(Map<String, Object?> r) => pick(r, [
    'id',
    'farm_id',
    'source_id',
    'day',
    'currency',
    'driver',
    'base_units',
    'money_scale',
    'weights_json',
    'source_digest',
  ]);
  static Future<Object> nativePayload(
    DatabaseExecutor db,
    String type,
    String id,
  ) async {
    Future<Map<String, Object?>> one(String table, String key) async {
      final rows = await db.query(table, where: '$key=?', whereArgs: [id]);
      if (rows.length != 1) throw StateError('Native source required.');
      return rows.single;
    }

    if (type == 'tradeExpense' || type == 'expenseReversal') {
      final row = await one('trade_documents_v1', 'id');
      return type == 'tradeExpense' ? expenseSource(row) : expenseReversal(row);
    }

    if (type == 'material') {
      return material(
        await one('inventory_movements_v2', 'id'),
        await one('production_material_costs_v2', 'movement_id'),
      );
    }
    if (type == 'payrollExtra') {
      return payroll(
        await one('personnel_payrolls_v1', 'id'),
        await db.query(
          'personnel_payroll_lines_v1',
          where: 'payroll_id=?',
          whereArgs: [id],
        ),
      );
    }
    if (type == 'payrollCorrection') {
      return correction(
        await one('personnel_payroll_adjustments_v1', 'id'),
        await db.query(
          'personnel_payroll_adjustment_costs_v1',
          where: 'adjustment_id=?',
          whereArgs: [id],
        ),
      );
    }
    throw StateError('Unsupported native source.');
  }

  static Future<Map<String, Object?>?> get(
    DatabaseExecutor db,
    String farm,
    String type,
    String id,
  ) async {
    final rows = await db.query(
      versions,
      where: 'farm_id=? AND source_type=? AND source_id=?',
      whereArgs: [farm, type, id],
    );
    return rows.singleOrNull;
  }

  static Future<void> register(
    DatabaseExecutor db, {
    required String farm,
    required String type,
    required String id,
    required String day,
    required String actor,
    required Object payload,
  }) async {
    if (actor.trim().isEmpty) throw StateError('Creation actor required.');
    PeriodLock.end(day.substring(0, 7));
    final hash = digest(payload), old = await get(db, farm, type, id);
    if (old != null) {
      if (old['payload_digest'] != hash) {
        throw StateError('Source payload identity conflict.');
      }
      return;
    }
    final time = DateTime.now().toUtc().toIso8601String();
    await db.insert(versions, {
      'farm_id': farm,
      'source_type': type,
      'source_id': id,
      'revision': 1,
      'day': day,
      'payload_digest': hash,
      'creator': actor,
      'created_at': time,
      'status': 'draft',
    });
    await db.insert(audit, {
      'farm_id': farm,
      'source_type': type,
      'source_id': id,
      'revision': 1,
      'action': 'create',
      'actor_id': actor,
      'occurred_at': time,
      'payload_digest': hash,
    });
  }

  static Future<void> approve(
    DatabaseExecutor db, {
    required String farm,
    required String type,
    required String id,
    required int expectedRevision,
    required String actor,
    required Object payload,
  }) async {
    if (actor.trim().isEmpty) throw StateError('Approval actor required.');
    final old = await get(db, farm, type, id);
    if (old == null || old['payload_digest'] != digest(payload)) {
      throw StateError('Source changed or unversioned.');
    }
    if (old['status'] == 'approved' &&
        old['revision'] == expectedRevision + 1) {
      return;
    }
    if (old['revision'] != expectedRevision || old['status'] != 'draft') {
      throw StateError('Stale source approval.');
    }
    final time = DateTime.now().toUtc().toIso8601String();
    final n = await db.update(
      versions,
      {
        'status': 'approved',
        'revision': expectedRevision + 1,
        'approver': actor,
        'approved_at': time,
      },
      where:
          'farm_id=? AND source_type=? AND source_id=? AND revision=? AND status=?',
      whereArgs: [farm, type, id, expectedRevision, 'draft'],
    );
    if (n != 1) throw StateError('Approval conflict.');
    await db.insert(audit, {
      'farm_id': farm,
      'source_type': type,
      'source_id': id,
      'revision': expectedRevision + 1,
      'action': 'approve',
      'actor_id': actor,
      'occurred_at': time,
      'payload_digest': old['payload_digest'],
    });
  }

  static Future<void> validate(
    DatabaseExecutor db, {
    Future<Object> Function(Map<String, Object?>)? allocationPayload,
  }) async {
    if ((await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [versions],
    )).isEmpty) {
      return;
    }
    for (final r in await db.query(versions)) {
      final type = r['source_type'] as String;
      final payload = type == 'expenseAllocation' && allocationPayload != null
          ? await allocationPayload(r)
          : await nativePayload(db, type, r['source_id'] as String);
      final expectedRevision = r['status'] == 'approved' ? 2 : 1;
      if (r['status'] == 'approved' &&
          ((r['approver'] as String).trim().isEmpty ||
              DateTime.tryParse(r['approved_at'] as String) == null ||
              DateTime.parse(
                r['approved_at'] as String,
              ).isBefore(DateTime.parse(r['created_at'] as String)))) {
        throw StateError('Invalid approval actor or timestamp.');
      }
      if (r['revision'] != expectedRevision ||
          r['payload_digest'] != digest(payload) ||
          (r['creator'] as String).trim().isEmpty ||
          DateTime.tryParse(r['created_at'] as String) == null) {
        throw StateError('Source governance does not reconcile.');
      }
      if (payload is Map) {
        if (payload['farm_id'] != null && payload['farm_id'] != r['farm_id']) {
          throw StateError('Source farm mismatch.');
        }
        for (final value in payload.values.whereType<Map>()) {
          if (value.containsKey('farm_id') &&
              value['farm_id'] != r['farm_id']) {
            throw StateError('Source farm mismatch.');
          }
        }
      }
      final events = await db.query(
        audit,
        where: 'farm_id=? AND source_type=? AND source_id=?',
        whereArgs: [r['farm_id'], type, r['source_id']],
        orderBy: 'revision',
      );
      if (events.length != expectedRevision) {
        throw StateError('Missing source audit.');
      }
      for (var i = 0; i < events.length; i++) {
        final e = events[i];
        if (e['revision'] != i + 1 ||
            e['action'] != (i == 0 ? 'create' : 'approve') ||
            e['actor_id'] != (i == 0 ? r['creator'] : r['approver']) ||
            e['occurred_at'] != (i == 0 ? r['created_at'] : r['approved_at']) ||
            e['payload_digest'] != r['payload_digest']) {
          throw StateError('Source event mismatch.');
        }
      }
    }
    final dangling = await db.rawQuery(
      'SELECT a.id FROM $audit a LEFT JOIN $versions v ON v.farm_id=a.farm_id AND v.source_type=a.source_type AND v.source_id=a.source_id WHERE v.source_id IS NULL',
    );
    if (dangling.isNotEmpty) throw StateError('Orphan source audit.');
  }

  /// Only the confirmed atomic restore workflow calls this; rollback restores guards.
  static Future<void> removeStorageGuardsForRestore(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND (name LIKE 'production_source_%' OR name LIKE 'production_immutable_production_expense_%')",
    );
    for (final r in rows) {
      final name = r['name'] as String;
      if (!RegExp(r'^[a-z0-9_]+$').hasMatch(name)) {
        throw StateError('Invalid guard identifier.');
      }
      await db.execute('DROP TRIGGER "$name"');
    }
  }
}
