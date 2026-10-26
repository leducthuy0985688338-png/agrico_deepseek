import '../../../core/permissions/operation_scope.dart';
import '../../../core/permissions/authorization.dart';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/machines.dart';
import '../../personnel/domain/personnel.dart' show LaborMoney;

class SqliteMachineRepository
    implements MachineRepository, ScopedOperationRepository<MachineRepository> {
  const SqliteMachineRepository(this.database, {this.scope});
  final OperationScope? scope;
  @override
  MachineRepository scoped(OperationScope scope) => SqliteMachineRepository(
    database,
    scope: this.scope == null
        ? scope
        : OperationScope(
            scope.opened,
            scope.live,
            {...this.scope!.permissions, ...scope.permissions}.toList(),
          ),
  );
  String visible(String machine) => scope?.sql(machine: machine) ?? '1';
  void check(String farm, String machine) =>
      scope?.require(ResourceContext(farmId: farm, machineId: machine));
  final Database database;
  static const tables = {
    'machine_profiles_v1',
    'machine_rates_v1',
    'machine_runs_v1',
    'machine_costs_v1',
    'machine_expenses_v1',
    'machine_audit_v1',
  };
  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS machine_profiles_v1(machine_id TEXT PRIMARY KEY REFERENCES company_catalog_entries_v1(id),farm_id TEXT NOT NULL,body TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>=0))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS machine_rates_v1(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,machine_id TEXT NOT NULL REFERENCES company_catalog_entries_v1(id),effective_on TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),body TEXT NOT NULL,UNIQUE(farm_id,machine_id,effective_on,revision))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS machine_runs_v1(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,machine_id TEXT NOT NULL REFERENCES company_catalog_entries_v1(id),day TEXT NOT NULL,starts_at TEXT NOT NULL,ends_at TEXT NOT NULL,body TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN ('draft','approved','void')),revision INTEGER NOT NULL CHECK(revision>=0),rate_id TEXT REFERENCES machine_rates_v1(id),amount TEXT,currency TEXT CHECK(currency IN ('VND','LAK')))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS machine_costs_v1(source_id TEXT NOT NULL REFERENCES machine_runs_v1(id),farm_id TEXT NOT NULL,plan_id TEXT NOT NULL REFERENCES production_plans_v1(id),minutes INTEGER NOT NULL CHECK(minutes>0),amount TEXT,currency TEXT CHECK(currency IN ('VND','LAK')),PRIMARY KEY(source_id,plan_id))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS machine_expenses_v1(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,machine_id TEXT NOT NULL REFERENCES company_catalog_entries_v1(id),day TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('fuel','maintenance')),reference TEXT NOT NULL,body TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN ('draft','approved','void')),revision INTEGER NOT NULL CHECK(revision>=0))''',
    );
    await db.execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_machine_expense_reference ON machine_expenses_v1(farm_id,machine_id,kind,reference) WHERE status<>'void'",
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_machine_run_interval ON machine_runs_v1(farm_id,machine_id,starts_at,ends_at,status)',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS machine_audit_v1(id INTEGER PRIMARY KEY,farm_id TEXT NOT NULL,entity_id TEXT NOT NULL,action TEXT NOT NULL,actor_id TEXT NOT NULL,reason TEXT NOT NULL,occurred_at TEXT NOT NULL)''',
    );
  }

  static Map<String, dynamic> body(Map<String, Object?> row) =>
      Map<String, dynamic>.from(jsonDecode(row['body'] as String) as Map);
  static Future<void> resource(
    DatabaseExecutor tx,
    String farm,
    String id,
    String kind, {
    bool active = true,
  }) async {
    final found = await tx.rawQuery(
      'SELECT c.id FROM company_catalog_entries_v1 c JOIN parcel_work_resources r ON r.id=c.id AND r.farm_id=c.farm_id AND r.kind=c.kind AND r.code=c.code WHERE c.id=? AND c.farm_id=? AND c.kind=? ${active ? 'AND c.active=1 AND r.active=1' : ''}',
      [id, farm, kind],
    );
    if (found.length != 1) throw StateError('Resource unavailable.');
  }

  static Future<void> audit(
    DatabaseExecutor tx,
    String farm,
    String id,
    String action,
    String actor, [
    String reason = '',
  ]) async {
    MachineRules.requiredText(actor);
    await tx.insert('machine_audit_v1', {
      'farm_id': farm,
      'entity_id': id,
      'action': action,
      'actor_id': actor,
      'reason': reason,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<Map<String, Object?>> one(
    DatabaseExecutor tx,
    String table,
    String farm,
    String id,
  ) async {
    final rows = await tx.query(
      table,
      where: 'farm_id=? AND id=?',
      whereArgs: [farm, id],
    );
    if (rows.length != 1) throw StateError('Record unavailable.');
    return rows.single;
  }

  static void version(Map<String, Object?> row, int revision) {
    if (row['revision'] != revision || row['status'] != 'draft') {
      throw StateError('Stale record or invalid status.');
    }
  }

  @override
  Future<List<MachineCard>> machines(String farm) async {
    final rows = await database.rawQuery(
      "SELECT c.id,c.code,c.name,c.active,p.body,p.revision FROM company_catalog_entries_v1 c JOIN parcel_work_resources r ON r.id=c.id AND r.farm_id=c.farm_id AND r.kind=c.kind AND r.code=c.code LEFT JOIN machine_profiles_v1 p ON p.machine_id=c.id AND p.farm_id=c.farm_id WHERE c.farm_id=? AND c.kind='machine' AND ${visible('c.id')} ORDER BY c.code",
      [farm],
    );
    return rows
        .map(
          (r) => MachineCard(
            r['id'] as String,
            r['code'] as String,
            r['name'] as String,
            r['active'] == 1,
            r['body'] == null
                ? {}
                : Map<String, String>.from(
                    jsonDecode(r['body'] as String) as Map,
                  ),
            (r['revision'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  @override
  Future<void> profile(
    String farm,
    String machine,
    int revision,
    Map<String, String> values,
    String actor,
  ) => database.transaction((tx) async {
    final stamp = scope?.live.stamp(scope!.opened);
    check(farm, machine);
    await resource(tx, farm, machine, 'machine');
    const allowed = {
      'model',
      'serial',
      'plate',
      'owner',
      'fuelType',
      'meterUnit',
      'notes',
    };
    if (values.keys.any((k) => !allowed.contains(k)) ||
        values.values.any((v) => v.length > 2000) ||
        !{'hour', 'km'}.contains(values['meterUnit'])) {
      throw const FormatException('Invalid profile.');
    }
    final existing = await tx.query(
      'machine_profiles_v1',
      where: 'machine_id=?',
      whereArgs: [machine],
    );
    if ((existing.isEmpty ? 0 : existing.single['revision']) != revision) {
      throw StateError('Stale profile.');
    }
    if (existing.isNotEmpty) {
      final old = body(existing.single);
      final runs = await tx.query(
        'machine_runs_v1',
        columns: ['id'],
        where: "machine_id=? AND status<>'void'",
        whereArgs: [machine],
        limit: 1,
      );
      final expenses = await tx.query(
        'machine_expenses_v1',
        columns: ['id'],
        where: "machine_id=? AND status<>'void'",
        whereArgs: [machine],
        limit: 1,
      );
      if ((runs.isNotEmpty || expenses.isNotEmpty) &&
          old['meterUnit'] != values['meterUnit']) {
        throw StateError('Meter unit is locked after use.');
      }
    }
    await tx.insert('machine_profiles_v1', {
      'machine_id': machine,
      'farm_id': farm,
      'body': jsonEncode(values),
      'revision': revision + 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
    await audit(tx, farm, machine, 'profile', actor);
  });
  @override
  Future<List<MachineRate>> rates(String farm) async => (await database.query(
    'machine_rates_v1',
    where: 'farm_id=? AND ${visible('machine_id')}',
    whereArgs: [farm],
    orderBy: 'effective_on DESC,revision DESC',
  )).map((r) => MachineRate.fromJson(body(r))).toList();
  @override
  Future<void> addRate(
    String farm,
    MachineRate rate,
    String actor,
  ) => database.transaction((tx) async {
    final stamp = scope?.live.stamp(scope!.opened);
    check(farm, rate.machineId);
    rate.validate();
    if (rate.revision != 0) {
      throw const FormatException('Revision is allocated by system.');
    }
    await resource(tx, farm, rate.machineId, 'machine');
    final max = await tx.rawQuery(
      'SELECT MAX(revision) AS n FROM machine_rates_v1 WHERE farm_id=? AND machine_id=? AND effective_on=?',
      [farm, rate.machineId, rate.effectiveOn],
    );
    final revision = ((max.single['n'] as int?) ?? 0) + 1;
    final json = rate.toJson()..['revision'] = revision;
    final existing = await tx.query(
      'machine_rates_v1',
      where: 'id=?',
      whereArgs: [rate.id],
    );
    if (existing.isNotEmpty) {
      final old = body(existing.single)..['revision'] = 0;
      if (existing.single['farm_id'] == farm &&
          jsonEncode(old) == jsonEncode(rate.toJson())) {
        return;
      }
      throw StateError('Request identity conflict.');
    }
    await tx.insert('machine_rates_v1', {
      'id': rate.id,
      'farm_id': farm,
      'machine_id': rate.machineId,
      'effective_on': rate.effectiveOn,
      'revision': revision,
      'body': jsonEncode(json),
    });
    if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
    await audit(tx, farm, rate.id, 'rate', actor);
  });
  static Future<void> profileExists(
    DatabaseExecutor tx,
    String farm,
    String machine,
  ) async {
    final rows = await tx.query(
      'machine_profiles_v1',
      where: 'farm_id=? AND machine_id=?',
      whereArgs: [farm, machine],
    );
    if (rows.length != 1 ||
        !{'hour', 'km'}.contains(body(rows.single)['meterUnit'])) {
      throw StateError('Configure meter unit first.');
    }
  }

  static Future<void> checkRun(
    DatabaseExecutor tx,
    String farm,
    MachineRun run, {
    String? exclude,
  }) async {
    run.validate();
    await resource(tx, farm, run.machineId, 'machine');
    await resource(tx, farm, run.operatorId, 'worker');
    await profileExists(tx, farm, run.machineId);
    final rows = await tx.query(
      'machine_runs_v1',
      where: "farm_id=? AND status<>'void'",
      whereArgs: [farm],
    );
    for (final r in rows) {
      if (r['id'] == exclude) continue;
      final other = MachineRun.fromJson(body(r));
      final sameMachine = other.machineId == run.machineId;
      if (!sameMachine && other.operatorId != run.operatorId) continue;
      if (run.startsAt.isBefore(other.endsAt) &&
          run.endsAt.isAfter(other.startsAt)) {
        throw StateError('Machine or operator overlaps.');
      }
      if (sameMachine &&
          ((!other.endsAt.isAfter(run.startsAt) &&
                  ExactDecimal.parse(
                        other.meterEnd,
                      ).compareTo(ExactDecimal.parse(run.meterStart)) >
                      0) ||
              (!other.startsAt.isBefore(run.endsAt) &&
                  ExactDecimal.parse(
                        run.meterEnd,
                      ).compareTo(ExactDecimal.parse(other.meterStart)) >
                      0))) {
        throw StateError('Meter chronology conflict.');
      }
    }
  }

  static Future<void> checkPlan(
    DatabaseExecutor tx,
    String farm,
    MachineRun run,
    MachineAllocation a, {
    String? currency,
  }) async {
    final p = await one(tx, 'production_plans_v1', farm, a.planId);
    if (p['status'] != 'active' ||
        run.businessDay.compareTo(p['starts_on'] as String) < 0 ||
        run.businessDay.compareTo(p['ends_on'] as String) > 0 ||
        (currency != null && p['currency'] != currency)) {
      throw StateError('Plan date/status/currency mismatch.');
    }
    if (a.taskId != null) {
      final tasks = await tx.rawQuery(
        'SELECT t.id,t.worker_resource_id,t.machine_resource_id FROM farm_tasks_v2 t JOIN production_plan_tasks_v1 p ON p.id=t.id WHERE t.id=? AND t.farm_id=? AND p.plan_id=?',
        [a.taskId, farm, a.planId],
      );
      if (tasks.length != 1 ||
          (tasks.single['worker_resource_id'] != null &&
              tasks.single['worker_resource_id'] != run.operatorId) ||
          (tasks.single['machine_resource_id'] != null &&
              tasks.single['machine_resource_id'] != run.machineId)) {
        throw StateError('Task is not eligible.');
      }
    }
  }

  @override
  Future<void> addRun(String farm, MachineRun run, String actor) =>
      database.transaction((tx) async {
        final stamp = scope?.live.stamp(scope!.opened);
        check(farm, run.machineId);
        final existing = await tx.query(
          'machine_runs_v1',
          where: 'id=?',
          whereArgs: [run.id],
        );
        if (existing.isNotEmpty) {
          if (existing.single['farm_id'] == farm &&
              existing.single['body'] == jsonEncode(run.toJson())) {
            return;
          }
          throw StateError('Request identity conflict.');
        }
        await checkRun(tx, farm, run);
        for (final a in run.allocations) {
          await checkPlan(tx, farm, run, a);
        }
        await tx.insert('machine_runs_v1', {
          'id': run.id,
          'farm_id': farm,
          'machine_id': run.machineId,
          'day': run.businessDay,
          'starts_at': run.startsAt.toUtc().toIso8601String(),
          'ends_at': run.endsAt.toUtc().toIso8601String(),
          'body': jsonEncode(run.toJson()),
          'status': 'draft',
          'revision': 0,
        });
        for (final a in run.allocations) {
          await tx.insert('machine_costs_v1', {
            'source_id': run.id,
            'farm_id': farm,
            'plan_id': a.planId,
            'minutes': a.minutes,
          });
        }
        if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
        await audit(tx, farm, run.id, 'run.create', actor);
      });
  @override
  Future<void> approveRun(
    String farm,
    String id,
    int revision,
    String actor,
  ) => database.transaction((tx) async {
    final stamp = scope?.live.stamp(scope!.opened);
    final row = await one(tx, 'machine_runs_v1', farm, id);
    check(farm, row['machine_id']! as String);
    version(row, revision);
    final run = MachineRun.fromJson(body(row));
    final attendanceTable = await tx.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='personnel_entries_v1'",
    );
    if (attendanceTable.isNotEmpty) {
      final attendance = await tx.query(
        'personnel_entries_v1',
        where:
            "farm_id=? AND worker_id=? AND status='approved' AND starts_at<? AND ends_at>?",
        whereArgs: [
          farm,
          run.operatorId,
          run.endsAt.toUtc().toIso8601String(),
          run.startsAt.toUtc().toIso8601String(),
        ],
      );
      if (attendance.any((e) => e['machine_id'] != run.machineId)) {
        throw StateError(
          'Driver wages must be marked included in this machine shift before approval.',
        );
      }
    }

    await checkRun(tx, farm, run, exclude: id);
    final rates = await tx.query(
      'machine_rates_v1',
      where: 'farm_id=? AND machine_id=? AND effective_on<=?',
      whereArgs: [farm, run.machineId, run.businessDay],
      orderBy: 'effective_on DESC,revision DESC',
      limit: 1,
    );
    if (rates.isEmpty) {
      throw StateError('No effective all-inclusive shift rate.');
    }
    final rate = MachineRate.fromJson(body(rates.single));
    final total = rate.cost(run.minutes);
    final amounts = LaborMoney.allocate(
      total,
      run.allocations.map((a) => a.minutes).toList(),
      run.minutes,
      rate.scale,
    );
    for (var i = 0; i < run.allocations.length; i++) {
      final a = run.allocations[i];
      await checkPlan(tx, farm, run, a, currency: rate.currency);
      final changed = await tx.update(
        'machine_costs_v1',
        {'amount': amounts[i], 'currency': rate.currency},
        where: 'source_id=? AND plan_id=? AND farm_id=?',
        whereArgs: [id, a.planId, farm],
      );
      if (changed != 1) throw StateError('Allocation source missing.');
    }
    await tx.update(
      'machine_runs_v1',
      {
        'status': 'approved',
        'revision': revision + 1,
        'rate_id': rate.id,
        'amount': total,
        'currency': rate.currency,
      },
      where: 'id=? AND farm_id=?',
      whereArgs: [id, farm],
    );
    if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
    await audit(tx, farm, id, 'run.approve', actor);
  });
  @override
  Future<List<MachineRecord<MachineRun>>> runs(
    String farm, {
    bool money = true,
  }) async =>
      (await database.query(
            'machine_runs_v1',
            where: 'farm_id=? AND ${visible('machine_id')}',
            whereArgs: [farm],
            orderBy: 'starts_at DESC',
          ))
          .map(
            (r) => MachineRecord(
              MachineRun.fromJson(body(r)),
              r['status'] as String,
              r['revision'] as int,
              amount:
                  money &&
                      (scope == null ||
                          scope!.live.can(
                            scope!.opened,
                            PermissionCodes.financeView,
                            resource: ResourceContext(
                              farmId: farm,
                              machineId: r['machine_id'] as String,
                            ),
                          ))
                  ? r['amount'] as String?
                  : null,
              currency:
                  money &&
                      (scope == null ||
                          scope!.live.can(
                            scope!.opened,
                            PermissionCodes.financeView,
                            resource: ResourceContext(
                              farmId: farm,
                              machineId: r['machine_id'] as String,
                            ),
                          ))
                  ? r['currency'] as String?
                  : null,
              rateId:
                  money &&
                      (scope == null ||
                          scope!.live.can(
                            scope!.opened,
                            PermissionCodes.financeView,
                            resource: ResourceContext(
                              farmId: farm,
                              machineId: r['machine_id'] as String,
                            ),
                          ))
                  ? r['rate_id'] as String?
                  : null,
            ),
          )
          .toList();
  Future<void> _void(
    String table,
    String farm,
    String id,
    int revision,
    String reason,
    String actor,
  ) => database.transaction((tx) async {
    final stamp = scope?.live.stamp(scope!.opened);
    MachineRules.requiredText(reason);
    final r = await one(tx, table, farm, id);
    check(farm, r['machine_id']! as String);
    if (r['revision'] != revision || r['status'] == 'void') {
      throw StateError('Stale record.');
    }
    if (table == 'machine_expenses_v1') {
      final available = await tx.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='integration_machine_links_v1'",
      );
      if (available.isNotEmpty) {
        final linked = await tx.rawQuery(
          "SELECT d.id FROM integration_machine_links_v1 l JOIN trade_documents_v1 d ON d.id=l.document_id WHERE l.expense_id=? AND d.status<>'void'",
          [id],
        );
        final fuel = await tx.query(
          'integration_fuel_issues_v1',
          where: 'expense_id=? AND reversal_movement_id IS NULL',
          whereArgs: [id],
        );
        if (linked.isNotEmpty || fuel.isNotEmpty)
          throw StateError(
            'Reverse the linked payable or fuel issue before voiding its source.',
          );
      }
    }
    if (table == 'machine_runs_v1') {
      final locked = await tx.rawQuery(
        "SELECT p.id FROM machine_costs_v1 c JOIN production_plans_v1 p ON p.id=c.plan_id WHERE c.source_id=? AND p.status IN ('completed','cancelled')",
        [id],
      );
      if (locked.isNotEmpty) throw StateError('Plan is closed.');
    }
    await tx.update(
      table,
      {'status': 'void', 'revision': revision + 1},
      where: 'id=? AND farm_id=?',
      whereArgs: [id, farm],
    );
    if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
    await audit(tx, farm, id, '$table.void', actor, reason);
  });
  @override
  Future<void> voidRun(
    String farm,
    String id,
    int revision,
    String reason,
    String actor,
  ) => _void('machine_runs_v1', farm, id, revision, reason, actor);
  @override
  Future<List<MachineRecord<MachineExpense>>> expenses(String farm) async =>
      (await database.query(
            'machine_expenses_v1',
            where: 'farm_id=? AND ${visible('machine_id')}',
            whereArgs: [farm],
            orderBy: 'day DESC,id',
          ))
          .map(
            (r) => MachineRecord(
              MachineExpense.fromJson(body(r)),
              r['status'] as String,
              r['revision'] as int,
            ),
          )
          .toList();
  @override
  Future<void> addExpense(String farm, MachineExpense e, String actor) =>
      database.transaction((tx) async {
        final stamp = scope?.live.stamp(scope!.opened);
        check(farm, e.machineId);
        e.validate();
        final found = await tx.query(
          'machine_expenses_v1',
          where: 'id=?',
          whereArgs: [e.id],
        );
        if (found.isNotEmpty) {
          if (found.single['farm_id'] == farm &&
              found.single['body'] == jsonEncode(e.toJson())) {
            return;
          }
          throw StateError('Request identity conflict.');
        }
        await resource(tx, farm, e.machineId, 'machine');
        await profileExists(tx, farm, e.machineId);
        await tx.insert('machine_expenses_v1', {
          'id': e.id,
          'farm_id': farm,
          'machine_id': e.machineId,
          'day': e.day,
          'kind': e.kind,
          'reference': e.reference.trim(),
          'body': jsonEncode(e.toJson()),
          'status': 'draft',
          'revision': 0,
        });
        if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
        await audit(tx, farm, e.id, 'expense.create', actor);
      });
  @override
  Future<void> approveExpense(
    String farm,
    String id,
    int revision,
    String actor,
  ) => database.transaction((tx) async {
    final stamp = scope?.live.stamp(scope!.opened);
    final r = await one(tx, 'machine_expenses_v1', farm, id);
    check(farm, r['machine_id']! as String);
    version(r, revision);
    final e = MachineExpense.fromJson(body(r));
    e.validate();
    await resource(tx, farm, e.machineId, 'machine');
    await tx.update(
      'machine_expenses_v1',
      {'status': 'approved', 'revision': revision + 1},
      where: 'id=? AND farm_id=?',
      whereArgs: [id, farm],
    );
    if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
    await audit(tx, farm, id, 'expense.approve', actor);
  });
  @override
  Future<void> voidExpense(
    String farm,
    String id,
    int revision,
    String reason,
    String actor,
  ) => _void('machine_expenses_v1', farm, id, revision, reason, actor);
  @override
  Future<List<ProductionMachineCost>> productionMachineCosts(
    String farm,
  ) async =>
      (await database.rawQuery(
            "SELECT c.*,r.machine_id,r.day FROM machine_costs_v1 c JOIN machine_runs_v1 r ON r.id=c.source_id AND r.farm_id=c.farm_id WHERE c.farm_id=? AND r.status='approved' AND ${visible('r.machine_id')}",
            [farm],
          ))
          .map(
            (r) => ProductionMachineCost(
              sourceId: r['source_id'] as String,
              machineId: r['machine_id'] as String,
              planId: r['plan_id'] as String,
              day: r['day'] as String,
              minutes: r['minutes'] as int,
              amount: r['amount'] as String,
              currency: r['currency'] as String,
            ),
          )
          .toList();
  @override
  Future<List<Map<String, Object?>>> plans(String farm) => database.query(
    'production_plans_v1',
    columns: ['id', 'code', 'name', 'currency', 'starts_on', 'ends_on'],
    where:
        "farm_id=? AND status='active' AND ${scope == null || scope!.farmWide ? '1' : "id IN (SELECT plan_id FROM machine_costs_v1 WHERE ${visible('machine_id').replaceAll('machine_id', '(SELECT machine_id FROM machine_runs_v1 WHERE id=source_id)')} UNION SELECT t.plan_id FROM production_plan_tasks_v1 t JOIN farm_tasks_v2 f ON f.id=t.id AND f.farm_id=t.farm_id WHERE ${visible('f.machine_resource_id')})"}",
    whereArgs: [farm],
    orderBy: 'code',
  );
  @override
  Future<List<Map<String, Object?>>> workers(String farm) => database.query(
    'company_catalog_entries_v1',
    columns: ['id', 'code', 'name', 'active'],
    where:
        "farm_id=? AND kind='worker' AND active=1 AND ${scope == null || scope!.farmWide ? '1' : "id IN (SELECT json_extract(body,'\$.operatorId') FROM machine_runs_v1 WHERE ${visible('machine_id')} UNION SELECT worker_resource_id FROM farm_tasks_v2 WHERE ${visible('machine_resource_id')})"}",
    whereArgs: [farm],
    orderBy: 'code',
  );
}
