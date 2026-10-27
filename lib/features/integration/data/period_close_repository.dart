import '../../trade/domain/trade.dart' show TradeLine;
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/periods/period_lock.dart';
import '../domain/period_close.dart';
import '../domain/integration_snapshot.dart';
import 'integration_repository.dart';
import 'integration_integrity.dart';
import '../../personnel/data/personnel_integrity.dart';
import '../../machines/data/machine_integrity.dart';
import '../../trade/data/trade_integrity.dart';
import '../../inventory/data/local/production_inventory_integrity.dart';

class PeriodCloseRepository implements PeriodCloseStore {
  const PeriodCloseRepository(this.database, {this.today});
  final Database database;

  /// Injected only in tests; production uses business day UTC+7.
  final String Function()? today;
  String get day =>
      today?.call() ??
      DateTime.now()
          .toUtc()
          .add(const Duration(hours: 7))
          .toIso8601String()
          .substring(0, 10);
  void identity(String farm, String actor, String reason) {
    if (farm.trim().isEmpty ||
        actor.trim().isEmpty ||
        reason.trim().isEmpty ||
        reason.length > 2000) {
      throw const FormatException(
        'Period action requires an actor and reason.',
      );
    }
  }

  Future<PeriodReview> _review(
    DatabaseExecutor tx,
    String farm,
    String period,
  ) async {
    final end = PeriodLock.end(period);
    if (farm.trim().isEmpty) {
      throw const FormatException('Farm required.');
    }
    final s = await PeriodLock.state(tx, farm, period);
    final history = await tx.query(
      PeriodLock.events,
      where: 'farm_id=? AND period=?',
      whereArgs: [farm, period],
      orderBy: 'revision',
    );
    final issues = <String>[];
    if (end.compareTo(day) >= 0) {
      issues.add('monthNotEnded');
    }
    final later = await tx.query(
      PeriodLock.states,
      where: "farm_id=? AND period>? AND status='closed'",
      whereArgs: [farm, period],
    );
    if (later.isNotEmpty) {
      issues.add('laterPeriodClosed');
    }
    // Reconciliation checks the complete ledger: a broken dependency anywhere
    // cannot become a certified closing balance. No writes or auto corrections.
    for (final c in <String, Future<void> Function(DatabaseExecutor)>{
      'inventoryIntegrity': ProductionInventoryIntegrity.validate,
      'personnelIntegrity': PersonnelIntegrity.validate,
      'machineIntegrity': MachineIntegrity.validate,
      'tradeIntegrity': TradeIntegrity.validate,
      'integrationIntegrity': IntegrationIntegrity.validate,
      'periodIntegrity': validate,
    }.entries) {
      try {
        await c.value(tx);
      } catch (_) {
        issues.add(c.key);
      }
    }
    final data = await IntegrationRepository.liveSnapshot(tx, farm, period);
    bool before(Map<String, Object?> r, String key) =>
        r[key].toString().substring(0, 7).compareTo(period) <= 0;
    for (final config in const [
      ['personnel_entries_v1', 'business_day'],
      ['personnel_payrolls_v1', 'period'],
      ['machine_runs_v1', 'day'],
      ['machine_expenses_v1', 'day'],
      ['trade_documents_v1', 'day'],
      ['personnel_payroll_adjustments_v1', 'day'],
    ]) {
      final count = data
          .rows(config[0])
          .where((r) => r['status'] == 'draft' && before(r, config[1]))
          .length;
      if (count > 0) {
        issues.add('draft:${config[0]}:$count');
      }
    }
    final cashLinks = data
        .rows('integration_cash_links_v1')
        .map((r) => r['source_id'])
        .toSet();
    final pending = data
        .rows('personnel_payments_v1')
        .where((r) => before(r, 'business_day') && !cashLinks.contains(r['id']))
        .length;
    if (pending > 0) {
      issues.add('unlinkedSalary:$pending');
    }
    final source = await asOf(tx, farm, period);
    final classified = {
      ...source
          .rows('integration_machine_links_v1')
          .map((r) => r['expense_id']),
      ...source.rows('integration_fuel_issues_v1').map((r) => r['expense_id']),
    };
    final machinePending = source
        .rows('machine_expenses_v1')
        .where(
          (r) => r['status'] == 'approved' && !classified.contains(r['id']),
        )
        .length;
    if (machinePending > 0) {
      issues.add('unclassifiedMachine:$machinePending');
    }
    if (source
        .rows('inventory_warehouse_stock_v1')
        .any((r) => (r['stock_units'] as int) < 0)) {
      issues.add('historicalStockNegative');
    }
    // Do not net VND against LAK, or one employee's receivable against another.
    // Debt may legitimately remain outstanding; it carries forward unchanged.
    final payload = {'farm': farm, 'period': period, 'tables': data.tables};
    final token = PeriodLock.digest({
      'payload': payload,
      'revision': s?['revision'] ?? 0,
      'status': s?['status'] ?? 'open',
    });
    return PeriodReview(
      period: period,
      revision: (s?['revision'] as int?) ?? 0,
      closed: s?['status'] == 'closed',
      token: token,
      issues: issues,
      history: history,
    );
  }

  /// Closing balances use business dates through month end, not the export day.
  /// Later reversals of trade documents are undone in this projection only.
  /// Operational tables stay untouched; master labels are snapshotted at approval.
  static Future<IntegrationSnapshot> asOf(
    DatabaseExecutor tx,
    String farm,
    String period,
  ) async {
    final live = await IntegrationRepository.liveSnapshot(tx, farm, period);
    final data = <String, List<Map<String, Object?>>>{
      for (final e in live.tables.entries)
        e.key: e.value.map((r) => Map<String, Object?>.from(r)).toList(),
    };
    final available = (await tx.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((r) => r['name']).toSet();
    for (final entry in PeriodLock.dated.entries) {
      if (!available.contains(entry.key)) {
        continue;
      }
      if (!data.containsKey(entry.key)) {
        continue;
      }
      final date = entry.value.replaceAll('{r}', 'source');
      final where =
          '${PeriodLock.farm(entry.key, 'source')}=? AND substr($date,1,7)<=?';
      data[entry.key] = (await tx.rawQuery(
        'SELECT source.* FROM ${entry.key} source WHERE $where',
        [farm, period],
      )).map((r) => Map<String, Object?>.from(r)).toList();
    }
    for (final d in data['trade_documents_v1'] ?? <Map<String, Object?>>[]) {
      if (d['status'] == 'void' &&
          (d['void_day'] as String).substring(0, 7).compareTo(period) > 0) {
        d['status'] = 'posted';
        d['void_day'] = null;
      }
    }
    final documents = {
      for (final r in data['trade_documents_v1'] ?? <Map<String, Object?>>[])
        r['id']: r,
    };
    data['trade_lots_v1'] = [
      for (final r in data['trade_lots_v1'] ?? <Map<String, Object?>>[])
        if (documents.containsKey(r['harvest_id'])) r,
    ];
    // These cached balances must not import later-month movements into closing.
    final moves = data['inventory_movements_v2'] ?? <Map<String, Object?>>[];
    for (final r
        in data['inventory_warehouse_stock_v1'] ?? <Map<String, Object?>>[]) {
      r['stock_units'] = moves
          .where(
            (m) =>
                m['warehouse_id'] == r['warehouse_id'] &&
                m['item_id'] == r['item_id'],
          )
          .fold<int>(
            0,
            (n, m) =>
                n +
                (m['kind'] == 'receipt' ? 1 : -1) *
                    (m['quantity_units'] as int),
          );
    }
    for (final item in data['inventory_items_v2'] ?? <Map<String, Object?>>[]) {
      final units = moves
          .where((m) => m['item_id'] == item['id'])
          .fold<int>(
            0,
            (n, m) =>
                n +
                (m['kind'] == 'receipt' ? 1 : -1) *
                    (m['quantity_units'] as int),
          );
      item['stock_units'] = units;
      item['stock'] = units / 1000000;
    }
    for (final lot in data['trade_lots_v1'] ?? <Map<String, Object?>>[]) {
      var sold = 0;
      for (final doc in documents.values.where(
        (d) => d['kind'] == 'sale' && d['status'] == 'posted',
      )) {
        final body = IntegrationSnapshot.json(doc['body']);
        for (final line in body['lines'] as List) {
          final l = TradeLine.fromJson(Map<String, dynamic>.from(line as Map));
          if (l.ref == lot['id']) {
            sold += l.units;
          }
        }
      }
      lot['stock_units'] = documents[lot['harvest_id']]?['status'] == 'void'
          ? 0
          : (lot['original_units'] as int) - sold;
    }
    for (final list in data.values) {
      list.sort((a, b) => PeriodLock.encode(a).compareTo(PeriodLock.encode(b)));
    }
    return IntegrationSnapshot(farm: farm, period: period, tables: data);
  }

  @override
  Future<PeriodReview> review(String farm, String period) =>
      database.transaction((tx) => _review(tx, farm, period));
  @override
  Future<void> close(
    String farm,
    String period,
    String token,
    int revision,
    String reason,
    String actor,
    void Function() authorize,
  ) => database.transaction((tx) async {
    identity(farm, actor, reason);
    authorize();
    final current = await _review(tx, farm, period);
    if (current.closed ||
        current.revision != revision ||
        current.token != token) {
      throw StateError('STALE_PERIOD_REVIEW');
    }
    if (current.issues.isNotEmpty) {
      throw StateError('PERIOD_RECONCILIATION_REQUIRED');
    }
    final data = await asOf(tx, farm, period);
    await _event(tx, farm, period, revision, 'close', reason, actor, {
      'farm': farm,
      'period': period,
      'tables': data.tables,
    });
    authorize();
  });
  @override
  Future<void> reopen(
    String farm,
    String period,
    int revision,
    String reason,
    String actor,
    void Function() authorize,
  ) => database.transaction((tx) async {
    identity(farm, actor, reason);
    PeriodLock.end(period);
    authorize();
    final current = await PeriodLock.state(tx, farm, period);
    if (current == null ||
        current['status'] != 'closed' ||
        current['revision'] != revision) {
      throw StateError('STALE_PERIOD_REVIEW');
    }
    final later = await tx.query(
      PeriodLock.states,
      where: "farm_id=? AND period>? AND status='closed'",
      whereArgs: [farm, period],
    );
    if (later.isNotEmpty) {
      throw StateError('LATER_PERIOD_CLOSED');
    }
    await _event(tx, farm, period, revision, 'reopen', reason, actor, {});
    authorize();
  });
  Future<void> _event(
    Transaction tx,
    String farm,
    String period,
    int revision,
    String action,
    String reason,
    String actor,
    Map<String, Object?> snapshot,
  ) async {
    final prior = await tx.query(
      PeriodLock.events,
      where: 'farm_id=? AND period=? AND revision=?',
      whereArgs: [farm, period, revision],
    );
    final id = 'period:$farm:$period:${revision + 1}';
    final event = <String, Object?>{
      'id': id,
      'farm_id': farm,
      'period': period,
      'revision': revision + 1,
      'action': action,
      'reason': reason.trim(),
      'actor_id': actor,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'snapshot': PeriodLock.encode(snapshot),
      'digest': PeriodLock.digest(snapshot),
      'previous_digest': prior.isEmpty ? '' : _eventDigest(prior.single),
    };
    event['event_digest'] = _eventDigest(event);
    await tx.insert(PeriodLock.events, event);
    if (revision == 0) {
      await tx.insert(PeriodLock.states, {
        'farm_id': farm,
        'period': period,
        'revision': 1,
        'status': 'closed',
        'event_id': id,
      });
    } else {
      final count = await tx.update(
        PeriodLock.states,
        {
          'revision': revision + 1,
          'status': action == 'close' ? 'closed' : 'open',
          'event_id': id,
        },
        where: 'farm_id=? AND period=? AND revision=?',
        whereArgs: [farm, period, revision],
      );
      if (count != 1) {
        throw StateError('STALE_PERIOD_REVIEW');
      }
    }
  }

  static String _eventDigest(Map<String, Object?> e) => PeriodLock.digest({
    for (final entry in e.entries)
      if (entry.key != 'event_digest') entry.key: entry.value,
  });

  /// Backup preflight checks append-only history and the exact frozen sources.
  static Future<void> validate(DatabaseExecutor db) async {
    final available = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('accounting_periods_v1','accounting_period_events_v1')",
    )).map((r) => r['name']).toSet();
    if (available.isEmpty) {
      return;
    }
    if (!available.containsAll(PeriodLock.tables)) {
      throw StateError('Partial period history.');
    }
    final rows = await db.query(
      PeriodLock.events,
      orderBy: 'farm_id,period,revision',
    );
    final groups = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      groups.putIfAbsent('${r['farm_id']}|${r['period']}', () => []).add(r);
    }
    final states = await db.query(PeriodLock.states);
    if (states.length != groups.length) {
      throw StateError('Invalid period history.');
    }
    for (final s in states) {
      final period = s['period'] as String;
      PeriodLock.end(period);
      final chain = groups['${s['farm_id']}|$period'];
      if (chain == null || chain.isEmpty) {
        throw StateError('Missing period history.');
      }
      Map<String, Object?>? previous;
      for (var i = 0; i < chain.length; i++) {
        final e = chain[i];
        final action = i.isEven ? 'close' : 'reopen';
        if (e['event_digest'] != _eventDigest(e) ||
            e['revision'] != i + 1 ||
            e['action'] != action ||
            e['id'] != 'period:${s['farm_id']}:$period:${i + 1}' ||
            (e['reason'] as String).trim().isEmpty ||
            (e['actor_id'] as String).trim().isEmpty ||
            e['previous_digest'] !=
                (previous == null ? '' : _eventDigest(previous))) {
          throw StateError('Broken period event chain.');
        }
        DateTime.parse(e['occurred_at'] as String);
        final snap = Map<String, dynamic>.from(
          jsonDecode(e['snapshot'] as String) as Map,
        );
        if (PeriodLock.digest(snap) != e['digest']) {
          throw StateError('Broken closing snapshot.');
        }
        if (action == 'close') {
          if (snap['farm'] != s['farm_id'] ||
              snap['period'] != period ||
              snap['tables'] is! Map) {
            throw StateError('Wrong closing source.');
          }
          final tables = snap['tables'] as Map;
          if (tables.length != IntegrationRepository.reportTables.length ||
              !IntegrationRepository.reportTables.every(tables.containsKey)) {
            throw StateError('Missing closing sources.');
          }
          for (final entry in tables.entries) {
            if (entry.value is! List) {
              throw StateError('Invalid closing rows.');
            }
            for (final row in entry.value as List) {
              if (row is! Map ||
                  (entry.key != 'personnel_payroll_lines_v1' &&
                      row[entry.key == 'finance_documents_v2'
                              ? 'organization_id'
                              : 'farm_id'] !=
                          s['farm_id'])) {
                throw StateError('Cross-farm closing source.');
              }
            }
          }
        } else if (snap.isNotEmpty) {
          throw StateError('Invalid reopening event.');
        }
        previous = e;
      }
      if (s['status'] == 'closed') {
        final frozen = Map<String, dynamic>.from(
          jsonDecode(chain.last['snapshot'] as String) as Map,
        );
        final current = await asOf(db, s['farm_id'] as String, period);
        final frozenTables = frozen['tables'] as Map;
        for (final table in [...PeriodLock.dated.keys, 'trade_lots_v1']) {
          final saved = (frozenTables[table] as List).toList()
            ..sort(
              (a, b) => PeriodLock.encode(a).compareTo(PeriodLock.encode(b)),
            );
          if (PeriodLock.digest(saved) !=
              PeriodLock.digest(current.rows(table))) {
            throw StateError('Closed ledger source changed: $table');
          }
        }
      }
      if (s['revision'] != chain.length ||
          s['event_id'] != chain.last['id'] ||
          s['status'] !=
              (chain.last['action'] == 'close' ? 'closed' : 'open')) {
        throw StateError('Invalid closing state.');
      }
    }
  }
}
