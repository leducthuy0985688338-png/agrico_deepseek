import '../../../core/permissions/operation_scope.dart';
import '../../../core/permissions/authorization.dart';
import '../../integration/data/integration_cash.dart';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../domain/personnel.dart';

class SqlitePersonnelRepository
    implements
        PersonnelRepository,
        ProductionLaborCostRepository,
        PersonnelOrganizationRepository,
        ScopedOperationRepository<PersonnelRepository> {
  const SqlitePersonnelRepository(this.database, {this.scope});
  final OperationScope? scope;
  @override
  PersonnelRepository scoped(OperationScope scope) => SqlitePersonnelRepository(
    database,
    scope: this.scope == null
        ? scope
        : OperationScope(
            scope.opened,
            scope.live,
            {...this.scope!.permissions, ...scope.permissions}.toList(),
          ),
  );
  String visible(String worker) {
    if (scope == null || scope!.farmWide) return '1';
    return '$worker IN (SELECT worker_id FROM personnel_profiles_v1 WHERE farm_id=${OperationScope.quote(scope!.subject.farmId)} AND ${scope!.sql(department: 'department_id')})';
  }

  bool permitted(String permission, String farm, String? department) =>
      scope == null ||
      scope!.live.can(
        scope!.opened,
        permission,
        resource: ResourceContext(farmId: farm, departmentId: department),
      );
  Future<void> checkWorker(
    DatabaseExecutor tx,
    String farm,
    String worker,
  ) async {
    if (scope == null) return;
    final rows = await tx.query(
      'personnel_profiles_v1',
      columns: ['department_id'],
      where: 'farm_id=? AND worker_id=?',
      whereArgs: [farm, worker],
    );
    scope!.require(
      ResourceContext(
        farmId: farm,
        departmentId: rows.isEmpty
            ? null
            : rows.single['department_id'] as String?,
      ),
    );
  }

  Future<void> checkRecord(
    DatabaseExecutor tx,
    String farm,
    String table,
    String id,
  ) async {
    final rows = await tx.query(
      table,
      columns: ['worker_id'],
      where: 'farm_id=? AND id=?',
      whereArgs: [farm, id],
    );
    if (rows.length != 1) throw StateError('Record not found.');
    await checkWorker(tx, farm, rows.single['worker_id']! as String);
  }

  @override
  Future<List<PersonnelDepartment>> departments(String farmId) async =>
      (await database.query(
            'personnel_departments_v1',
            where: 'farm_id=? AND ${scope?.sql(department: 'id') ?? '1'}',
            whereArgs: [farmId],
            orderBy: 'name,id',
          ))
          .map(
            (r) => PersonnelDepartment(
              r['id']! as String,
              r['name']! as String,
              code: r['code']! as String,
            ),
          )
          .toList();
  @override
  Future<void> createDepartment(
    String farmId,
    PersonnelDepartment d,
    String actorId,
  ) => database.transaction((tx) async {
    if (d.id.trim().isEmpty || d.name.trim().isEmpty || d.name.length > 200)
      throw const FormatException('Invalid department.');
    final previous = await tx.query(
      'personnel_department_sequences_v1',
      where: 'farm_id=?',
      whereArgs: [farmId],
    );
    final next = previous.isEmpty
        ? 1
        : (previous.single['last_value']! as int) + 1;
    await tx.insert('personnel_department_sequences_v1', {
      'farm_id': farmId,
      'last_value': next,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await tx.insert('personnel_departments_v1', {
      'id': d.id,
      'farm_id': farmId,
      'name': d.name.trim(),
      'code': 'BP-${next.toString().padLeft(3, '0')}',
    });
    await _audit(tx, farmId, d.id, 'department.create', actorId);
  });
  final Database database;
  static const tables = {
    'personnel_departments_v1',
    'personnel_department_sequences_v1',
    'personnel_profiles_v1',
    'personnel_pay_rates_v1',
    'personnel_entries_v1',
    'production_labor_costs_v1',
    'personnel_payrolls_v1',
    'personnel_payroll_lines_v1',
    'personnel_payments_v1',
    'personnel_audit_v1',
    'personnel_payroll_sequences_v1',
  };
  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS personnel_departments_v1(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,code TEXT NOT NULL,name TEXT NOT NULL,UNIQUE(farm_id,name),UNIQUE(farm_id,code))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS personnel_department_sequences_v1(farm_id TEXT PRIMARY KEY,last_value INTEGER NOT NULL CHECK(last_value>0))',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS personnel_profiles_v1 (
      worker_id TEXT PRIMARY KEY REFERENCES company_catalog_entries_v1(id) ON DELETE RESTRICT,
      farm_id TEXT NOT NULL, profile_json TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision>=0))''',
    );
    final profileColumns = await db.rawQuery(
      'PRAGMA table_info(personnel_profiles_v1)',
    );
    if (!profileColumns.any((c) => c['name'] == 'department_id'))
      await db.execute(
        'ALTER TABLE personnel_profiles_v1 ADD COLUMN department_id TEXT REFERENCES personnel_departments_v1(id)',
      );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS personnel_pay_rates_v1 (
      id TEXT PRIMARY KEY, farm_id TEXT NOT NULL, worker_id TEXT NOT NULL REFERENCES company_catalog_entries_v1(id),
      effective_on TEXT NOT NULL, basis TEXT NOT NULL CHECK(basis IN ('hourly','daily','piece')),
      rate TEXT NOT NULL, currency TEXT NOT NULL CHECK(currency IN ('VND','LAK')), overtime_rate TEXT,
      standard_minutes INTEGER NOT NULL CHECK(standard_minutes>0 AND standard_minutes<=1440),
      money_scale INTEGER NOT NULL CHECK(money_scale>=0 AND money_scale<=6), rounding TEXT NOT NULL CHECK(rounding IN ('halfUp','down')),
      piece_unit TEXT NOT NULL, work_type_id TEXT NOT NULL DEFAULT '', revision INTEGER NOT NULL CHECK(revision>0), UNIQUE(farm_id,worker_id,effective_on,basis,piece_unit,work_type_id,revision))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS personnel_entries_v1 (
      id TEXT PRIMARY KEY, farm_id TEXT NOT NULL, worker_id TEXT NOT NULL REFERENCES company_catalog_entries_v1(id),
      business_day TEXT NOT NULL, starts_at TEXT NOT NULL, ends_at TEXT NOT NULL, break_minutes INTEGER NOT NULL,
      regular_minutes INTEGER NOT NULL, overtime_minutes INTEGER NOT NULL, piece_quantity TEXT,
      machine_id TEXT REFERENCES company_catalog_entries_v1(id), notes TEXT NOT NULL,
      requested_basis TEXT CHECK(requested_basis IN ('hourly','daily','piece')), requested_piece_unit TEXT NOT NULL DEFAULT '', work_type_id TEXT NOT NULL DEFAULT '',
      output_quantity TEXT, output_unit TEXT,
      status TEXT NOT NULL CHECK(status IN ('draft','approved','void')), revision INTEGER NOT NULL DEFAULT 0,
      rate_id TEXT REFERENCES personnel_pay_rates_v1(id), currency TEXT CHECK(currency IN ('VND','LAK')),
      regular_amount TEXT, overtime_amount TEXT, piece_amount TEXT, total_amount TEXT, approved_by TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS production_labor_costs_v1 (
      entry_id TEXT NOT NULL REFERENCES personnel_entries_v1(id) ON DELETE RESTRICT,
      plan_id TEXT NOT NULL REFERENCES production_plans_v1(id) ON DELETE RESTRICT,
      farm_id TEXT NOT NULL, task_id TEXT REFERENCES farm_tasks_v2(id),
      regular_minutes INTEGER NOT NULL CHECK(regular_minutes>=0), overtime_minutes INTEGER NOT NULL CHECK(overtime_minutes>=0),
      amount TEXT, currency TEXT CHECK(currency IN ('VND','LAK')), PRIMARY KEY(entry_id,plan_id))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS personnel_payrolls_v1 (
      id TEXT PRIMARY KEY, farm_id TEXT NOT NULL, worker_id TEXT NOT NULL REFERENCES company_catalog_entries_v1(id),
      code TEXT NOT NULL,worker_name_snapshot TEXT NOT NULL, period TEXT NOT NULL, currency TEXT NOT NULL CHECK(currency IN ('VND','LAK')),
      status TEXT NOT NULL CHECK(status IN ('draft','approved','cancelled')), regular TEXT NOT NULL,
      overtime TEXT NOT NULL, piece TEXT NOT NULL, allowance TEXT NOT NULL, bonus TEXT NOT NULL,
      advance TEXT NOT NULL, deduction TEXT NOT NULL, net TEXT NOT NULL, note TEXT NOT NULL,
      adjustment_plan_id TEXT REFERENCES production_plans_v1(id), extra_cost_day TEXT NOT NULL, UNIQUE(farm_id,code))''',
    );
    await db.execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_personnel_payroll_period ON personnel_payrolls_v1(farm_id,worker_id,period,currency) WHERE status<>'cancelled'",
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS personnel_payroll_lines_v1 (
      payroll_id TEXT NOT NULL REFERENCES personnel_payrolls_v1(id), entry_id TEXT NOT NULL REFERENCES personnel_entries_v1(id),
      amount TEXT NOT NULL, active INTEGER NOT NULL CHECK(active IN (0,1)), PRIMARY KEY(payroll_id,entry_id))''',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_personnel_payroll_source ON personnel_payroll_lines_v1(entry_id) WHERE active=1',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS personnel_payments_v1 (
      id TEXT PRIMARY KEY, farm_id TEXT NOT NULL, payroll_id TEXT NOT NULL REFERENCES personnel_payrolls_v1(id),
      amount TEXT NOT NULL,currency TEXT NOT NULL CHECK(currency IN ('VND','LAK')),business_day TEXT NOT NULL,note TEXT NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS personnel_audit_v1 (
      id INTEGER PRIMARY KEY,farm_id TEXT NOT NULL,entity_id TEXT NOT NULL,action TEXT NOT NULL,
      actor_id TEXT NOT NULL,reason TEXT NOT NULL,occurred_at TEXT NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS personnel_payroll_sequences_v1 (
      farm_id TEXT NOT NULL,period TEXT NOT NULL,last_value INTEGER NOT NULL CHECK(last_value>0),PRIMARY KEY(farm_id,period))''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_personnel_entries_period ON personnel_entries_v1(farm_id,worker_id,business_day,status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_personnel_labor_plan ON production_labor_costs_v1(farm_id,plan_id)',
    );
  }

  static Future<void> _audit(
    DatabaseExecutor tx,
    String farm,
    String id,
    String action,
    String actor, [
    String reason = '',
  ]) async {
    if (actor.trim().isEmpty) throw const FormatException('Actor required.');
    await tx.insert('personnel_audit_v1', {
      'farm_id': farm,
      'entity_id': id,
      'action': action,
      'actor_id': actor,
      'reason': reason,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<void> _worker(
    DatabaseExecutor tx,
    String farm,
    String id, {
    bool active = true,
    String kind = 'worker',
  }) async {
    final rows = await tx.rawQuery(
      'SELECT c.id FROM company_catalog_entries_v1 c JOIN parcel_work_resources r ON r.id=c.id AND r.farm_id=c.farm_id AND r.kind=c.kind WHERE c.id=? AND c.farm_id=? AND c.kind=? AND c.code=r.code ${active ? 'AND c.active=1 AND r.active=1' : ''}',
      [id, farm, kind],
    );
    if (rows.length != 1) {
      throw StateError('Shared resource is unavailable in this farm.');
    }
  }

  static Future<void> _workType(
    DatabaseExecutor tx,
    String farm,
    String type,
  ) async {
    if (type.isEmpty) return;
    final rows = await tx.query(
      'company_catalog_entries_v1',
      columns: ['id'],
      where: "id=? AND farm_id=? AND kind='taskType' AND active=1",
      whereArgs: [type, farm],
    );
    if (rows.length != 1) {
      throw StateError('Work type is unavailable in this farm.');
    }
  }

  static Future<void> _unit(
    DatabaseExecutor tx,
    String farm,
    String name,
  ) async {
    if (name.isEmpty) return;
    final rows = await tx.query(
      'company_catalog_entries_v1',
      columns: ['id'],
      where: "farm_id=? AND kind='unit' AND name=? AND active=1",
      whereArgs: [farm, name],
    );
    if (rows.length != 1) throw StateError('Choose an active shared unit.');
  }

  @override
  Future<List<EmployeeCard>> employees(
    String farmId, {
    required bool sensitive,
  }) async {
    final rows = await database.rawQuery(
      "SELECT c.*, p.profile_json, p.department_id, p.revision AS profile_revision FROM company_catalog_entries_v1 c "
      "LEFT JOIN personnel_profiles_v1 p ON p.worker_id=c.id AND p.farm_id=c.farm_id WHERE c.farm_id=? AND c.kind='worker' AND ${visible('c.id')} ORDER BY c.code",
      [farmId],
    );
    return rows
        .map((r) {
          final details = r['profile_json'] == null
              ? null
              : Map<String, String>.from(
                  jsonDecode(r['profile_json']! as String) as Map,
                );
          if ((!sensitive ||
                  !permitted(
                    PermissionCodes.employeeSensitiveView,
                    farmId,
                    r['department_id'] as String?,
                  )) &&
              details != null) {
            for (final k in EmployeeProfile.sensitiveFields) {
              details.remove(k);
            }
          }
          return EmployeeCard(
            workerId: r['id']! as String,
            code: r['code']! as String,
            name: r['name']! as String,
            active: r['active'] == 1,
            profile: details == null
                ? null
                : EmployeeProfile(
                    workerId: r['id']! as String,
                    farmId: farmId,
                    details: details,
                    departmentId: r['department_id'] as String?,
                    revision: r['profile_revision']! as int,
                  ),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> saveProfile(EmployeeProfile p, String actorId) async {
    p.validate();
    await database.transaction((tx) async {
      final stamp = scope?.live.stamp(scope!.opened);
      await _worker(tx, p.farmId, p.workerId, active: false);
      await checkWorker(tx, p.farmId, p.workerId);
      final rows = await tx.query(
        'personnel_profiles_v1',
        where: 'worker_id=? AND farm_id=?',
        whereArgs: [p.workerId, p.farmId],
      );
      String? departmentName;
      if (p.departmentId != null) {
        final d = await tx.query(
          'personnel_departments_v1',
          where: 'id=? AND farm_id=?',
          whereArgs: [p.departmentId, p.farmId],
        );
        if (d.length != 1) throw StateError('Department outside farm.');
        departmentName = d.single['name']! as String;
      }
      final oldDepartment = rows.isEmpty ? null : rows.single['department_id'];
      if (p.departmentId != oldDepartment && scope != null && !scope!.farmWide)
        throw StateError('Only farm-wide editors can reassign departments.');
      final privateAccess =
          scope == null ||
          scope!.live.can(
            scope!.opened,
            PermissionCodes.employeeSensitiveView,
            resource: ResourceContext(
              farmId: p.farmId,
              departmentId: oldDepartment as String?,
            ),
          );
      final values = Map<String, String>.from(p.details);
      if (departmentName != null) values['department'] = departmentName;
      if (!privateAccess) {
        if (values.keys.any(EmployeeProfile.sensitiveFields.contains))
          throw StateError('Private fields require explicit access.');
        if (rows.isNotEmpty) {
          final old = Map<String, String>.from(
            jsonDecode(rows.single['profile_json']! as String) as Map,
          );
          for (final key in EmployeeProfile.sensitiveFields) {
            if (old.containsKey(key)) values[key] = old[key]!;
          }
        }
      }
      if (rows.isEmpty) {
        if (p.revision != 0) throw StateError('Stale profile.');
        await tx.insert('personnel_profiles_v1', {
          'worker_id': p.workerId,
          'farm_id': p.farmId,
          'profile_json': jsonEncode(values),
          'department_id': p.departmentId,
          'revision': 1,
        });
      } else {
        final n = await tx.update(
          'personnel_profiles_v1',
          {
            'profile_json': jsonEncode(values),
            'department_id': p.departmentId,
            'revision': p.revision + 1,
          },
          where: 'worker_id=? AND farm_id=? AND revision=?',
          whereArgs: [p.workerId, p.farmId, p.revision],
        );
        if (n != 1) throw StateError('Stale profile.');
      }
      if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
      await _audit(tx, p.farmId, p.workerId, 'profile.save', actorId);
    });
  }

  static PayRate rateFromRow(Map<String, Object?> r) => PayRate(
    id: r['id']! as String,
    farmId: r['farm_id']! as String,
    workerId: r['worker_id']! as String,
    effectiveOn: r['effective_on']! as String,
    basis: PayBasis.values.byName(r['basis']! as String),
    rate: r['rate']! as String,
    currency: r['currency']! as String,
    rounding: MoneyRounding.values.byName(r['rounding']! as String),
    moneyScale: r['money_scale']! as int,
    standardMinutes: r['standard_minutes']! as int,
    overtimeHourlyRate: r['overtime_rate'] as String?,
    pieceUnit: r['piece_unit']! as String,
    workTypeId: r['work_type_id']! as String,
    revision: r['revision']! as int,
  );
  @override
  Future<List<PayRate>> rates(String farmId) async => (await database.query(
    'personnel_pay_rates_v1',
    where: 'farm_id=? AND ${visible('worker_id')}',
    whereArgs: [farmId],
    orderBy: 'worker_id,effective_on DESC,revision DESC',
  )).map(rateFromRow).toList(growable: false);
  @override
  Future<void> createRate(PayRate r, String actorId) async {
    r.validate();
    await database.transaction((tx) async {
      final stamp = scope?.live.stamp(scope!.opened);
      await checkWorker(tx, r.farmId, r.workerId);
      await _worker(tx, r.farmId, r.workerId);
      await _workType(tx, r.farmId, r.workTypeId);
      if (r.basis == PayBasis.piece) await _unit(tx, r.farmId, r.pieceUnit);
      if (r.revision != 0) {
        throw const FormatException('Create an unversioned rate proposal.');
      }
      final previous = await tx.query(
        'personnel_pay_rates_v1',
        columns: ['revision'],
        where:
            'farm_id=? AND worker_id=? AND effective_on=? AND basis=? AND piece_unit=? AND work_type_id=?',
        whereArgs: [
          r.farmId,
          r.workerId,
          r.effectiveOn,
          r.basis.name,
          r.pieceUnit,
          r.workTypeId,
        ],
        orderBy: 'revision DESC',
        limit: 1,
      );
      final revision = previous.isEmpty
          ? 1
          : (previous.single['revision']! as int) + 1;
      await tx.insert('personnel_pay_rates_v1', {
        'id': r.id,
        'farm_id': r.farmId,
        'worker_id': r.workerId,
        'effective_on': r.effectiveOn,
        'basis': r.basis.name,
        'rate': r.rate,
        'currency': r.currency,
        'overtime_rate': r.overtimeHourlyRate,
        'standard_minutes': r.standardMinutes,
        'money_scale': r.moneyScale,
        'rounding': r.rounding.name,
        'piece_unit': r.pieceUnit,
        'work_type_id': r.workTypeId,
        'revision': revision,
      });
      if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
      await _audit(tx, r.farmId, r.id, 'rate.create', actorId);
    });
  }

  @override
  Future<List<LaborEntryRecord>> entries(
    String farmId, {
    required bool money,
  }) async {
    final rows = await database.rawQuery(
      'SELECT e.*,(SELECT department_id FROM personnel_profiles_v1 WHERE worker_id=e.worker_id) AS department_id,c.name,r.piece_unit,r.standard_minutes,t.name AS work_type_name FROM personnel_entries_v1 e '
      'JOIN company_catalog_entries_v1 c ON c.id=e.worker_id AND c.farm_id=e.farm_id LEFT JOIN personnel_pay_rates_v1 r ON r.id=e.rate_id '
      "LEFT JOIN company_catalog_entries_v1 t ON t.id=e.work_type_id AND t.farm_id=e.farm_id AND t.kind='taskType' "
      'WHERE e.farm_id=? AND ${visible('e.worker_id')} ORDER BY e.business_day DESC,e.starts_at,e.id',
      [farmId],
    );
    final labels = await database.rawQuery(
      'SELECT c.entry_id,c.regular_minutes,c.overtime_minutes,p.code,p.name FROM production_labor_costs_v1 c JOIN production_plans_v1 p ON p.id=c.plan_id AND p.farm_id=c.farm_id WHERE c.farm_id=? ORDER BY p.code',
      [farmId],
    );
    return rows
        .map(
          (r) => LaborEntryRecord(
            id: r['id']! as String,
            workerId: r['worker_id']! as String,
            workerName: r['name']! as String,
            businessDay: r['business_day']! as String,
            startsAt: DateTime.parse(r['starts_at']! as String),
            endsAt: DateTime.parse(r['ends_at']! as String),
            breakMinutes: r['break_minutes']! as int,
            regularMinutes: r['regular_minutes']! as int,
            overtimeMinutes: r['overtime_minutes']! as int,
            status: r['status']! as String,
            revision: r['revision']! as int,
            pieceQuantity: r['piece_quantity'] as String?,
            pieceUnit: r['piece_unit'] as String?,
            currency:
                money &&
                    permitted(
                      PermissionCodes.payrollView,
                      farmId,
                      r['department_id'] as String?,
                    )
                ? r['currency'] as String?
                : null,
            regularAmount:
                money &&
                    permitted(
                      PermissionCodes.payrollView,
                      farmId,
                      r['department_id'] as String?,
                    )
                ? r['regular_amount'] as String?
                : null,
            overtimeAmount:
                money &&
                    permitted(
                      PermissionCodes.payrollView,
                      farmId,
                      r['department_id'] as String?,
                    )
                ? r['overtime_amount'] as String?
                : null,
            pieceAmount:
                money &&
                    permitted(
                      PermissionCodes.payrollView,
                      farmId,
                      r['department_id'] as String?,
                    )
                ? r['piece_amount'] as String?
                : null,
            rateId:
                money &&
                    permitted(
                      PermissionCodes.payrollView,
                      farmId,
                      r['department_id'] as String?,
                    )
                ? r['rate_id'] as String?
                : null,
            standardMinutes: r['standard_minutes'] as int?,
            machineId: r['machine_id'] as String?,
            outputQuantity: r['output_quantity'] as String?,
            outputUnit: r['output_unit'] as String?,
            workTypeLabel: r['work_type_name'] as String?,
            planLabels: labels
                .where((a) => a['entry_id'] == r['id'])
                .map(
                  (a) =>
                      "${a['code']} · ${a['name']} (${a['regular_minutes']} + ${a['overtime_minutes']} min)",
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  static Future<void> _destination(
    DatabaseExecutor tx,
    String farm,
    String planId,
    String day, {
    String? currency,
    String? taskId,
    String? workerId,
  }) async {
    final rows = await tx.rawQuery(
      'SELECT p.id FROM production_plans_v1 p JOIN production_seasons_v2 s ON s.id=p.season_id AND s.farm_id=p.farm_id '
              'JOIN land_parcels l ON l.id=p.parcel_id AND l.farm_id=p.farm_id '
              "WHERE p.id=? AND p.farm_id=? AND p.status='active' AND s.active=1 AND l.active=1 AND p.starts_on<=? AND p.ends_on>=? " +
          (currency == null ? '' : 'AND p.currency=?'),
      [planId, farm, day, day, ?currency],
    );
    if (rows.length != 1) {
      throw StateError('Active plan in this farm/date/currency required.');
    }
    if (taskId != null) {
      final tasks = await tx.rawQuery(
        'SELECT t.id FROM production_plan_tasks_v1 t JOIN farm_tasks_v2 f ON f.id=t.id AND f.farm_id=t.farm_id '
        'WHERE t.id=? AND t.plan_id=? AND t.farm_id=? AND (f.worker_resource_id IS NULL OR f.worker_resource_id=?)',
        [taskId, planId, farm, workerId],
      );
      if (tasks.length != 1) {
        throw StateError('Task does not match plan/worker.');
      }
    }
  }

  @override
  Future<void> createEntry(LaborEntryDraft d, String actorId) async {
    d.validate();
    await database.transaction((tx) async {
      final stamp = scope?.live.stamp(scope!.opened);
      await checkWorker(tx, d.farmId, d.workerId);
      await _worker(tx, d.farmId, d.workerId);
      await _workType(tx, d.farmId, d.workTypeId);
      await _unit(tx, d.farmId, d.requestedPieceUnit);
      if (d.outputUnit != null) await _unit(tx, d.farmId, d.outputUnit!);
      if (d.machineId != null) {
        await _worker(tx, d.farmId, d.machineId!, kind: 'machine');
      }
      final overlap = await tx.query(
        'personnel_entries_v1',
        columns: ['id'],
        where:
            "worker_id=? AND farm_id=? AND status<>'void' AND starts_at<? AND ends_at>?",
        whereArgs: [
          d.workerId,
          d.farmId,
          d.endsAt.toUtc().toIso8601String(),
          d.startsAt.toUtc().toIso8601String(),
        ],
        limit: 1,
      );
      if (overlap.isNotEmpty) {
        throw StateError('Attendance overlaps an existing entry.');
      }
      for (final a in d.allocations) {
        await _destination(
          tx,
          d.farmId,
          a.planId,
          d.businessDay,
          taskId: a.taskId,
          workerId: d.workerId,
        );
      }
      await tx.insert('personnel_entries_v1', {
        'id': d.id,
        'farm_id': d.farmId,
        'worker_id': d.workerId,
        'business_day': d.businessDay,
        'starts_at': d.startsAt.toUtc().toIso8601String(),
        'ends_at': d.endsAt.toUtc().toIso8601String(),
        'break_minutes': d.breakMinutes,
        'regular_minutes': d.regularMinutes,
        'overtime_minutes': d.overtimeMinutes,
        'piece_quantity': d.pieceQuantity,
        'machine_id': d.machineId,
        'requested_basis': d.requestedBasis?.name,
        'requested_piece_unit': d.requestedPieceUnit,
        'work_type_id': d.workTypeId,
        'output_quantity': d.outputQuantity,
        'output_unit': d.outputUnit,
        'notes': d.notes,
        'status': 'draft',
        'revision': 0,
      });
      for (final a in d.allocations) {
        await tx.insert('production_labor_costs_v1', {
          'entry_id': d.id,
          'plan_id': a.planId,
          'farm_id': d.farmId,
          'task_id': a.taskId,
          'regular_minutes': a.regularMinutes,
          'overtime_minutes': a.overtimeMinutes,
        });
      }
      if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
      await _audit(tx, d.farmId, d.id, 'entry.create', actorId);
    });
  }

  static Map<String, String> earnings(Map<String, Object?> e, PayRate r) {
    final normal = e['regular_minutes']! as int,
        ot = e['overtime_minutes']! as int;
    final quantity = e['piece_quantity'] as String?;
    if ((r.basis == PayBasis.piece) != (quantity != null)) {
      throw StateError('Pay basis does not match attendance.');
    }
    if (ot > 0 && r.overtimeHourlyRate == null) {
      throw StateError('Overtime rate is not configured.');
    }
    final regular = r.basis == PayBasis.piece
        ? '0'
        : LaborMoney.fraction(
            r.rate,
            normal,
            r.basis == PayBasis.daily ? r.standardMinutes : 60,
            r.moneyScale,
            r.rounding,
          );
    final overtime = ot == 0
        ? '0'
        : LaborMoney.fraction(
            r.overtimeHourlyRate!,
            ot,
            60,
            r.moneyScale,
            r.rounding,
          );
    final piece = quantity == null
        ? '0'
        : LaborMoney.fraction(
            (ExactDecimal.parse(quantity) * ExactDecimal.parse(r.rate))
                .toString(),
            1,
            1,
            r.moneyScale,
            r.rounding,
          );
    return {
      'regular': regular,
      'overtime': overtime,
      'piece': piece,
      'total': LaborMoney.sum([regular, overtime, piece]),
    };
  }

  static List<String> allocationAmounts(
    Map<String, Object?> e,
    PayRate r,
    List<Map<String, Object?>> allocations,
  ) {
    final source = earnings(e, r);
    final regular = LaborMoney.allocate(
      LaborMoney.sum([source['regular']!, source['piece']!]),
      allocations.map((a) => a['regular_minutes']! as int).toList(),
      e['regular_minutes']! as int,
      r.moneyScale,
    );
    final overtime = LaborMoney.allocate(
      source['overtime']!,
      allocations.map((a) => a['overtime_minutes']! as int).toList(),
      e['overtime_minutes']! as int,
      r.moneyScale,
    );
    return [
      for (var i = 0; i < allocations.length; i++)
        e['machine_id'] != null
            ? '0'
            : LaborMoney.sum([regular[i], overtime[i]]),
    ];
  }

  @override
  Future<void> approveEntry(
    String farmId,
    String id,
    int revision,
    String actorId,
  ) async {
    await database.transaction((tx) async {
      final stamp = scope?.live.stamp(scope!.opened);
      final rows = await tx.query(
        'personnel_entries_v1',
        where: "id=? AND farm_id=? AND status='draft' AND revision=?",
        whereArgs: [id, farmId, revision],
      );
      if (rows.length != 1) throw StateError('Stale or non-draft attendance.');
      final e = rows.single;
      await checkWorker(tx, farmId, e['worker_id']! as String);
      await _worker(tx, farmId, e['worker_id']! as String);
      final machineTable = await tx.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='machine_runs_v1'",
      );
      if (machineTable.isNotEmpty) {
        final machines = await tx.query(
          'machine_runs_v1',
          where:
              "farm_id=? AND status='approved' AND starts_at<? AND ends_at>?",
          whereArgs: [farmId, e['ends_at'], e['starts_at']],
        );
        for (final machine in machines) {
          final detail = jsonDecode(machine['body'] as String) as Map;
          if (detail['operatorId'] == e['worker_id'] &&
              e['machine_id'] != machine['machine_id']) {
            throw StateError(
              'Driver wages are included in the all-inclusive machine shift. Select that machine.',
            );
          }
        }
      }

      final basis = e['requested_basis'] as String?;
      final unit = e['requested_piece_unit']! as String;
      final type = e['work_type_id']! as String;
      final rates = await tx.query(
        'personnel_pay_rates_v1',
        where:
            'worker_id=? AND farm_id=? AND effective_on<=? AND work_type_id IN (?,?) AND ${basis != null
                ? 'basis=?'
                : e['piece_quantity'] != null
                ? "basis='piece'"
                : "basis IN ('hourly','daily')"}${unit.isEmpty ? '' : ' AND piece_unit=?'}',
        whereArgs: [
          e['worker_id'],
          farmId,
          e['business_day'],
          '',
          type,
          ?basis,
          if (unit.isNotEmpty) unit,
        ],
        orderBy:
            "CASE WHEN work_type_id='' THEN 1 ELSE 0 END,effective_on DESC,revision DESC,id",
      );
      if (rates.isEmpty) throw StateError('No effective pay rate.');
      final latest = rates
          .where(
            (r) =>
                r['effective_on'] == rates.first['effective_on'] &&
                r['work_type_id'] == rates.first['work_type_id'],
          )
          .toList();
      if (latest
              .map((r) => "${r['basis']}/${r['piece_unit']}")
              .toSet()
              .length !=
          1) {
        throw StateError('Choose an explicit pay basis and piece unit.');
      }
      final r = rateFromRow(latest.first);
      final approved = await tx.rawQuery(
        "SELECT COALESCE(SUM(regular_minutes),0) AS n FROM personnel_entries_v1 WHERE worker_id=? AND farm_id=? AND business_day=? AND status='approved'",
        [e['worker_id'], farmId, e['business_day']],
      );
      if ((approved.single['n']! as int) + (e['regular_minutes']! as int) >
          r.standardMinutes) {
        throw StateError(
          'Regular time exceeds the configured workday. Record approved overtime separately.',
        );
      }
      final amount = earnings(e, r);
      final allocations = await tx.query(
        'production_labor_costs_v1',
        where: 'entry_id=?',
        whereArgs: [id],
        orderBy: 'plan_id',
      );
      final allocated = allocationAmounts(e, r, allocations);
      for (var i = 0; i < allocations.length; i++) {
        final a = allocations[i];
        await _destination(
          tx,
          farmId,
          a['plan_id']! as String,
          e['business_day']! as String,
          currency: r.currency,
          taskId: a['task_id'] as String?,
          workerId: e['worker_id']! as String,
        );
        if (r.basis == PayBasis.piece && a['task_id'] != null) {
          final task = await tx.query(
            'production_plan_tasks_v1',
            columns: ['unit'],
            where: 'id=? AND farm_id=?',
            whereArgs: [a['task_id'], farmId],
          );
          if (task.single['unit'] != r.pieceUnit) {
            throw StateError('Piece unit differs from task unit.');
          }
        }
        await tx.update(
          'production_labor_costs_v1',
          {'amount': allocated[i], 'currency': r.currency},
          where: 'entry_id=? AND plan_id=?',
          whereArgs: [id, a['plan_id']],
        );
      }
      await tx.update(
        'personnel_entries_v1',
        {
          'status': 'approved',
          'revision': revision + 1,
          'rate_id': r.id,
          'currency': r.currency,
          'regular_amount': amount['regular'],
          'overtime_amount': amount['overtime'],
          'piece_amount': amount['piece'],
          'total_amount': amount['total'],
          'approved_by': actorId,
        },
        where: 'id=? AND farm_id=? AND revision=?',
        whereArgs: [id, farmId, revision],
      );
      if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
      await _audit(tx, farmId, id, 'entry.approve', actorId);
    });
  }

  @override
  Future<void> voidEntry(
    String farmId,
    String id,
    int revision,
    String reason,
    String actorId,
  ) async {
    if (reason.trim().isEmpty) {
      throw const FormatException('Void reason required.');
    }
    await database.transaction((tx) async {
      final stamp = scope?.live.stamp(scope!.opened);
      await checkRecord(tx, farmId, 'personnel_entries_v1', id);
      if ((await tx.query(
        'personnel_payroll_lines_v1',
        where: 'entry_id=? AND active=1',
        whereArgs: [id],
        limit: 1,
      )).isNotEmpty) {
        throw StateError('Payroll has locked this entry.');
      }
      final n = await tx.update(
        'personnel_entries_v1',
        {'status': 'void', 'revision': revision + 1},
        where: "id=? AND farm_id=? AND revision=? AND status<>'void'",
        whereArgs: [id, farmId, revision],
      );
      if (n != 1) throw StateError('Stale entry.');
      if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
      await _audit(tx, farmId, id, 'entry.void', actorId, reason);
    });
  }

  @override
  Future<List<ProductionLaborCost>> productionLaborCosts(String farmId) async {
    final exists = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='production_labor_costs_v1'",
    );
    if (exists.isEmpty) return [];
    final rows = await database.rawQuery(
      "SELECT c.*,e.business_day FROM production_labor_costs_v1 c JOIN personnel_entries_v1 e ON e.id=c.entry_id AND e.farm_id=c.farm_id WHERE c.farm_id=? AND e.status='approved' AND ${visible('e.worker_id')} ORDER BY e.business_day,c.entry_id,c.plan_id",
      [farmId],
    );
    final extras = await database.query(
      'personnel_payrolls_v1',
      where:
          "farm_id=? AND status='approved' AND adjustment_plan_id IS NOT NULL AND ${visible('worker_id')}",
      whereArgs: [farmId],
    );
    return [
      ...rows.map(
        (r) => ProductionLaborCost(
          entryId: r['entry_id']! as String,
          planId: r['plan_id']! as String,
          currency: r['currency']! as String,
          amount: r['amount']! as String,
          businessDay: r['business_day']! as String,
          regularMinutes: r['regular_minutes']! as int,
          overtimeMinutes: r['overtime_minutes']! as int,
        ),
      ),
      for (final p in extras)
        ProductionLaborCost(
          entryId: 'payroll:${p['id']}',
          planId: p['adjustment_plan_id']! as String,
          currency: p['currency']! as String,
          amount: LaborMoney.sum([
            p['allowance']! as String,
            p['bonus']! as String,
          ]),
          businessDay: p['extra_cost_day']! as String,
          regularMinutes: 0,
          overtimeMinutes: 0,
        ),
    ];
  }

  @override
  Future<List<PayrollRecordV2>> payrolls(String farmId) async {
    final rows = await database.rawQuery(
      'SELECT p.*,c.name FROM personnel_payrolls_v1 p JOIN company_catalog_entries_v1 c ON c.id=p.worker_id AND c.farm_id=p.farm_id WHERE p.farm_id=? AND ${visible('p.worker_id')} ORDER BY p.period DESC,p.code',
      [farmId],
    );
    final payments = await IntegrationCash.activePayments(database, farmId);
    return rows
        .map(
          (r) => PayrollRecordV2(
            id: r['id']! as String,
            code: r['code']! as String,
            workerId: r['worker_id']! as String,
            workerName: r['worker_name_snapshot']! as String,
            period: r['period']! as String,
            currency: r['currency']! as String,
            status: r['status']! as String,
            regular: r['regular']! as String,
            overtime: r['overtime']! as String,
            piece: r['piece']! as String,
            allowance: r['allowance']! as String,
            bonus: r['bonus']! as String,
            advance: r['advance']! as String,
            deduction: r['deduction']! as String,
            net: r['net']! as String,
            adjustmentPlanId: r['adjustment_plan_id'] as String?,
            paid: LaborMoney.sum(
              payments
                  .where((p) => p['payroll_id'] == r['id'])
                  .map((p) => p['amount']! as String),
            ),
            note: r['note']! as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> createPayroll(PayrollDraft d, String actorId) async {
    d.validate();
    await database.transaction((tx) async {
      final stamp = scope?.live.stamp(scope!.opened);
      await checkWorker(tx, d.farmId, d.workerId);
      await _worker(tx, d.farmId, d.workerId, active: false);
      final sources = await tx.rawQuery(
        "SELECT e.* FROM personnel_entries_v1 e WHERE e.farm_id=? AND e.worker_id=? AND substr(e.business_day,1,7)=? AND e.currency=? AND e.status='approved' AND NOT EXISTS(SELECT 1 FROM personnel_payroll_lines_v1 l WHERE l.entry_id=e.id AND l.active=1) ORDER BY e.business_day,e.id",
        [d.farmId, d.workerId, d.period, d.currency],
      );
      if (sources.isEmpty) {
        throw StateError(
          'No approved unpaid earnings in this period/currency.',
        );
      }
      String sum(String key) =>
          LaborMoney.sum(sources.map((e) => e[key]! as String));
      final normal = sum('regular_amount'),
          ot = sum('overtime_amount'),
          piece = sum('piece_amount');
      final net = LaborMoney.minus(
        LaborMoney.sum([normal, ot, piece, d.allowance, d.bonus]),
        LaborMoney.sum([d.advance, d.deduction]),
      );
      if (ExactDecimal.parse(net).isNegative) {
        throw StateError('Deductions exceed payable earnings.');
      }
      final extraDay = sources.last['business_day']! as String;
      if (d.adjustmentPlanId != null) {
        await _destination(
          tx,
          d.farmId,
          d.adjustmentPlanId!,
          extraDay,
          currency: d.currency,
        );
      }
      final sequence = await tx.query(
        'personnel_payroll_sequences_v1',
        where: 'farm_id=? AND period=?',
        whereArgs: [d.farmId, d.period],
      );
      final next = sequence.isEmpty
          ? 1
          : (sequence.single['last_value']! as int) + 1;
      await tx.insert('personnel_payroll_sequences_v1', {
        'farm_id': d.farmId,
        'period': d.period,
        'last_value': next,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final worker = (await tx.query(
        'company_catalog_entries_v1',
        columns: ['name'],
        where: 'id=? AND farm_id=?',
        whereArgs: [d.workerId, d.farmId],
      )).single;
      await tx.insert('personnel_payrolls_v1', {
        'id': d.id,
        'farm_id': d.farmId,
        'worker_id': d.workerId,
        'period': d.period,
        'currency': d.currency,
        'worker_name_snapshot': worker['name'],
        'code':
            'LUONG-${d.period.replaceAll('-', '')}-${next.toString().padLeft(3, '0')}',
        'status': 'draft',
        'regular': normal,
        'overtime': ot,
        'piece': piece,
        'allowance': d.allowance,
        'bonus': d.bonus,
        'advance': d.advance,
        'deduction': d.deduction,
        'net': net,
        'note': d.note,
        'adjustment_plan_id': d.adjustmentPlanId,
        'extra_cost_day': extraDay,
      });
      for (final e in sources) {
        await tx.insert('personnel_payroll_lines_v1', {
          'payroll_id': d.id,
          'entry_id': e['id'],
          'amount': e['total_amount'],
          'active': 1,
        });
      }
      if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
      await _audit(tx, d.farmId, d.id, 'payroll.create', actorId, d.note);
    });
  }

  @override
  Future<void> approvePayroll(String farmId, String id, String actorId) async {
    await database.transaction((tx) async {
      final stamp = scope?.live.stamp(scope!.opened);
      final rows = await tx.query(
        'personnel_payrolls_v1',
        where: "id=? AND farm_id=? AND status='draft'",
        whereArgs: [id, farmId],
      );
      if (rows.length != 1) throw StateError('Payroll draft required.');
      final p = rows.single;
      await checkWorker(tx, farmId, p['worker_id']! as String);
      if (p['adjustment_plan_id'] != null) {
        await _destination(
          tx,
          farmId,
          p['adjustment_plan_id']! as String,
          p['extra_cost_day']! as String,
          currency: p['currency']! as String,
        );
      }
      final n = await tx.update(
        'personnel_payrolls_v1',
        {'status': 'approved'},
        where: "id=? AND farm_id=? AND status='draft'",
        whereArgs: [id, farmId],
      );
      if (n != 1) throw StateError('Payroll must be a draft in this farm.');
      if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
      await _audit(tx, farmId, id, 'payroll.approve', actorId);
    });
  }

  @override
  Future<void> cancelPayroll(
    String farmId,
    String id,
    String reason,
    String actorId,
  ) async {
    if (reason.trim().isEmpty) {
      throw const FormatException('Cancellation reason required.');
    }
    await database.transaction((tx) async {
      final stamp = scope?.live.stamp(scope!.opened);
      await checkRecord(tx, farmId, 'personnel_payrolls_v1', id);
      final n = await tx.update(
        'personnel_payrolls_v1',
        {'status': 'cancelled'},
        where: "id=? AND farm_id=? AND status='draft'",
        whereArgs: [id, farmId],
      );
      if (n != 1) throw StateError('Only draft payrolls may be cancelled.');
      await tx.update(
        'personnel_payroll_lines_v1',
        {'active': 0},
        where: 'payroll_id=?',
        whereArgs: [id],
      );
      if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
      await _audit(tx, farmId, id, 'payroll.cancel', actorId, reason);
    });
  }

  @override
  Future<void> recordPayment(
    String farmId,
    String id,
    String payrollId,
    String amount,
    String currency,
    String day,
    String note,
    String actorId,
  ) async {
    ExactDecimal.validatePrice(amount, currency);
    LaborMoney.date(day);
    if (id.trim().isEmpty ||
        ExactDecimal.parse(amount).coefficient <= BigInt.zero ||
        note.trim().isEmpty) {
      throw const FormatException('Payment and reference required.');
    }
    await database.transaction((tx) async {
      final stamp = scope?.live.stamp(scope!.opened);
      await checkRecord(tx, farmId, 'personnel_payrolls_v1', payrollId);
      final prior = await tx.query(
        'personnel_payments_v1',
        where: 'id=?',
        whereArgs: [id],
      );
      if (prior.isNotEmpty) {
        final p = prior.single;
        if (p['farm_id'] == farmId &&
            p['payroll_id'] == payrollId &&
            p['amount'] == amount &&
            p['currency'] == currency &&
            p['business_day'] == day &&
            p['note'] == note) {
          return;
        }
        throw StateError('Payment ID conflict.');
      }
      final payroll = await tx.query(
        'personnel_payrolls_v1',
        where: "id=? AND farm_id=? AND currency=? AND status='approved'",
        whereArgs: [payrollId, farmId, currency],
      );
      if (payroll.length != 1) {
        throw StateError('Approved payroll with matching currency required.');
      }
      final previous = await IntegrationCash.activePayments(
        tx,
        farmId,
        payroll: payrollId,
      );
      final paid = LaborMoney.sum([
        ...previous.map((p) => p['amount']! as String),
        amount,
      ]);
      if (ExactDecimal.parse(
            paid,
          ).compareTo(ExactDecimal.parse(payroll.single['net']! as String)) >
          0) {
        throw StateError('Payment exceeds outstanding salary.');
      }
      await tx.insert('personnel_payments_v1', {
        'id': id,
        'farm_id': farmId,
        'payroll_id': payrollId,
        'amount': amount,
        'currency': currency,
        'business_day': day,
        'note': note,
      });
      await IntegrationCash.salary(tx, {
        'id': id,
        'farm_id': farmId,
        'payroll_id': payrollId,
        'amount': amount,
        'currency': currency,
        'business_day': day,
        'note': note,
      }, actorId);
      if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
      await _audit(tx, farmId, id, 'payroll.payment', actorId, note);
    });
  }

  @override
  Future<List<PersonnelPlanChoice>> planChoices(String farmId) async {
    final rows = await database.rawQuery(
      "SELECT p.id,p.code,p.name,p.currency,p.starts_on,p.ends_on FROM production_plans_v1 p JOIN production_seasons_v2 s ON s.id=p.season_id AND s.farm_id=p.farm_id JOIN land_parcels l ON l.id=p.parcel_id AND l.farm_id=p.farm_id WHERE p.farm_id=? AND p.status='active' AND s.active=1 AND l.active=1 AND ${scope == null || scope!.farmWide ? '1' : "p.id IN (SELECT plan_id FROM production_labor_costs_v1 WHERE entry_id IN (SELECT id FROM personnel_entries_v1 WHERE ${visible('worker_id')}) UNION SELECT t.plan_id FROM production_plan_tasks_v1 t JOIN farm_tasks_v2 f ON f.id=t.id AND f.farm_id=t.farm_id WHERE ${visible('f.worker_resource_id')})"} ORDER BY p.code",
      [farmId],
    );
    return rows
        .map(
          (r) => PersonnelPlanChoice(
            r['id']! as String,
            '${r['code']} · ${r['name']}',
            r['currency']! as String,
            r['starts_on']! as String,
            r['ends_on']! as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<PersonnelTaskChoice>> taskChoices(String farmId) async {
    final rows = await database.rawQuery(
      'SELECT t.id,t.plan_id,f.title,f.worker_resource_id FROM production_plan_tasks_v1 t JOIN farm_tasks_v2 f ON f.id=t.id AND f.farm_id=t.farm_id WHERE t.farm_id=? AND ${visible('f.worker_resource_id')} ORDER BY f.due_at,t.id',
      [farmId],
    );
    return rows
        .map(
          (r) => PersonnelTaskChoice(
            r['id']! as String,
            r['plan_id']! as String,
            r['title']! as String,
            r['worker_resource_id'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<SalaryPayment>> payments(String farmId) async {
    final reversed = await IntegrationCash.reversed(database);
    final rows = await database.query(
      'personnel_payments_v1',
      where:
          'farm_id=? AND payroll_id IN (SELECT id FROM personnel_payrolls_v1 WHERE ${visible('worker_id')})',
      whereArgs: [farmId],
      orderBy: 'business_day,id',
    );
    return rows
        .map(
          (r) => SalaryPayment(
            id: r['id'] as String,
            payrollId: r['payroll_id'] as String,
            amount: r['amount'] as String,
            currency: r['currency'] as String,
            day: r['business_day'] as String,
            note: r['note'] as String,
            reversed: reversed.contains(r['id']),
          ),
        )
        .toList();
  }
}
