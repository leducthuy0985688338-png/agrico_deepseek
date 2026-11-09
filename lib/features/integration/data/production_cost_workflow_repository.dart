import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/production/source_governance.dart';
import '../../../core/periods/period_lock.dart';
import '../domain/production_cost_workflow.dart';
import '../../personnel/domain/personnel.dart' show LaborMoney, ExactDecimal;

class ProductionCostWorkflowRepository implements ProductionCostWorkflowStore {
  const ProductionCostWorkflowRepository(this.db);
  final Database db;
  static const policies = 'production_expense_policies_v2',
      costs = 'production_expense_costs_v2';
  static const tables = {policies, costs, ...SourceGovernance.tables};
  static Future<void> createSchema(DatabaseExecutor db) async {
    await SourceGovernance.createSchema(db);
    await db.execute('''CREATE TABLE IF NOT EXISTS $policies(
      id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,source_id TEXT NOT NULL UNIQUE REFERENCES trade_documents_v1(id),
      day TEXT NOT NULL,currency TEXT NOT NULL CHECK(currency IN ('VND','LAK')),
      driver TEXT NOT NULL CHECK(driver IN ('direct','area','machineMinutes','laborMinutes','approvedWeights')),
      base_units INTEGER NOT NULL CHECK(base_units>0),money_scale INTEGER NOT NULL CHECK(money_scale BETWEEN 0 AND 6),
      weights_json TEXT NOT NULL,source_digest TEXT NOT NULL)''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $costs(policy_id TEXT NOT NULL REFERENCES $policies(id),
      farm_id TEXT NOT NULL,plan_id TEXT NOT NULL REFERENCES production_plans_v1(id),
      parcel_id TEXT NOT NULL REFERENCES land_parcels(id),amount TEXT NOT NULL,
      currency TEXT NOT NULL CHECK(currency IN ('VND','LAK')),PRIMARY KEY(policy_id,plan_id))''',
    );
    for (final t in [policies, costs]) {
      for (final action in ['UPDATE', 'DELETE']) {
        await db.execute(
          "CREATE TRIGGER IF NOT EXISTS production_immutable_${t}_${action.toLowerCase()} BEFORE $action ON $t BEGIN SELECT RAISE(ABORT,'IMMUTABLE_COST_ALLOCATION'); END",
        );
      }
    }
    await db.execute(
      'CREATE TABLE IF NOT EXISTS production_cost_schema_v2(version INTEGER PRIMARY KEY,applied_at TEXT NOT NULL)',
    );
    await db.insert('production_cost_schema_v2', {
      'version': 1,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Object expenseSource(Map<String, Object?> row) =>
      SourceGovernance.expenseSource(row);
  static Object policyPayload(Map<String, Object?> row) =>
      SourceGovernance.policyPayload(row);
  static Future<Map<String, Object?>> one(
    DatabaseExecutor db,
    String table,
    String farm,
    String id,
  ) async {
    final rows = await db.query(
      table,
      where: 'farm_id=? AND id=?',
      whereArgs: [farm, id],
    );
    if (rows.length != 1) throw StateError('Source unavailable in this farm.');
    return rows.single;
  }

  static Future<void> validate(DatabaseExecutor db) async {
    await SourceGovernance.validate(
      db,
      allocationPayload: (r) async => policyPayload(
        await one(
          db,
          policies,
          r['farm_id'] as String,
          r['source_id'] as String,
        ),
      ),
    );
    if ((await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [policies],
    )).isEmpty) {
      return;
    }
    for (final p in await db.query(policies)) {
      final source = await one(
        db,
        'trade_documents_v1',
        p['farm_id'] as String,
        p['source_id'] as String,
      );
      if (p['source_digest'] !=
          SourceGovernance.digest(expenseSource(source))) {
        throw StateError('Expense source changed.');
      }
      final g = await SourceGovernance.get(
        db,
        p['farm_id'] as String,
        'expenseAllocation',
        p['id'] as String,
      );
      if (g == null) throw StateError('Allocation has no creator/version.');
      final weights = (jsonDecode(p['weights_json'] as String) as List)
          .map((r) => Map<String, Object?>.from(r as Map))
          .toList();
      ExpenseAllocationProposal(
        expenseId: p['source_id'] as String,
        driver: CostAllocationDriver.values.byName(p['driver'] as String),
        baseUnits: p['base_units'] as int,
        moneyScale: p['money_scale'] as int,
        weights: weights
            .map(
              (r) => CostAllocationWeight(
                r['planId'] as String,
                r['units'] as int,
                r['evidence'] as String,
              ),
            )
            .toList(),
      ).validate();
      final allocations = await db.query(
        costs,
        where: 'policy_id=?',
        whereArgs: [p['id']],
      );
      if (g['status'] == 'draft') {
        if (allocations.isNotEmpty) throw StateError('Draft policy has costs.');
        continue;
      }
      final expected = LaborMoney.allocate(
        source['total'] as String,
        weights.map((r) => r['units'] as int).toList(),
        p['base_units'] as int,
        p['money_scale'] as int,
      );
      if (allocations.length != weights.length) {
        throw StateError('Missing expense costs.');
      }
      for (var i = 0; i < weights.length; i++) {
        final a = allocations
            .where((r) => r['plan_id'] == weights[i]['planId'])
            .single;
        final plan = await one(
          db,
          'production_plans_v1',
          p['farm_id'] as String,
          a['plan_id'] as String,
        );
        if (a['farm_id'] != p['farm_id'] ||
            a['currency'] != p['currency'] ||
            a['amount'] != expected[i] ||
            a['parcel_id'] != plan['parcel_id']) {
          throw StateError('Expense allocation differs from approved policy.');
        }
      }
    }
  }

  static Future<Map<String, Object?>> destination(
    DatabaseExecutor tx,
    String farm,
    String id,
    String currency,
    String day,
  ) async {
    final p = await one(tx, 'production_plans_v1', farm, id);
    final parcel = await one(
      tx,
      'land_parcels',
      farm,
      p['parcel_id'] as String,
    );
    if (p['status'] != 'active' ||
        p['currency'] != currency ||
        parcel['active'] != 1 ||
        day.compareTo(p['starts_on'] as String) < 0 ||
        day.compareTo(p['ends_on'] as String) > 0) {
      throw StateError(
        'Eligible active plan, parcel, dates and currency required.',
      );
    }
    return p;
  }

  @override
  Future<void> approveMaterial(
    String farm,
    String id,
    int revision,
    String actor,
    void Function() checkAccess,
  ) => db.transaction((tx) async {
    checkAccess();
    final m = await one(tx, 'inventory_movements_v2', farm, id);
    final c = (await tx.query(
      'production_material_costs_v2',
      where: 'movement_id=? AND farm_id=?',
      whereArgs: [id, farm],
    )).single;
    if (m['kind'] != 'issue') throw StateError('Production issue required.');
    final day = LaborMoney.day(DateTime.parse(m['occurred_at'] as String));
    await destination(
      tx,
      farm,
      c['plan_id'] as String,
      c['currency'] as String,
      day,
    );
    await SourceGovernance.approve(
      tx,
      farm: farm,
      type: 'material',
      id: id,
      expectedRevision: revision,
      actor: actor,
      payload: SourceGovernance.material(m, c),
    );
    checkAccess();
  });
  @override
  Future<void> proposeExpense(
    String farm,
    ExpenseAllocationProposal proposal,
    String actor,
    void Function() checkAccess,
  ) => db.transaction((tx) async {
    checkAccess();
    proposal.validate();
    final source = await one(
      tx,
      'trade_documents_v1',
      farm,
      proposal.expenseId,
    );
    final body = jsonDecode(source['body'] as String) as Map;
    final sourceApproval = await SourceGovernance.get(
      tx,
      farm,
      'tradeExpense',
      proposal.expenseId,
    );
    if (sourceApproval?['status'] != 'approved' ||
        sourceApproval?['payload_digest'] !=
            SourceGovernance.digest(expenseSource(source))) {
      throw StateError('Approved native expense payload required.');
    }
    final treatment = body['expenseTreatment'];
    if (source['kind'] != 'expense' ||
        source['status'] != 'posted' ||
        !{'directProduction', 'commonProduction'}.contains(treatment) ||
        (treatment == 'directProduction') !=
            (proposal.driver == CostAllocationDriver.direct)) {
      throw StateError(
        'Posted production expense and explicit matching driver required.',
      );
    }
    if (treatment == 'directProduction' &&
        source['plan_id'] != proposal.weights.single.planId) {
      throw StateError('Direct destination differs from approved source.');
    }
    final amount = ExactDecimal.parse(source['total'] as String);
    if (amount.isNegative || amount.scale > proposal.moneyScale) {
      throw StateError('Source must already have approved money precision.');
    }
    for (final w in proposal.weights) {
      await destination(
        tx,
        farm,
        w.planId,
        source['currency'] as String,
        source['day'] as String,
      );
    }
    final row = <String, Object?>{
      'id': proposal.expenseId,
      'farm_id': farm,
      'source_id': proposal.expenseId,
      'day': source['day'],
      'currency': source['currency'],
      'driver': proposal.driver.name,
      'base_units': proposal.baseUnits,
      'money_scale': proposal.moneyScale,
      'weights_json': PeriodLock.encode(
        proposal.weights.map((w) => w.toJson()).toList(),
      ),
      'source_digest': SourceGovernance.digest(expenseSource(source)),
    };
    final old = await tx.query(
      policies,
      where: 'id=?',
      whereArgs: [proposal.expenseId],
    );
    if (old.isNotEmpty) {
      if (SourceGovernance.digest(policyPayload(old.single)) !=
          SourceGovernance.digest(policyPayload(row))) {
        throw StateError('Allocation identity conflict.');
      }
      checkAccess();
      return;
    }
    await tx.insert(policies, row);
    await SourceGovernance.register(
      tx,
      farm: farm,
      type: 'expenseAllocation',
      id: proposal.expenseId,
      day: source['day'] as String,
      actor: actor,
      payload: policyPayload(row),
    );
    checkAccess();
  });
  @override
  Future<void> approveExpense(
    String farm,
    String id,
    int revision,
    String actor,
    void Function() checkAccess,
  ) => db.transaction((tx) async {
    checkAccess();
    final policy = await one(tx, policies, farm, id);
    final source = await one(
      tx,
      'trade_documents_v1',
      farm,
      policy['source_id'] as String,
    );
    if (source['status'] != 'posted' ||
        policy['source_digest'] !=
            SourceGovernance.digest(expenseSource(source))) {
      throw StateError('Expense changed or not posted.');
    }
    final weights = (jsonDecode(policy['weights_json'] as String) as List)
        .map((r) => Map<String, Object?>.from(r as Map))
        .toList();
    final destinations = <String, Map<String, Object?>>{};
    for (final w in weights) {
      destinations[w['planId'] as String] = await destination(
        tx,
        farm,
        w['planId'] as String,
        policy['currency'] as String,
        policy['day'] as String,
      );
    }
    final metadata = await SourceGovernance.get(
      tx,
      farm,
      'expenseAllocation',
      id,
    );
    if (metadata?['status'] == 'approved') {
      if (metadata?['revision'] != revision + 1) {
        throw StateError('Stale approved configuration.');
      }
      checkAccess();
      return;
    }
    final amounts = LaborMoney.allocate(
      source['total'] as String,
      weights.map((w) => w['units'] as int).toList(),
      policy['base_units'] as int,
      policy['money_scale'] as int,
    );
    await SourceGovernance.approve(
      tx,
      farm: farm,
      type: 'expenseAllocation',
      id: id,
      expectedRevision: revision,
      actor: actor,
      payload: policyPayload(policy),
    );
    for (var i = 0; i < weights.length; i++) {
      final p = destinations[weights[i]['planId']]!;
      await tx.insert(costs, {
        'policy_id': id,
        'farm_id': farm,
        'plan_id': p['id'],
        'parcel_id': p['parcel_id'],
        'amount': amounts[i],
        'currency': source['currency'],
      });
    }
    checkAccess();
  });
}
