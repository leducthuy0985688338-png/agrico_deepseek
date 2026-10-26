import 'package:sqflite/sqflite.dart';

import '../../domain/entities/exact_decimal.dart';
import '../../domain/repositories/production_planning_repository.dart';

class SqliteProductionPlanningRepository
    implements ProductionPlanningRepository {
  const SqliteProductionPlanningRepository(this.database);
  final Database database;
  static const plansTable = 'production_plans_v1';
  static const tasksTable = 'production_plan_tasks_v1';
  static const sequenceTable = 'production_plan_sequences_v1';
  static const auditTable = 'production_plan_audit_v1';
  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS $plansTable (
      id TEXT PRIMARY KEY, farm_id TEXT NOT NULL, parcel_id TEXT NOT NULL REFERENCES land_parcels(id),
      season_id TEXT NOT NULL REFERENCES production_seasons_v2(id), code TEXT NOT NULL,
      name TEXT NOT NULL, crop TEXT NOT NULL, starts_on TEXT NOT NULL, ends_on TEXT NOT NULL,
      currency TEXT NOT NULL CHECK(currency IN ('VND','LAK')),
      material_budget TEXT NOT NULL, labor_budget TEXT NOT NULL, machine_budget TEXT NOT NULL,
      labor_hours TEXT NOT NULL, machine_shifts TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('draft','active','paused','completed','cancelled')),
      revision INTEGER NOT NULL DEFAULT 0, UNIQUE(farm_id,code))''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $tasksTable (
      id TEXT PRIMARY KEY REFERENCES farm_tasks_v2(id) ON DELETE RESTRICT, farm_id TEXT NOT NULL, plan_id TEXT NOT NULL REFERENCES $plansTable(id),
      stage TEXT NOT NULL, quantity TEXT NOT NULL, unit TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 0)''',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS $sequenceTable (
      farm_id TEXT NOT NULL, month TEXT NOT NULL, last_value INTEGER NOT NULL,
      PRIMARY KEY(farm_id,month))''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $auditTable (
      id INTEGER PRIMARY KEY, farm_id TEXT NOT NULL, entity_id TEXT NOT NULL,
      action TEXT NOT NULL, actor_id TEXT NOT NULL, occurred_at TEXT NOT NULL)''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_production_plans_farm ON $plansTable(farm_id,season_id,status)',
    );
    final core = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='farm_tasks_v2'",
    );
    if (core.isNotEmpty) {
      await db.execute(
        """CREATE TRIGGER IF NOT EXISTS production_plan_task_revision_v1
        AFTER UPDATE ON farm_tasks_v2
        WHEN EXISTS(SELECT 1 FROM $tasksTable WHERE id=NEW.id)
        BEGIN UPDATE $tasksTable SET revision=revision+1 WHERE id=NEW.id; END""",
      );
      await db.execute(
        """CREATE TRIGGER IF NOT EXISTS production_plan_task_guard_v1
        BEFORE UPDATE ON farm_tasks_v2
        WHEN EXISTS(SELECT 1 FROM $tasksTable WHERE id=OLD.id)
        AND NOT EXISTS(SELECT 1 FROM $tasksTable t JOIN $plansTable p ON p.id=t.plan_id
          JOIN production_seasons_v2 s ON s.id=p.season_id
          JOIN land_parcels l ON l.id=p.parcel_id
          WHERE t.id=OLD.id AND NEW.id=OLD.id AND NEW.farm_id=p.farm_id AND NEW.parcel_id=p.parcel_id
          AND s.active=1 AND l.active=1 AND p.status IN ('draft','active')
          AND (NEW.status=OLD.status OR p.status='active'))
        BEGIN SELECT RAISE(ABORT,'Linked production task is locked or has an invalid destination'); END""",
      );
    }
  }

  Future<void> _audit(
    Transaction tx,
    String farm,
    String id,
    String action,
    String actor,
  ) async {
    if (actor.trim().isEmpty) throw const FormatException('Actor required.');
    await tx.insert(auditTable, {
      'farm_id': farm,
      'entity_id': id,
      'action': action,
      'actor_id': actor,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static ProductionPlan planFromRow(Map<String, Object?> r) => ProductionPlan(
    id: r['id']! as String,
    farmId: r['farm_id']! as String,
    parcelId: r['parcel_id']! as String,
    seasonId: r['season_id']! as String,
    code: r['code']! as String,
    parcelCode: r['parcel_code'] as String?,
    seasonName: r['season_name'] as String?,
    name: r['name']! as String,
    crop: r['crop']! as String,
    startsOn: r['starts_on']! as String,
    endsOn: r['ends_on']! as String,
    currency: r['currency']! as String,
    materialBudget: r['material_budget']! as String,
    laborBudget: r['labor_budget']! as String,
    machineBudget: r['machine_budget']! as String,
    laborHours: r['labor_hours']! as String,
    machineShifts: r['machine_shifts']! as String,
    status: ProductionPlanStatus.values.byName(r['status']! as String),
    revision: r['revision']! as int,
  );
  @override
  Future<List<ProductionPlan>> productionPlans(
    String farmId,
  ) async => (await database.rawQuery(
    'SELECT plan.*, p.parcel_code, s.name AS season_name FROM $plansTable plan '
    'JOIN land_parcels p ON p.id=plan.parcel_id AND p.farm_id=plan.farm_id '
    'JOIN production_seasons_v2 s ON s.id=plan.season_id AND s.farm_id=plan.farm_id '
    'WHERE plan.farm_id=? ORDER BY plan.starts_on DESC,plan.code',
    [farmId],
  )).map(planFromRow).toList(growable: false);
  @override
  Future<void> createProductionPlan(ProductionPlan plan, String actorId) async {
    plan.validate();
    if (plan.code != null ||
        plan.revision != 0 ||
        plan.status != ProductionPlanStatus.draft) {
      throw const FormatException('New plans must be unnumbered drafts.');
    }
    await database.transaction((tx) async {
      final destination = await tx.rawQuery(
        'SELECT s.id FROM production_seasons_v2 s '
        'JOIN land_parcels p ON p.id=s.parcel_id AND p.farm_id=s.farm_id '
        "WHERE s.id=? AND s.farm_id=? AND p.id=? AND p.active=1 AND p.kind='fieldPlot' "
        'AND s.active=1 AND s.starts_on<=?',
        [plan.seasonId, plan.farmId, plan.parcelId, plan.startsOn],
      );
      if (destination.length != 1) {
        throw StateError('Invalid active parcel/season.');
      }
      final month = plan.startsOn.substring(0, 7).replaceAll('-', '');
      final rows = await tx.query(
        sequenceTable,
        where: 'farm_id=? AND month=?',
        whereArgs: [plan.farmId, month],
      );
      final next = rows.isEmpty ? 1 : (rows.single['last_value']! as int) + 1;
      await tx.insert(sequenceTable, {
        'farm_id': plan.farmId,
        'month': month,
        'last_value': next,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.insert(plansTable, {
        'id': plan.id,
        'farm_id': plan.farmId,
        'parcel_id': plan.parcelId,
        'season_id': plan.seasonId,
        'code': 'KH-$month-${next.toString().padLeft(3, '0')}',
        'name': plan.name.trim(),
        'crop': plan.crop.trim(),
        'starts_on': plan.startsOn,
        'ends_on': plan.endsOn,
        'currency': plan.currency,
        'material_budget': ExactDecimal.parse(plan.materialBudget).toString(),
        'labor_budget': ExactDecimal.parse(plan.laborBudget).toString(),
        'machine_budget': ExactDecimal.parse(plan.machineBudget).toString(),
        'labor_hours': ExactDecimal.parse(plan.laborHours).toString(),
        'machine_shifts': ExactDecimal.parse(plan.machineShifts).toString(),
        'status': 'draft',
        'revision': 0,
      });
      await _audit(tx, plan.farmId, plan.id, 'create', actorId);
    });
  }

  @override
  Future<void> changeProductionPlanStatus(
    String farmId,
    String planId,
    int revision,
    ProductionPlanStatus status,
    String actorId,
  ) async {
    await database.transaction((tx) async {
      final rows = await tx.query(
        plansTable,
        where: 'id=? AND farm_id=? AND revision=?',
        whereArgs: [planId, farmId, revision],
      );
      if (rows.length != 1) throw StateError('Stale or missing plan.');
      final old = ProductionPlanStatus.values.byName(
        rows.single['status']! as String,
      );
      final allowed = switch (old) {
        ProductionPlanStatus.draft => {
          ProductionPlanStatus.active,
          ProductionPlanStatus.cancelled,
        },
        ProductionPlanStatus.active => {
          ProductionPlanStatus.paused,
          ProductionPlanStatus.completed,
        },
        ProductionPlanStatus.paused => {
          ProductionPlanStatus.active,
          ProductionPlanStatus.cancelled,
        },
        _ => <ProductionPlanStatus>{},
      };
      if (!allowed.contains(status)) {
        throw StateError('Invalid plan transition.');
      }
      if (status == ProductionPlanStatus.active) {
        final valid = await tx.rawQuery(
          'SELECT s.id FROM production_seasons_v2 s JOIN land_parcels p '
          'ON p.id=s.parcel_id AND p.farm_id=s.farm_id '
          "WHERE s.id=? AND s.farm_id=? AND s.active=1 AND p.active=1 AND p.kind='fieldPlot'",
          [rows.single['season_id'], farmId],
        );
        if (valid.isEmpty) throw StateError('Season/parcel is closed.');
      }
      if (status == ProductionPlanStatus.completed &&
          (await tx.query(
            tasksTable,
            where:
                "plan_id=? AND farm_id=? AND id IN (SELECT id FROM farm_tasks_v2 WHERE status<>'completed')",
            whereArgs: [planId, farmId],
            limit: 1,
          )).isNotEmpty) {
        throw StateError('Complete plan tasks first.');
      }
      if (status == ProductionPlanStatus.completed ||
          status == ProductionPlanStatus.cancelled) {
        final tradeTables = await tx.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='trade_documents_v1'",
        );
        if (tradeTables.isNotEmpty &&
            (await tx.rawQuery(
              "SELECT id FROM trade_documents_v1 WHERE farm_id=? AND plan_id=? AND (status='draft' OR (?='cancelled' AND status='posted')) LIMIT 1",
              [farmId, planId, status.name],
            )).isNotEmpty) {
          throw StateError(
            'Resolve harvest drafts; plans with posted harvests cannot be cancelled.',
          );
        }
        final machineTables = await tx.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='machine_runs_v1'",
        );
        if (machineTables.isNotEmpty &&
            (await tx.rawQuery(
              "SELECT r.id FROM machine_runs_v1 r JOIN machine_costs_v1 c ON c.source_id=r.id AND c.farm_id=r.farm_id WHERE c.plan_id=? AND c.farm_id=? AND r.status='draft' LIMIT 1",
              [planId, farmId],
            )).isNotEmpty) {
          throw StateError(
            'Approve or void machine logs before closing the plan.',
          );
        }
        final tables = await tx.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='personnel_entries_v1'",
        );
        if (tables.isNotEmpty) {
          final pending = await tx.rawQuery(
            "SELECT e.id FROM personnel_entries_v1 e JOIN production_labor_costs_v1 c ON c.entry_id=e.id WHERE c.plan_id=? AND c.farm_id=? AND e.status='draft' LIMIT 1",
            [planId, farmId],
          );
          final pendingPayroll = await tx.query(
            'personnel_payrolls_v1',
            columns: ['id'],
            where: "adjustment_plan_id=? AND farm_id=? AND status='draft'",
            whereArgs: [planId, farmId],
            limit: 1,
          );
          if (pendingPayroll.isNotEmpty) {
            throw StateError(
              'Approve or cancel payroll allocations before closing the plan.',
            );
          }
          if (pending.isNotEmpty) {
            throw StateError(
              'Approve or void draft labor entries before closing the plan.',
            );
          }
        }
      }
      await tx.update(
        plansTable,
        {'status': status.name, 'revision': revision + 1},
        where: 'id=? AND farm_id=? AND revision=?',
        whereArgs: [planId, farmId, revision],
      );
      await _audit(tx, farmId, planId, '${old.name}->${status.name}', actorId);
    });
  }

  @override
  Future<List<ProductionPlanTask>> productionPlanTasks(String farmId) async {
    final core = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='farm_tasks_v2'",
    );
    if (core.isEmpty) return [];
    final rows = await database.rawQuery(
      'SELECT t.*, f.title, f.status, f.due_at FROM $tasksTable t JOIN farm_tasks_v2 f '
      'ON f.id=t.id AND f.farm_id=t.farm_id WHERE t.farm_id=? ORDER BY f.due_at,t.id',
      [farmId],
    );
    return rows
        .map(
          (r) => ProductionPlanTask(
            id: r['id']! as String,
            farmId: r['farm_id']! as String,
            planId: r['plan_id']! as String,
            title: r['title']! as String,
            stage: r['stage']! as String,
            quantity: r['quantity']! as String,
            unit: r['unit']! as String,
            completed: r['status'] == 'completed',
            dueOn: DateTime.parse(r['due_at']! as String)
                .toUtc()
                .add(const Duration(hours: 7))
                .toIso8601String()
                .substring(0, 10),
            revision: r['revision']! as int,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> createProductionPlanTask(
    ProductionPlanTask task,
    String actorId,
  ) async {
    task.validate();
    if (task.completed || task.revision != 0) {
      throw const FormatException('New task must be pending.');
    }
    await database.transaction((tx) async {
      final plan = await tx.query(
        plansTable,
        where: "id=? AND farm_id=? AND status IN ('draft','active')",
        whereArgs: [task.planId, task.farmId],
      );
      if (plan.length != 1) throw StateError('Plan does not accept tasks.');
      final due = task.dueOn ?? plan.single['ends_on']! as String;
      if (due.compareTo(plan.single['starts_on']! as String) < 0 ||
          due.compareTo(plan.single['ends_on']! as String) > 0) {
        throw const FormatException('Task date must be within plan dates.');
      }
      await tx.insert('farm_tasks_v2', {
        'id': task.id,
        'farm_id': task.farmId,
        'title': task.title.trim(),
        'description': task.stage.trim(),
        'status': 'pending',
        'due_at': DateTime.parse(
          '${due}T00:00:00+07:00',
        ).toUtc().toIso8601String(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'parcel_id': plan.single['parcel_id'],
        'worker_resource_id': null,
        'machine_resource_id': null,
      });
      await tx.insert(tasksTable, {
        'id': task.id,
        'farm_id': task.farmId,
        'plan_id': task.planId,
        'stage': task.stage.trim(),
        'quantity': ExactDecimal.parse(task.quantity).toString(),
        'unit': task.unit.trim(),
        'revision': 0,
      });
      await _audit(tx, task.farmId, task.id, 'task.create', actorId);
    });
  }

  @override
  Future<void> completeProductionPlanTask(
    String farmId,
    String taskId,
    int revision,
    bool completed,
    String actorId,
  ) async {
    await database.transaction((tx) async {
      final rows = await tx.rawQuery(
        'SELECT t.id FROM $tasksTable t JOIN $plansTable p ON p.id=t.plan_id AND p.farm_id=t.farm_id '
        "WHERE t.id=? AND t.farm_id=? AND t.revision=? AND p.status='active'",
        [taskId, farmId, revision],
      );
      if (rows.length != 1) {
        throw StateError('Active plan and current task revision required.');
      }
      final changed = await tx.update(
        'farm_tasks_v2',
        {'status': completed ? 'completed' : 'pending'},
        where: 'id=? AND farm_id=?',
        whereArgs: [taskId, farmId],
      );
      if (changed != 1) throw StateError('Shared task missing.');
      await _audit(
        tx,
        farmId,
        taskId,
        completed ? 'task.complete' : 'task.reopen',
        actorId,
      );
    });
  }
}
