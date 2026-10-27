import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

/// All modules share these SQLite guards. No UI-only lock or bypass flag.
abstract final class PeriodLock {
  static const states = 'accounting_periods_v1';
  static const events = 'accounting_period_events_v1';
  static const tables = {states, events};
  static String end(String month) {
    if (!RegExp(r'^[1-9][0-9]{3}-(0[1-9]|1[0-2])$').hasMatch(month)) {
      throw const FormatException('Invalid accounting month.');
    }
    return DateTime.utc(
      int.parse(month.substring(0, 4)),
      int.parse(month.substring(5)) + 1,
      1,
    ).subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
  }

  static Object? canonical(Object? value) {
    if (value is Map) {
      return {
        for (final k in value.keys.map((v) => v.toString()).toList()..sort())
          k: canonical(value[k]),
      };
    }
    if (value is List) {
      return value.map(canonical).toList();
    }
    return value;
  }

  static String encode(Object? value) => jsonEncode(canonical(value));
  static String digest(Object? value) =>
      sha256.convert(utf8.encode(encode(value))).toString();
  static Future<bool> enabled(DatabaseExecutor db) async => (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
    [states],
  )).isNotEmpty;
  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS $states(
      farm_id TEXT NOT NULL,period TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),
      status TEXT NOT NULL CHECK(status IN ('closed','open')),event_id TEXT NOT NULL,
      PRIMARY KEY(farm_id,period))''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $events(
      id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,period TEXT NOT NULL,revision INTEGER NOT NULL,
      action TEXT NOT NULL CHECK(action IN ('close','reopen')),reason TEXT NOT NULL,
      actor_id TEXT NOT NULL,occurred_at TEXT NOT NULL,snapshot TEXT NOT NULL,digest TEXT NOT NULL,
      previous_digest TEXT NOT NULL,event_digest TEXT NOT NULL,UNIQUE(farm_id,period,revision))''',
    );
    await install(db);
  }

  // Date expressions always come from persisted source rows, never caller dates.
  // Child costs/links inherit the source date. Current payments on old debts are
  // dated independently and remain allowed. Cached stock is maintained atomically
  // with the guarded movements; consuming an old harvest lot is also allowed.
  static const dated = <String, String>{
    'finance_documents_v2': '{r}.occurred_at',
    'inventory_movements_v2': "date({r}.occurred_at,'+7 hours')",
    'inventory_transfers_v1': "date({r}.occurred_at,'+7 hours')",
    'production_material_costs_v2': "date({r}.occurred_at,'+7 hours')",
    'personnel_entries_v1': '{r}.business_day',
    'personnel_pay_rates_v1': '{r}.effective_on',
    'personnel_payrolls_v1': "{r}.period||'-01'",
    'personnel_payments_v1': '{r}.business_day',
    'personnel_payroll_adjustments_v1': '{r}.day',
    'personnel_payroll_refunds_v1': '{r}.day',
    'machine_rates_v1': '{r}.effective_on',
    'machine_runs_v1': '{r}.day',
    'machine_expenses_v1': '{r}.day',
    'trade_documents_v1': '{r}.day',
    'trade_settlements_v1': '{r}.day',
    'trade_reversals_v1': '{r}.day',
    'integration_salary_reversals_v1': '{r}.day',
    'production_labor_costs_v1':
        '(SELECT business_day FROM personnel_entries_v1 WHERE id={r}.entry_id)',
    'personnel_payroll_lines_v1':
        "(SELECT period||'-01' FROM personnel_payrolls_v1 WHERE id={r}.payroll_id)",
    'personnel_payroll_adjustment_costs_v1':
        '(SELECT day FROM personnel_payroll_adjustments_v1 WHERE id={r}.adjustment_id)',
    'machine_costs_v1':
        '(SELECT day FROM machine_runs_v1 WHERE id={r}.source_id)',
    'trade_stock_links_v1':
        "(SELECT date(occurred_at,'+7 hours') FROM inventory_movements_v2 WHERE id={r}.movement_id)",
    'integration_cash_links_v1':
        '(SELECT business_day FROM personnel_payments_v1 WHERE id={r}.source_id)',
    'integration_machine_links_v1':
        '(SELECT day FROM machine_expenses_v1 WHERE id={r}.expense_id)',
    'integration_fuel_issues_v1':
        '(SELECT day FROM machine_expenses_v1 WHERE id={r}.expense_id)',
  };
  static String farm(String table, String row) =>
      table == 'finance_documents_v2'
      ? '$row.organization_id'
      : table == 'personnel_payroll_lines_v1'
      ? '(SELECT farm_id FROM personnel_payrolls_v1 WHERE id=$row.payroll_id)'
      : '$row.farm_id';
  static String condition(String table, String row, String date) =>
      "EXISTS(SELECT 1 FROM $states p WHERE p.farm_id=${farm(table, row)} AND p.status='closed' AND substr($date,1,7)<=p.period)";
  static Future<void> install(DatabaseExecutor db) async {
    if (!await enabled(db)) {
      return;
    }
    final installed = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((r) => r['name']).toSet();
    for (final entry in dated.entries) {
      if (!installed.contains(entry.key)) {
        continue;
      }
      for (final action in ['INSERT', 'UPDATE', 'DELETE']) {
        final refs = action == 'UPDATE'
            ? ['OLD', 'NEW']
            : [action == 'DELETE' ? 'OLD' : 'NEW'];
        final checks = refs
            .map(
              (r) => condition(entry.key, r, entry.value.replaceAll('{r}', r)),
            )
            .join(' OR ');
        await db.execute(
          'CREATE TRIGGER IF NOT EXISTS period_guard_${entry.key}_${action.toLowerCase()} BEFORE $action ON ${entry.key} WHEN $checks BEGIN SELECT RAISE(ABORT,\'ACCOUNTING_PERIOD_CLOSED\'); END',
        );
      }
    }
    if (installed.contains('trade_lots_v1')) {
      final cols = (await db.rawQuery(
        'PRAGMA table_info(trade_lots_v1)',
      )).map((r) => r['name'] as String).where((c) => c != 'stock_units');
      final changed = cols.map((c) => 'OLD.$c IS NOT NEW.$c').join(' OR ');
      for (final action in ['INSERT', 'UPDATE', 'DELETE']) {
        final refs = action == 'UPDATE'
            ? ['OLD', 'NEW']
            : [action == 'DELETE' ? 'OLD' : 'NEW'];
        final locked = refs
            .map((r) => condition('trade_lots_v1', r, '$r.day'))
            .join(' OR ');
        final checks = action == 'UPDATE' ? '($locked) AND ($changed)' : locked;
        await db.execute(
          "CREATE TRIGGER IF NOT EXISTS period_guard_lot_${action.toLowerCase()} BEFORE $action ON trade_lots_v1 WHEN $checks BEGIN SELECT RAISE(ABORT,'ACCOUNTING_PERIOD_CLOSED'); END",
        );
      }
    }
    if (installed.contains('integration_report_metadata_v1')) {
      for (final action in ['INSERT', 'UPDATE', 'DELETE']) {
        final refs = action == 'UPDATE'
            ? ['OLD', 'NEW']
            : [action == 'DELETE' ? 'OLD' : 'NEW'];
        final checks = refs
            .map(
              (r) =>
                  "EXISTS(SELECT 1 FROM $states p WHERE p.farm_id=$r.farm_id AND p.status='closed' AND (CASE $r.kind WHEN 'capital' THEN (SELECT substr(occurred_at,1,7) FROM finance_documents_v2 WHERE id=$r.entity_id) WHEN 'run' THEN (SELECT substr(day,1,7) FROM machine_runs_v1 WHERE id=$r.entity_id) WHEN 'maintenance' THEN (SELECT substr(day,1,7) FROM machine_expenses_v1 WHERE id=$r.entity_id) WHEN 'harvest' THEN (SELECT substr(day,1,7) FROM trade_documents_v1 WHERE id=$r.entity_id) WHEN 'payroll' THEN (SELECT period FROM personnel_payrolls_v1 WHERE id=$r.entity_id) ELSE '0000-00' END)<=p.period)",
            )
            .join(' OR ');
        await db.execute(
          "CREATE TRIGGER IF NOT EXISTS period_guard_metadata_${action.toLowerCase()} BEFORE $action ON integration_report_metadata_v1 WHEN $checks BEGIN SELECT RAISE(ABORT,'ACCOUNTING_PERIOD_CLOSED'); END",
        );
      }
    }
    for (final action in ['UPDATE', 'DELETE']) {
      await db.execute(
        "CREATE TRIGGER IF NOT EXISTS period_guard_event_${action.toLowerCase()} BEFORE $action ON $events BEGIN SELECT RAISE(ABORT,'IMMUTABLE_PERIOD_HISTORY'); END",
      );
    }
  }

  /// Restore alone drops/reinstalls guards inside its existing atomic transaction.
  /// Rollback restores both the old data and original triggers.
  static Future<void> removeGuards(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND name GLOB 'period_guard_*'",
    );
    for (final r in rows) {
      final name = r['name'] as String;
      if (!RegExp(r'^period_guard_[a-z0-9_]+$').hasMatch(name)) {
        throw StateError('Invalid guard name.');
      }
      await db.execute('DROP TRIGGER "$name"');
    }
  }

  static Future<Map<String, Object?>?> state(
    DatabaseExecutor db,
    String farm,
    String period,
  ) async {
    if (!await enabled(db)) {
      return null;
    }
    final rows = await db.query(
      states,
      where: 'farm_id=? AND period=?',
      whereArgs: [farm, period],
    );
    return rows.isEmpty ? null : rows.single;
  }

  static Future<Map<String, dynamic>?> frozen(
    DatabaseExecutor db,
    String farm,
    String period,
  ) async {
    final s = await state(db, farm, period);
    if (s == null || s['status'] != 'closed') {
      return null;
    }
    final e = (await db.query(
      events,
      where: 'id=?',
      whereArgs: [s['event_id']],
    )).single;
    if (e['farm_id'] != farm ||
        e['period'] != period ||
        e['action'] != 'close' ||
        e['revision'] != s['revision']) {
      throw StateError('Invalid period identity.');
    }
    final value = Map<String, dynamic>.from(
      jsonDecode(e['snapshot'] as String) as Map,
    );
    if (digest(value) != e['digest']) {
      throw StateError('Invalid period snapshot.');
    }
    return value;
  }
}
