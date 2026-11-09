import 'dart:convert';
import '../../../core/production/source_governance.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/permissions/authorization.dart';
import '../../../core/permissions/operation_scope.dart';
import '../../integration/data/integration_cash.dart';
import '../domain/personnel.dart';

/// Corrections and refunds append their own sources; original payroll and
/// attendance snapshots are never rewritten.
class SqlitePayrollAdjustments implements PayrollAdjustmentRepository {
  const SqlitePayrollAdjustments(this.db, {this.scope});
  final Database db;
  final OperationScope? scope;
  static const adjustments = 'personnel_payroll_adjustments_v1',
      costs = 'personnel_payroll_adjustment_costs_v1',
      sequences = 'personnel_payroll_adjustment_sequences_v1',
      refunds = 'personnel_payroll_refunds_v1';
  static const tables = {adjustments, costs, sequences, refunds};
  static Future<bool> enabled(DatabaseExecutor db) async => (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
    [adjustments],
  )).isNotEmpty;
  static Future<void> createSchema(DatabaseExecutor db) async {
    await SourceGovernance.createSchema(db);
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $adjustments(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,payroll_id TEXT NOT NULL REFERENCES personnel_payrolls_v1(id),code TEXT NOT NULL,currency TEXT NOT NULL CHECK(currency IN ('VND','LAK')),day TEXT NOT NULL,delta TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('earnings','deduction')),reason TEXT NOT NULL,expected_revision INTEGER NOT NULL CHECK(expected_revision>=0),before_net TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN ('draft','approved','cancelled')),creator TEXT NOT NULL,created_at TEXT NOT NULL,approver TEXT,approved_at TEXT,approved_revision INTEGER,UNIQUE(farm_id,code),UNIQUE(payroll_id,approved_revision))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $costs(adjustment_id TEXT NOT NULL REFERENCES $adjustments(id),farm_id TEXT NOT NULL,plan_id TEXT NOT NULL REFERENCES production_plans_v1(id),amount TEXT NOT NULL,PRIMARY KEY(adjustment_id,plan_id))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $sequences(farm_id TEXT NOT NULL,month TEXT NOT NULL,last_value INTEGER NOT NULL CHECK(last_value>0),PRIMARY KEY(farm_id,month))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $refunds(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,payroll_id TEXT NOT NULL REFERENCES personnel_payrolls_v1(id),amount TEXT NOT NULL,currency TEXT NOT NULL CHECK(currency IN ('VND','LAK')),day TEXT NOT NULL,reason TEXT NOT NULL,actor TEXT NOT NULL,created_at TEXT NOT NULL,finance_id TEXT NOT NULL UNIQUE REFERENCES finance_documents_v2(id),reverses_id TEXT UNIQUE REFERENCES $refunds(id),event_revision INTEGER NOT NULL CHECK(event_revision>0),basis TEXT NOT NULL,UNIQUE(payroll_id,event_revision))''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payroll_adjustments_scope_v1 ON $adjustments(farm_id,payroll_id,status,day)',
    );
  }

  static Future<List<Map<String, Object?>>> approved(
    DatabaseExecutor db,
    String payroll, {
    String? through,
  }) async => await enabled(db)
      ? db.query(
          adjustments,
          where:
              "payroll_id=? AND status='approved'${through == null ? '' : ' AND day<=?'}",
          whereArgs: [payroll, if (through != null) through],
          orderBy: 'approved_revision',
        )
      : [];
  static Future<int> revision(DatabaseExecutor db, String payroll) async =>
      (await approved(db, payroll)).length;
  static Future<String> effectiveNet(
    DatabaseExecutor db,
    Map<String, Object?> payroll, {
    String? through,
  }) async => LaborMoney.sum([
    payroll['net']! as String,
    ...(await approved(
      db,
      payroll['id']! as String,
      through: through,
    )).map((r) => r['delta']! as String),
  ]);
  static Future<List<Map<String, Object?>>> refundRows(
    DatabaseExecutor db,
    String payroll,
  ) async => await enabled(db)
      ? db.query(
          refunds,
          where: 'payroll_id=?',
          whereArgs: [payroll],
          orderBy: 'event_revision',
        )
      : [];
  static String refundTotal(Iterable<Map<String, Object?>> rows) =>
      LaborMoney.sum(
        rows.map(
          (r) => r['reverses_id'] == null
              ? r['amount']! as String
              : LaborMoney.minus('0', r['amount']! as String),
        ),
      );
  static Future<bool> linkedPayment(
    DatabaseExecutor db,
    Map<String, Object?> payment,
  ) async {
    final links = await db.query(
      'integration_cash_links_v1',
      where: 'source_id=? AND farm_id=?',
      whereArgs: [payment['id'], payment['farm_id']],
    );
    if (links.length != 1) return false;
    final cash = await db.query(
      'finance_documents_v2',
      where: 'id=? AND organization_id=?',
      whereArgs: [links.single['finance_id'], payment['farm_id']],
    );
    return cash.length == 1 &&
        cash.single['kind'] == 'CHI' &&
        cash.single['currency'] == payment['currency'] &&
        IntegrationCash.amount(cash.single) ==
            ExactDecimal.parse(payment['amount']! as String).toString() &&
        (cash.single['occurred_at']! as String).substring(0, 10) ==
            payment['business_day'];
  }

  static Future<String> paid(
    DatabaseExecutor db,
    String farm,
    String payroll,
  ) async => LaborMoney.minus(
    LaborMoney.sum(
      (await IntegrationCash.activePayments(
        db,
        farm,
        payroll: payroll,
      )).map((r) => r['amount']! as String),
    ),
    refundTotal(await refundRows(db, payroll)),
  );
  static Future<String> maximumNet(
    DatabaseExecutor db,
    Map<String, Object?> p,
  ) async {
    var current = ExactDecimal.parse(p['net']! as String), maximum = current;
    for (final r in await approved(db, p['id']! as String)) {
      current = current + ExactDecimal.parse(r['delta']! as String);
      if (current.compareTo(maximum) > 0) maximum = current;
    }
    return maximum.toString();
  }

  static Future<String> latestDay(
    DatabaseExecutor db,
    Map<String, Object?> p,
  ) async {
    final days = [
      p['extra_cost_day']! as String,
      ...(await approved(
        db,
        p['id']! as String,
      )).map((r) => r['day']! as String),
      ...(await db.query(
        'personnel_payments_v1',
        where: 'payroll_id=?',
        whereArgs: [p['id']],
      )).map((r) => r['business_day']! as String),
      ...(await refundRows(
        db,
        p['id']! as String,
      )).map((r) => r['day']! as String),
    ];
    if (await IntegrationCash.enabled(db)) {
      days.addAll(
        (await db.rawQuery(
          'SELECT r.day FROM integration_salary_reversals_v1 r JOIN personnel_payments_v1 p ON p.id=r.payment_id WHERE p.payroll_id=?',
          [p['id']],
        )).map((r) => r['day']! as String),
      );
    }
    return (days..sort()).last;
  }

  static void postingDay(String day) {
    LaborMoney.date(day);
    if (day.compareTo(LaborMoney.day(DateTime.now())) > 0) {
      throw const FormatException('Future posting is not allowed.');
    }
  }

  Future<Map<String, Object?>> payroll(
    DatabaseExecutor tx,
    String farm,
    String id,
  ) async {
    final rows = await tx.query(
      'personnel_payrolls_v1',
      where: 'farm_id=? AND id=?',
      whereArgs: [farm, id],
    );
    if (rows.length != 1) throw StateError('Payroll unavailable.');
    final p = rows.single;
    if (scope != null) {
      final people = await tx.query(
        'personnel_profiles_v1',
        columns: ['department_id'],
        where: 'worker_id=? AND farm_id=?',
        whereArgs: [p['worker_id'], farm],
      );
      scope!.require(
        ResourceContext(
          farmId: farm,
          departmentId: people.isEmpty
              ? null
              : people.single['department_id'] as String?,
        ),
      );
    }
    return p;
  }

  String visible(String payrollColumn) => scope == null || scope!.farmWide
      ? '1'
      : "$payrollColumn IN (SELECT p.id FROM personnel_payrolls_v1 p JOIN personnel_profiles_v1 profile ON profile.worker_id=p.worker_id AND profile.farm_id=p.farm_id WHERE p.farm_id=${OperationScope.quote(scope!.subject.farmId)} AND ${scope!.sql(department: 'profile.department_id')})";
  static Future<Map<String, String>> sourceCosts(
    DatabaseExecutor tx,
    Map<String, Object?> p,
  ) async {
    final result = <String, String>{};
    final rows = await tx.rawQuery(
      'SELECT c.plan_id,c.amount FROM production_labor_costs_v1 c JOIN personnel_payroll_lines_v1 l ON l.entry_id=c.entry_id JOIN personnel_entries_v1 e ON e.id=c.entry_id AND e.farm_id=c.farm_id WHERE l.payroll_id=? AND l.active=1 AND c.farm_id=? AND e.machine_id IS NULL',
      [p['id'], p['farm_id']],
    );
    for (final r in rows) {
      result[r['plan_id']! as String] = LaborMoney.sum([
        result[r['plan_id']] ?? '0',
        r['amount']! as String,
      ]);
    }
    if (p['adjustment_plan_id'] != null) {
      final id = p['adjustment_plan_id']! as String;
      result[id] = LaborMoney.sum([
        result[id] ?? '0',
        p['allowance']! as String,
        p['bonus']! as String,
      ]);
    }
    return result;
  }

  static Future<void> validateAllocations(
    DatabaseExecutor tx,
    Map<String, Object?> p,
    PayrollAdjustmentDraft d, {
    int? throughRevision,
  }) async {
    final source = await sourceCosts(tx, p);
    for (final a in d.allocations) {
      final plan = await tx.query(
        'production_plans_v1',
        where: 'id=? AND farm_id=? AND currency=?',
        whereArgs: [a.planId, p['farm_id'], p['currency']],
      );
      if (!source.containsKey(a.planId) || plan.length != 1) {
        throw StateError(
          'Cost correction must reference an original payroll plan.',
        );
      }
      final previous = await tx.rawQuery(
        'SELECT c.amount FROM $costs c JOIN $adjustments a ON a.id=c.adjustment_id WHERE a.payroll_id=? AND a.status=\'approved\' AND c.plan_id=?${throughRevision == null ? '' : ' AND a.approved_revision<=?'}',
        [p['id'], a.planId, if (throughRevision != null) throughRevision],
      );
      final balance = LaborMoney.sum([
        source[a.planId]!,
        ...previous.map((r) => r['amount']! as String),
        a.amount,
      ]);
      if (ExactDecimal.parse(balance).isNegative) {
        throw StateError(
          'Correction exceeds attributed production labor cost.',
        );
      }
    }
    final prior = await tx.query(
      adjustments,
      where:
          "payroll_id=? AND status='approved'${throughRevision == null ? '' : ' AND approved_revision<=?'}",
      whereArgs: [p['id'], if (throughRevision != null) throughRevision],
    );
    final priorCosts = await tx.rawQuery(
      "SELECT c.amount FROM $costs c JOIN $adjustments a ON a.id=c.adjustment_id WHERE a.payroll_id=? AND a.status='approved'${throughRevision == null ? '' : ' AND a.approved_revision<=?'}",
      [p['id'], if (throughRevision != null) throughRevision],
    );
    final gross = LaborMoney.sum([
      p['regular']! as String,
      p['overtime']! as String,
      p['piece']! as String,
      p['allowance']! as String,
      p['bonus']! as String,
      ...prior
          .where((r) => r['kind'] == 'earnings')
          .map((r) => r['delta']! as String),
      if (d.kind == PayrollAdjustmentKind.earnings) d.delta,
    ]);
    final net = LaborMoney.sum([
      p['net']! as String,
      ...prior.map((r) => r['delta']! as String),
      d.delta,
    ]);
    final allocated = LaborMoney.sum([
      ...source.values,
      ...priorCosts.map((r) => r['amount']! as String),
      d.costDelta,
    ]);
    if (ExactDecimal.parse(gross).isNegative ||
        ExactDecimal.parse(net).isNegative ||
        ExactDecimal.parse(net).compareTo(ExactDecimal.parse(gross)) > 0 ||
        ExactDecimal.parse(allocated).compareTo(ExactDecimal.parse(gross)) >
            0) {
      throw StateError('Corrected salary components do not balance.');
    }
  }

  static Future<void> audit(
    Transaction tx,
    String farm,
    String id,
    String action,
    String actor,
    String reason,
  ) async {
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

  static PayrollAdjustmentRecord fromRow(
    Map<String, Object?> r,
    List<Map<String, Object?>> lines,
  ) => PayrollAdjustmentRecord(
    draft: PayrollAdjustmentDraft(
      id: r['id']! as String,
      farmId: r['farm_id']! as String,
      payrollId: r['payroll_id']! as String,
      currency: r['currency']! as String,
      day: r['day']! as String,
      delta: r['delta']! as String,
      reason: r['reason']! as String,
      expectedRevision: r['expected_revision']! as int,
      kind: PayrollAdjustmentKind.values.byName(r['kind']! as String),
      allocations: lines
          .where((l) => l['adjustment_id'] == r['id'])
          .map(
            (l) => PayrollCostAdjustment(
              l['plan_id']! as String,
              l['amount']! as String,
            ),
          )
          .toList(),
    ),
    code: r['code']! as String,
    status: r['status']! as String,
    creator: r['creator']! as String,
    createdAt: r['created_at']! as String,
    beforeNet: r['before_net']! as String,
    approver: r['approver'] as String?,
    approvedAt: r['approved_at'] as String?,
    approvedRevision: r['approved_revision'] as int?,
  );
  @override
  Future<List<PersonnelPlanChoice>> payrollAdjustmentPlans(
    String farmId,
    String payrollId,
  ) async {
    final p = await payroll(db, farmId, payrollId);
    final sources = await sourceCosts(db, p);
    final result = <PersonnelPlanChoice>[];
    for (final id in sources.keys) {
      final rows = await db.query(
        'production_plans_v1',
        where: 'id=? AND farm_id=?',
        whereArgs: [id, farmId],
      );
      if (rows.length == 1) {
        final r = rows.single;
        result.add(
          PersonnelPlanChoice(
            id,
            '${r['code']} · ${r['name']}',
            r['currency']! as String,
            r['starts_on']! as String,
            r['ends_on']! as String,
          ),
        );
      }
    }
    return result;
  }

  @override
  Future<List<PayrollAdjustmentRecord>> payrollAdjustments(
    String farmId,
  ) async {
    final rows = await db.query(
      adjustments,
      where: 'farm_id=? AND ${visible('payroll_id')}',
      whereArgs: [farmId],
      orderBy: 'day,code',
    );
    final lines = await db.query(
      costs,
      where:
          'farm_id=? AND adjustment_id IN (SELECT id FROM $adjustments WHERE ${visible('payroll_id')})',
      whereArgs: [farmId],
    );
    return rows.map((r) => fromRow(r, lines)).toList();
  }

  @override
  Future<void> createPayrollAdjustment(
    PayrollAdjustmentDraft d,
    String actor,
  ) async {
    d.validate();
    postingDay(d.day);
    await db.transaction((tx) async {
      final stamp = scope?.live.stamp(scope!.opened);
      final p = await payroll(tx, d.farmId, d.payrollId);
      if (p['status'] != 'approved' || p['currency'] != d.currency) {
        throw StateError('Approved payroll and matching currency required.');
      }
      final prior = await tx.query(
        adjustments,
        where: 'id=?',
        whereArgs: [d.id],
      );
      if (prior.isNotEmpty) {
        final r = fromRow(
          prior.single,
          await tx.query(costs, where: 'adjustment_id=?', whereArgs: [d.id]),
        );
        if (jsonEncode(canonical(r.draft)) == jsonEncode(canonical(d)) &&
            r.creator == actor) {
          return;
        }
        throw StateError('Adjustment identity conflict.');
      }
      if (d.expectedRevision != await revision(tx, d.payrollId) ||
          d.day.compareTo(await latestDay(tx, p)) < 0) {
        throw StateError('Stale payroll or posting date.');
      }
      final before = await effectiveNet(tx, p);
      if (ExactDecimal.parse(LaborMoney.sum([before, d.delta])).isNegative) {
        throw StateError('Corrected payroll cannot be negative.');
      }
      await validateAllocations(tx, p, d);
      final month = d.day.substring(0, 7).replaceAll('-', '');
      final counters = await tx.query(
        sequences,
        where: 'farm_id=? AND month=?',
        whereArgs: [d.farmId, month],
      );
      final n = counters.isEmpty
          ? 1
          : (counters.single['last_value']! as int) + 1;
      await tx.insert(sequences, {
        'farm_id': d.farmId,
        'month': month,
        'last_value': n,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.insert(adjustments, {
        'id': d.id,
        'farm_id': d.farmId,
        'payroll_id': d.payrollId,
        'code': 'DCL-$month-${n.toString().padLeft(3, '0')}',
        'currency': d.currency,
        'day': d.day,
        'delta': ExactDecimal.parse(d.delta).toString(),
        'kind': d.kind.name,
        'reason': d.reason.trim(),
        'expected_revision': d.expectedRevision,
        'before_net': before,
        'status': 'draft',
        'creator': actor,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      for (final a in d.allocations) {
        await tx.insert(costs, {
          'adjustment_id': d.id,
          'farm_id': d.farmId,
          'plan_id': a.planId,
          'amount': ExactDecimal.parse(a.amount).toString(),
        });
      }
      await SourceGovernance.register(
        tx,
        farm: d.farmId,
        type: 'payrollCorrection',
        id: d.id,
        day: d.day,
        actor: actor,
        payload: await SourceGovernance.nativePayload(
          tx,
          'payrollCorrection',
          d.id,
        ),
      );
      await audit(
        tx,
        d.farmId,
        d.id,
        'payroll.adjustment.create',
        actor,
        d.reason,
      );
      if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
    });
  }

  static Map<String, Object?> canonical(PayrollAdjustmentDraft d) => {
    'id': d.id,
    'farm': d.farmId,
    'payroll': d.payrollId,
    'currency': d.currency,
    'day': d.day,
    'delta': ExactDecimal.parse(d.delta).toString(),
    'reason': d.reason.trim(),
    'revision': d.expectedRevision,
    'kind': d.kind.name,
    'allocations': (d.allocations.map((a) => a.toJson()).toList()
      ..sort(
        (a, b) => (a['planId']! as String).compareTo(b['planId']! as String),
      )),
  };
  @override
  Future<void> approvePayrollAdjustment(
    String farmId,
    String id,
    String actor,
  ) async {
    await db.transaction((tx) async {
      final stamp = scope?.live.stamp(scope!.opened);
      final rows = await tx.query(
        adjustments,
        where: 'id=? AND farm_id=?',
        whereArgs: [id, farmId],
      );
      if (rows.length != 1) throw StateError('Adjustment unavailable.');
      final record = fromRow(
        rows.single,
        await tx.query(costs, where: 'adjustment_id=?', whereArgs: [id]),
      );
      final d = record.draft;
      final p = await payroll(tx, farmId, d.payrollId);
      if (record.status == 'approved') return;
      if (record.status != 'draft' ||
          p['status'] != 'approved' ||
          d.expectedRevision != await revision(tx, d.payrollId) ||
          d.day.compareTo(await latestDay(tx, p)) < 0 ||
          record.beforeNet != await effectiveNet(tx, p)) {
        throw StateError(
          'Stale adjustment; create a new proposal after reviewing the current payroll.',
        );
      }
      d.validate();
      postingDay(d.day);
      if (ExactDecimal.parse(
        LaborMoney.sum([record.beforeNet, d.delta]),
      ).isNegative) {
        throw StateError('Negative payroll.');
      }
      await validateAllocations(tx, p, d);
      await tx.update(
        adjustments,
        {
          'status': 'approved',
          'approver': actor,
          'approved_at': DateTime.now().toUtc().toIso8601String(),
          'approved_revision': d.expectedRevision + 1,
        },
        where: "id=? AND status='draft'",
        whereArgs: [id],
      );
      await audit(
        tx,
        farmId,
        id,
        'payroll.adjustment.approve',
        actor,
        d.reason,
      );
      await SourceGovernance.approve(
        tx,
        farm: farmId,
        type: 'payrollCorrection',
        id: id,
        expectedRevision: 1,
        actor: actor,
        payload: await SourceGovernance.nativePayload(
          tx,
          'payrollCorrection',
          id,
        ),
      );
      if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
    });
  }

  @override
  Future<void> cancelPayrollAdjustment(
    String farmId,
    String id,
    String actor,
  ) async {
    await db.transaction((tx) async {
      final stamp = scope?.live.stamp(scope!.opened);
      final rows = await tx.query(
        adjustments,
        where: 'id=? AND farm_id=?',
        whereArgs: [id, farmId],
      );
      if (rows.length != 1) throw StateError('Adjustment unavailable.');
      await payroll(tx, farmId, rows.single['payroll_id']! as String);
      if (rows.single['status'] == 'cancelled') return;
      if (rows.single['status'] != 'draft') {
        throw StateError(
          'Approved corrections must be countered by a new adjustment.',
        );
      }
      await tx.update(
        adjustments,
        {'status': 'cancelled'},
        where: 'id=?',
        whereArgs: [id],
      );
      await audit(
        tx,
        farmId,
        id,
        'payroll.adjustment.cancel',
        actor,
        rows.single['reason']! as String,
      );
      if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
    });
  }

  @override
  Future<List<PayrollRefund>> payrollRefunds(String farmId) async =>
      (await db.query(
            refunds,
            where: 'farm_id=? AND ${visible('payroll_id')}',
            whereArgs: [farmId],
            orderBy: 'day,event_revision',
          ))
          .map(
            (r) => PayrollRefund(
              id: r['id']! as String,
              payrollId: r['payroll_id']! as String,
              amount: r['amount']! as String,
              currency: r['currency']! as String,
              day: r['day']! as String,
              reason: r['reason']! as String,
              actor: r['actor']! as String,
              financeId: r['finance_id']! as String,
              reversesId: r['reverses_id'] as String?,
            ),
          )
          .toList();
  @override
  Future<void> refundPayroll(
    String farmId,
    String id,
    String payrollId,
    String amount,
    String currency,
    String day,
    String reason,
    String actor, {
    String? reversesId,
  }) async {
    postingDay(day);
    ExactDecimal.validatePrice(amount, currency);
    if ([id, reason, actor].any((v) => v.trim().isEmpty) ||
        reason.length > 2000 ||
        ExactDecimal.parse(amount).coefficient <= BigInt.zero) {
      throw const FormatException('Positive refund and reason required.');
    }
    await db.transaction((tx) async {
      final stamp = scope?.live.stamp(scope!.opened);
      final p = await payroll(tx, farmId, payrollId);
      if (p['status'] != 'approved' ||
          p['currency'] != currency ||
          !await IntegrationCash.enabled(tx)) {
        throw StateError(
          'Approved payroll with a connected cash ledger required.',
        );
      }
      final existing = await tx.query(refunds, where: 'id=?', whereArgs: [id]);
      if (existing.isNotEmpty) {
        final r = existing.single;
        if (r['farm_id'] == farmId &&
            r['payroll_id'] == payrollId &&
            r['amount'] == ExactDecimal.parse(amount).toString() &&
            r['currency'] == currency &&
            r['day'] == day &&
            r['reason'] == reason.trim() &&
            r['actor'] == actor &&
            r['reverses_id'] == reversesId) {
          return;
        }
        throw StateError('Refund identity conflict.');
      }
      if (day.compareTo(await latestDay(tx, p)) < 0) {
        throw StateError('Refund date precedes the current payroll ledger.');
      }
      final active = await IntegrationCash.activePayments(
        tx,
        farmId,
        payroll: payrollId,
      );
      for (final payment in active) {
        if (!await linkedPayment(tx, payment))
          throw StateError(
            'Link original salary payments to cash before refunding.',
          );
      }
      final previous = await refundRows(tx, payrollId);
      final netPaid = await paid(tx, farmId, payrollId),
          net = await effectiveNet(tx, p);
      if (reversesId == null) {
        if (ExactDecimal.parse(
              amount,
            ).compareTo(ExactDecimal.parse(LaborMoney.minus(netPaid, net))) >
            0) {
          throw StateError('Refund exceeds employee overpayment.');
        }
      } else {
        final original = previous.where((r) => r['id'] == reversesId).toList();
        if (original.length != 1 ||
            original.single['reverses_id'] != null ||
            original.single['amount'] !=
                ExactDecimal.parse(amount).toString() ||
            previous.any((r) => r['reverses_id'] == reversesId)) {
          throw StateError('Original refund cannot be reversed.');
        }
        if (ExactDecimal.parse(
              LaborMoney.sum([netPaid, amount]),
            ).compareTo(ExactDecimal.parse(await maximumNet(tx, p))) >
            0) {
          throw StateError(
            'Reverse dependent salary payments before reversing this refund.',
          );
        }
      }
      final basis = {
        'adjustmentRevision': await revision(tx, payrollId),
        'net': net,
        'paid': netPaid,
        'paymentIds': active.map((r) => r['id']).toList(),
      };
      final finance = 'integrated:salary-refund:$id';
      await IntegrationCash.write(
        tx,
        id: finance,
        farm: farmId,
        day: day,
        amountText: amount,
        currency: currency,
        category: reversesId == null
            ? 'INTEGRATED_PAYROLL_REFUND'
            : 'INTEGRATED_PAYROLL_REFUND_REVERSAL',
        note: '${p['code']} · $reason',
        receipt: reversesId == null,
      );
      await tx.insert(refunds, {
        'id': id,
        'farm_id': farmId,
        'payroll_id': payrollId,
        'amount': ExactDecimal.parse(amount).toString(),
        'currency': currency,
        'day': day,
        'reason': reason.trim(),
        'actor': actor,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'finance_id': finance,
        'reverses_id': reversesId,
        'event_revision': previous.length + 1,
        'basis': jsonEncode(basis),
      });
      await audit(
        tx,
        farmId,
        id,
        reversesId == null ? 'payroll.refund' : 'payroll.refund.reverse',
        actor,
        reason,
      );
      if (stamp != null) scope!.live.requireStamp(scope!.opened, stamp);
    });
  }

  @override
  Future<List<ProductionLaborCost>> payrollAdjustmentCosts(
    String farmId,
  ) async =>
      (await db.rawQuery(
            "SELECT c.*,a.payroll_id,a.day,a.currency FROM $costs c JOIN $adjustments a ON a.id=c.adjustment_id AND a.farm_id=c.farm_id WHERE a.status='approved' AND a.farm_id=? AND ${visible('a.payroll_id')}",
            [farmId],
          ))
          .map(
            (r) => ProductionLaborCost(
              entryId:
                  'payroll-adjustment:${r['adjustment_id']}:${r['plan_id']}',
              planId: r['plan_id']! as String,
              currency: r['currency']! as String,
              amount: r['amount']! as String,
              businessDay: r['day']! as String,
              regularMinutes: 0,
              overtimeMinutes: 0,
            ),
          )
          .toList();
  static Future<void> validate(DatabaseExecutor db) async {
    if (!await enabled(db)) return;
    final all = await db.query(adjustments),
        lines = await db.query(costs),
        allRefunds = await db.query(refunds);
    final payrolls = {
      for (final p in await db.query('personnel_payrolls_v1')) p['id']: p,
    };
    final originals = {
      for (final p in await db.query('personnel_payments_v1')) p['id']: p,
    };
    for (final p in payrolls.values) {
      final approvedRows =
          all
              .where(
                (r) => r['payroll_id'] == p['id'] && r['status'] == 'approved',
              )
              .toList()
            ..sort(
              (a, b) => (a['approved_revision']! as int).compareTo(
                b['approved_revision']! as int,
              ),
            );
      final nets = <String>[p['net']! as String];
      String last = p['extra_cost_day']! as String;
      for (final r in approvedRows) {
        if (r['approved_revision'] != nets.length ||
            r['expected_revision'] != nets.length - 1 ||
            r['before_net'] != nets.last ||
            (r['day']! as String).compareTo(last) < 0 ||
            (r['approver'] as String?)?.trim().isNotEmpty != true ||
            DateTime.tryParse(r['approved_at']?.toString() ?? '') == null) {
          throw StateError('Invalid adjustment approval chain.');
        }
        nets.add(LaborMoney.sum([nets.last, r['delta']! as String]));
        if (ExactDecimal.parse(nets.last).isNegative) {
          throw StateError('Negative corrected payroll.');
        }
        last = r['day']! as String;
      }
      for (final r in all.where((r) => r['payroll_id'] == p['id'])) {
        final record = fromRow(r, lines), d = record.draft;
        d.validate();
        postingDay(d.day);
        if (p['status'] != 'approved' ||
            r['farm_id'] != p['farm_id'] ||
            r['currency'] != p['currency'] ||
            d.day.compareTo(p['extra_cost_day']! as String) < 0 ||
            d.expectedRevision >= nets.length ||
            r['before_net'] != nets[d.expectedRevision] ||
            (r['creator']! as String).trim().isEmpty ||
            DateTime.tryParse(r['created_at']! as String) == null) {
          throw StateError('Invalid correction source.');
        }
        if (r['status'] != 'approved' &&
            (r['approver'] != null ||
                r['approved_at'] != null ||
                r['approved_revision'] != null)) {
          throw StateError('Unapproved adjustment has approval fields.');
        }
        final code = RegExp(
          r'^DCL-([0-9]{6})-([0-9]{3,})$',
        ).firstMatch(r['code']! as String);
        final seq = await db.query(
          sequences,
          where: 'farm_id=? AND month=?',
          whereArgs: [r['farm_id'], d.day.substring(0, 7).replaceAll('-', '')],
        );
        if (code == null ||
            code.group(1) != d.day.substring(0, 7).replaceAll('-', '') ||
            int.parse(code.group(2)!) < 1 ||
            seq.length != 1 ||
            (seq.single['last_value']! as int) < int.parse(code.group(2)!)) {
          throw StateError('Invalid correction sequence.');
        }
        for (final line in lines.where((l) => l['adjustment_id'] == r['id'])) {
          if (line['farm_id'] != p['farm_id']) {
            throw StateError('Correction cost crosses farm.');
          }
        }
        await validateAllocations(
          db,
          p,
          d,
          throughRevision: d.expectedRevision,
        );
      }
      final events =
          allRefunds.where((r) => r['payroll_id'] == p['id']).toList()..sort(
            (a, b) => (a['event_revision']! as int).compareTo(
              b['event_revision']! as int,
            ),
          );
      final seen = <Map<String, Object?>>[];
      for (final r in events) {
        postingDay(r['day']! as String);
        ExactDecimal.validatePrice(
          r['amount']! as String,
          r['currency']! as String,
        );
        if (r['event_revision'] != seen.length + 1 ||
            p['status'] != 'approved' ||
            r['farm_id'] != p['farm_id'] ||
            r['currency'] != p['currency'] ||
            ExactDecimal.parse(r['amount']! as String).coefficient <=
                BigInt.zero ||
            (r['reason']! as String).trim().isEmpty ||
            (r['actor']! as String).trim().isEmpty ||
            DateTime.tryParse(r['created_at']! as String) == null) {
          throw StateError('Invalid payroll refund.');
        }
        final basis = jsonDecode(r['basis']! as String) as Map;
        final rev = basis['adjustmentRevision'];
        if (rev is! int ||
            rev < 0 ||
            rev >= nets.length ||
            basis['net'] != nets[rev]) {
          throw StateError('Invalid refund salary basis.');
        }
        if (approvedRows
            .take(rev)
            .any(
              (a) => (a['day']! as String).compareTo(r['day']! as String) > 0,
            )) {
          throw StateError('Refund precedes its correction basis.');
        }
        final ids = List<String>.from(basis['paymentIds'] as List);
        if (ids.toSet().length != ids.length) {
          throw StateError('Duplicated refund basis.');
        }
        final amounts = <String>[];
        for (final id in ids) {
          final payment = originals[id];
          if (payment == null ||
              payment['payroll_id'] != p['id'] ||
              payment['farm_id'] != p['farm_id'] ||
              payment['currency'] != p['currency'] ||
              (payment['business_day']! as String).compareTo(
                    r['day']! as String,
                  ) >
                  0) {
            throw StateError('Invalid refund cash basis.');
          }
          if (!await linkedPayment(db, payment))
            throw StateError('Refund basis lacks its original cash payment.');
          amounts.add(payment['amount']! as String);
        }
        final paidBefore = LaborMoney.minus(
          LaborMoney.sum(amounts),
          refundTotal(seen),
        );
        if (basis['paid'] != paidBefore ||
            ExactDecimal.parse(paidBefore).isNegative) {
          throw StateError('Invalid refund balance basis.');
        }
        if (r['reverses_id'] == null) {
          if (ExactDecimal.parse(r['amount']! as String).compareTo(
                ExactDecimal.parse(
                  LaborMoney.minus(paidBefore, basis['net']! as String),
                ),
              ) >
              0) {
            throw StateError('Refund exceeds its recorded receivable.');
          }
        } else {
          final source = seen
              .where((v) => v['id'] == r['reverses_id'])
              .toList();
          if (source.length != 1 ||
              source.single['reverses_id'] != null ||
              source.single['amount'] != r['amount'] ||
              seen.any((v) => v['reverses_id'] == r['reverses_id']) ||
              (source.single['day']! as String).compareTo(r['day']! as String) >
                  0) {
            throw StateError('Invalid refund reversal.');
          }
        }
        final cash = await db.query(
          'finance_documents_v2',
          where: 'id=? AND organization_id=?',
          whereArgs: [r['finance_id'], p['farm_id']],
        );
        if (r['finance_id'] != 'integrated:salary-refund:${r['id']}' ||
            cash.length != 1 ||
            cash.single['kind'] != (r['reverses_id'] == null ? 'THU' : 'CHI') ||
            cash.single['category'] !=
                (r['reverses_id'] == null
                    ? 'INTEGRATED_PAYROLL_REFUND'
                    : 'INTEGRATED_PAYROLL_REFUND_REVERSAL') ||
            cash.single['currency'] != p['currency'] ||
            IntegrationCash.amount(cash.single) != r['amount'] ||
            (cash.single['occurred_at']! as String).substring(0, 10) !=
                r['day']) {
          throw StateError('Refund does not match cash.');
        }
        for (final table in [
          'integration_cash_links_v1',
          'integration_salary_reversals_v1',
          'trade_settlements_v1',
          'trade_reversals_v1',
        ]) {
          final installed = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            [table],
          );
          if (installed.isNotEmpty &&
              (await db.query(
                table,
                where: 'finance_id=?',
                whereArgs: [r['finance_id']],
              )).isNotEmpty) {
            throw StateError('Refund cash is linked to another source.');
          }
        }
        seen.add(r);
      }
      final netPaid = await paid(
        db,
        p['farm_id']! as String,
        p['id']! as String,
      );
      if (ExactDecimal.parse(netPaid).isNegative ||
          ExactDecimal.parse(
                netPaid,
              ).compareTo(ExactDecimal.parse(await maximumNet(db, p))) >
              0) {
        throw StateError('Invalid corrected salary settlement.');
      }
    }
    if (all.any((r) => !payrolls.containsKey(r['payroll_id'])) ||
        allRefunds.any((r) => !payrolls.containsKey(r['payroll_id'])) ||
        lines.any((l) => !all.any((a) => a['id'] == l['adjustment_id']))) {
      throw StateError('Orphan payroll correction.');
    }
  }
}
