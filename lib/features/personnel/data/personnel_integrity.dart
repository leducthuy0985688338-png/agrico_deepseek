import '../../integration/data/integration_cash.dart';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../domain/personnel.dart';
import 'sqlite_personnel_repository.dart';

abstract final class PersonnelIntegrity {
  static Future<void> validate(DatabaseExecutor db) async {
    for (final d in await db.query('personnel_departments_v1')) {
      final match = RegExp(
        r'^BP-([0-9]{3,})$',
      ).firstMatch(d['code']! as String);
      final seq = await db.query(
        'personnel_department_sequences_v1',
        where: 'farm_id=?',
        whereArgs: [d['farm_id']],
      );
      if ((d['name']! as String).trim().isEmpty ||
          match == null ||
          int.parse(match.group(1)!) < 1 ||
          seq.length != 1 ||
          (seq.single['last_value']! as int) < int.parse(match.group(1)!))
        throw StateError('Invalid department sequence.');
    }
    final workers = {
      for (final c in await db.query('company_catalog_entries_v1')) c['id']: c,
    };
    void worker(String id, String farm, [String kind = 'worker']) {
      final w = workers[id];
      if (w == null || w['farm_id'] != farm || w['kind'] != kind) {
        throw StateError('Invalid personnel resource.');
      }
    }

    for (final p in await db.query('personnel_profiles_v1')) {
      worker(p['worker_id']! as String, p['farm_id']! as String);
      if (p['department_id'] != null) {
        final d = await db.query(
          'personnel_departments_v1',
          where: 'id=? AND farm_id=?',
          whereArgs: [p['department_id'], p['farm_id']],
        );
        if (d.length != 1) throw StateError('Invalid personnel department.');
      }
      EmployeeProfile(
        workerId: p['worker_id']! as String,
        farmId: p['farm_id']! as String,
        details: Map<String, String>.from(
          jsonDecode(p['profile_json']! as String) as Map,
        ),
        revision: p['revision']! as int,
      ).validate();
    }
    final rates = {
      for (final r in await db.query('personnel_pay_rates_v1'))
        r['id']: SqlitePersonnelRepository.rateFromRow(r),
    };
    for (final r in rates.values) {
      r.validate();
      worker(r.workerId, r.farmId);
      if (r.workTypeId.isNotEmpty) worker(r.workTypeId, r.farmId, 'taskType');
    }
    final plans = {
      for (final p in await db.query('production_plans_v1')) p['id']: p,
    };
    final entries = {
      for (final e in await db.query('personnel_entries_v1')) e['id']: e,
    };
    final costs = await db.query(
      'production_labor_costs_v1',
      orderBy: 'plan_id',
    );
    final intervals = <String, List<(DateTime, DateTime)>>{};
    final daily = <String, int>{};
    for (final e in entries.values) {
      final farm = e['farm_id']! as String,
          id = e['id']! as String,
          w = e['worker_id']! as String;
      worker(w, farm);
      final allocations = costs.where((a) => a['entry_id'] == id).toList();
      final draft = LaborEntryDraft(
        id: id,
        farmId: farm,
        workerId: w,
        startsAt: DateTime.parse(e['starts_at']! as String),
        endsAt: DateTime.parse(e['ends_at']! as String),
        breakMinutes: e['break_minutes']! as int,
        overtimeMinutes: e['overtime_minutes']! as int,
        pieceQuantity: e['piece_quantity'] as String?,
        machineId: e['machine_id'] as String?,
        requestedBasis: e['requested_basis'] == null
            ? null
            : PayBasis.values.byName(e['requested_basis']! as String),
        requestedPieceUnit: e['requested_piece_unit']! as String,
        workTypeId: e['work_type_id']! as String,
        outputQuantity: e['output_quantity'] as String?,
        outputUnit: e['output_unit'] as String?,
        allocations: allocations
            .map(
              (a) => LaborAllocationDraft(
                planId: a['plan_id']! as String,
                regularMinutes: a['regular_minutes']! as int,
                overtimeMinutes: a['overtime_minutes']! as int,
                taskId: a['task_id'] as String?,
              ),
            )
            .toList(),
      );
      draft.validate();
      if (draft.workTypeId.isNotEmpty) {
        worker(draft.workTypeId, farm, 'taskType');
      }
      if (draft.businessDay != e['business_day'] ||
          draft.regularMinutes != e['regular_minutes'] ||
          (e['revision']! as int) < 0 ||
          !{'draft', 'approved', 'void'}.contains(e['status'])) {
        throw StateError('Invalid attendance snapshot.');
      }
      if (draft.machineId != null) worker(draft.machineId!, farm, 'machine');
      if (e['status'] != 'void') {
        intervals.putIfAbsent('$farm/$w', () => []).add((
          draft.startsAt,
          draft.endsAt,
        ));
      }
      PayRate? rate;
      List<String>? amounts;
      if (e['rate_id'] != null) {
        rate = rates[e['rate_id']];
        if (rate == null ||
            rate.farmId != farm ||
            rate.workerId != w ||
            rate.effectiveOn.compareTo(draft.businessDay) > 0) {
          throw StateError('Invalid earning rate.');
        }
        if (draft.requestedBasis != null &&
            draft.requestedBasis != rate.basis) {
          throw StateError('Pay basis mismatch.');
        }
        if (draft.requestedPieceUnit.isNotEmpty &&
            draft.requestedPieceUnit != rate.pieceUnit) {
          throw StateError('Piece unit mismatch.');
        }
        if (rate.workTypeId.isNotEmpty && rate.workTypeId != draft.workTypeId) {
          throw StateError('Work type rate mismatch.');
        }
        final earnings = SqlitePersonnelRepository.earnings(e, rate);
        for (final field in ['regular', 'overtime', 'piece', 'total']) {
          if (earnings[field] != e['${field}_amount']) {
            throw StateError('Earnings arithmetic mismatch.');
          }
        }
        if (e['currency'] != rate.currency ||
            (e['approved_by'] as String?)?.trim().isNotEmpty != true) {
          throw StateError('Invalid approved earning.');
        }
        amounts = SqlitePersonnelRepository.allocationAmounts(
          e,
          rate,
          allocations,
        );
        if (e['status'] == 'approved') {
          final key = '$farm/$w/${draft.businessDay}';
          daily[key] = (daily[key] ?? 0) + draft.regularMinutes;
          if (daily[key]! > rate.standardMinutes) {
            throw StateError('Regular day cap exceeded.');
          }
        }
      } else if (e['status'] == 'approved' ||
          e['total_amount'] != null ||
          e['currency'] != null) {
        throw StateError('Missing earning snapshot.');
      }
      for (var i = 0; i < allocations.length; i++) {
        final a = allocations[i], p = plans[allocations[i]['plan_id']];
        if (a['farm_id'] != farm ||
            p == null ||
            p['farm_id'] != farm ||
            draft.businessDay.compareTo(p['starts_on']! as String) < 0 ||
            draft.businessDay.compareTo(p['ends_on']! as String) > 0) {
          throw StateError('Invalid labor plan.');
        }
        if (rate != null &&
            (a['currency'] != rate.currency ||
                p['currency'] != rate.currency ||
                a['amount'] != amounts![i])) {
          throw StateError('Labor allocation differs from source.');
        }
        if (rate == null && (a['currency'] != null || a['amount'] != null)) {
          throw StateError('Draft labor cost must be unpriced.');
        }
        if (a['task_id'] != null) {
          final tasks = await db.rawQuery(
            'SELECT t.id FROM production_plan_tasks_v1 t JOIN farm_tasks_v2 f ON f.id=t.id '
            'WHERE t.id=? AND t.plan_id=? AND t.farm_id=? AND (f.worker_resource_id IS NULL OR f.worker_resource_id=?)',
            [a['task_id'], a['plan_id'], farm, w],
          );
          if (tasks.length != 1) throw StateError('Invalid labor task.');
        }
      }
    }
    for (final list in intervals.values) {
      list.sort((a, b) => a.$1.compareTo(b.$1));
      for (var i = 1; i < list.length; i++) {
        if (list[i].$1.isBefore(list[i - 1].$2)) {
          throw StateError('Overlapping attendance.');
        }
      }
    }
    final lines = await db.query('personnel_payroll_lines_v1');
    final payrolls = await db.query('personnel_payrolls_v1');
    final payments = await db.query('personnel_payments_v1');
    final reversedPayments = await IntegrationCash.reversed(db);
    for (final p in payrolls) {
      worker(p['worker_id']! as String, p['farm_id']! as String);
      if ((p['worker_name_snapshot']! as String).trim().isEmpty) {
        throw StateError('Payroll name snapshot required.');
      }
      PayrollDraft(
        id: p['id']! as String,
        farmId: p['farm_id']! as String,
        workerId: p['worker_id']! as String,
        period: p['period']! as String,
        currency: p['currency']! as String,
        allowance: p['allowance']! as String,
        bonus: p['bonus']! as String,
        advance: p['advance']! as String,
        deduction: p['deduction']! as String,
        note: p['note']! as String,
      ).validate();
      final sources = lines.where((l) => l['payroll_id'] == p['id']).toList();
      if (sources.isEmpty) throw StateError('Payroll without sources.');
      for (final l in sources) {
        final e = entries[l['entry_id']];
        if (e == null ||
            e['farm_id'] != p['farm_id'] ||
            e['worker_id'] != p['worker_id'] ||
            e['currency'] != p['currency'] ||
            (e['business_day']! as String).substring(0, 7) != p['period'] ||
            e['total_amount'] != l['amount'] ||
            (p['status'] != 'cancelled' &&
                (e['status'] != 'approved' || l['active'] != 1)) ||
            (p['status'] == 'cancelled' && l['active'] != 0)) {
          throw StateError('Invalid payroll source.');
        }
      }
      for (final field in ['regular', 'overtime', 'piece']) {
        final sum = LaborMoney.sum(
          sources.map(
            (l) => entries[l['entry_id']]!['${field}_amount']! as String,
          ),
        );
        if (sum != p[field]) throw StateError('Payroll total mismatch.');
      }
      final net = LaborMoney.minus(
        LaborMoney.sum(
          [
            p['regular'],
            p['overtime'],
            p['piece'],
            p['allowance'],
            p['bonus'],
          ].cast<String>(),
        ),
        LaborMoney.sum([p['advance'], p['deduction']].cast<String>()),
      );
      if (net != p['net'] || ExactDecimal.parse(net).isNegative) {
        throw StateError('Payroll net mismatch.');
      }
      final paid = LaborMoney.sum(
        payments.where((v) => v['payroll_id'] == p['id']).map((v) {
          if (p['status'] != 'approved' ||
              v['farm_id'] != p['farm_id'] ||
              v['currency'] != p['currency'] ||
              (v['note']! as String).trim().isEmpty) {
            throw StateError('Invalid salary payment.');
          }
          LaborMoney.date(v['business_day']! as String);
          ExactDecimal.validatePrice(
            v['amount']! as String,
            v['currency']! as String,
          );
          if (ExactDecimal.parse(v['amount']! as String).coefficient <=
              BigInt.zero) {
            throw StateError('Invalid payment amount.');
          }
          return reversedPayments.contains(v['id'])
              ? '0'
              : v['amount']! as String;
        }),
      );
      if (ExactDecimal.parse(paid).compareTo(ExactDecimal.parse(net)) > 0) {
        throw StateError('Salary overpayment.');
      }
      LaborMoney.date(p['extra_cost_day']! as String);
      if ((p['extra_cost_day']! as String).substring(0, 7) != p['period']) {
        throw StateError('Invalid extra cost date.');
      }
      if (p['adjustment_plan_id'] != null) {
        final plan = plans[p['adjustment_plan_id']];
        if (plan == null ||
            plan['farm_id'] != p['farm_id'] ||
            plan['currency'] != p['currency'] ||
            (p['extra_cost_day']! as String).compareTo(
                  plan['starts_on']! as String,
                ) <
                0 ||
            (p['extra_cost_day']! as String).compareTo(
                  plan['ends_on']! as String,
                ) >
                0) {
          throw StateError('Invalid payroll cost allocation.');
        }
      }
      final code = RegExp(
        r'^LUONG-(\d{6})-(\d{3,})$',
      ).firstMatch(p['code']! as String);
      final sequence = await db.query(
        'personnel_payroll_sequences_v1',
        where: 'farm_id=? AND period=?',
        whereArgs: [p['farm_id'], p['period']],
      );
      if (code == null ||
          code.group(1) != (p['period']! as String).replaceAll('-', '') ||
          sequence.length != 1 ||
          (sequence.single['last_value']! as int) < int.parse(code.group(2)!)) {
        throw StateError('Invalid payroll number.');
      }
    }
    final payrollIds = payrolls.map((p) => p['id']).toSet();
    if (lines.any((l) => !payrollIds.contains(l['payroll_id'])) ||
        payments.any((p) => !payrollIds.contains(p['payroll_id']))) {
      throw StateError('Orphan salary record.');
    }
  }
}
