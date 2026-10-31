import 'package:sqflite/sqflite.dart';

import 'sqlite_machine_repository.dart';
import '../domain/machines.dart';
import '../../personnel/domain/personnel.dart' show LaborMoney;

abstract final class MachineIntegrity {
  static Future<void> validate(DatabaseExecutor db) async {
    void require(bool condition) {
      if (!condition) throw StateError('Machine backup integrity failure.');
    }

    final rateRows = await db.query('machine_rates_v1');
    final rates = <String, MachineRate>{};
    final rateFarms = <String, String>{};
    for (final r in rateRows) {
      final v = MachineRate.fromJson(SqliteMachineRepository.body(r));
      v.validate();
      require(
        v.id == r['id'] &&
            v.machineId == r['machine_id'] &&
            v.effectiveOn == r['effective_on'] &&
            v.revision == r['revision'],
      );
      await SqliteMachineRepository.resource(
        db,
        r['farm_id'] as String,
        v.machineId,
        'machine',
        active: false,
      );
      rates[v.id] = v;
      rateFarms[v.id] = r['farm_id'] as String;
    }
    final profiles = await db.query('machine_profiles_v1');
    for (final r in profiles) {
      await SqliteMachineRepository.resource(
        db,
        r['farm_id'] as String,
        r['machine_id'] as String,
        'machine',
        active: false,
      );
      require(
        {'hour', 'km'}.contains(SqliteMachineRepository.body(r)['meterUnit']),
      );
    }
    final all = await db.query('machine_runs_v1');
    final allocated = await db.query('machine_costs_v1');
    for (final r in all) {
      final v = MachineRun.fromJson(SqliteMachineRepository.body(r));
      v.validate();
      final farm = r['farm_id'] as String;
      for (final visit in v.segments) {
        // Historical/closed plans remain valid during restore; task identity
        // and resource links are checked below without requiring active status.
        if (visit.taskId != null) {
          final tasks = await db.rawQuery(
            'SELECT t.id FROM farm_tasks_v2 t JOIN production_plan_tasks_v1 p ON p.id=t.id WHERE t.id=? AND t.farm_id=? AND p.plan_id=? AND (t.worker_resource_id IS NULL OR t.worker_resource_id=?) AND (t.machine_resource_id IS NULL OR t.machine_resource_id=?)',
            [visit.taskId, farm, visit.planId, v.operatorId, v.machineId],
          );
          require(tasks.length == 1);
        }
      }
      require(
        v.id == r['id'] &&
            v.machineId == r['machine_id'] &&
            v.businessDay == r['day'] &&
            v.startsAt.toUtc().toIso8601String() == r['starts_at'] &&
            v.endsAt.toUtc().toIso8601String() == r['ends_at'],
      );
      await SqliteMachineRepository.resource(
        db,
        farm,
        v.machineId,
        'machine',
        active: false,
      );
      await SqliteMachineRepository.resource(
        db,
        farm,
        v.operatorId,
        'worker',
        active: false,
      );
      await SqliteMachineRepository.profileExists(db, farm, v.machineId);
      final parts = allocated.where((a) => a['source_id'] == v.id).toList();
      require(parts.length == v.allocations.length);
      final approved = r['rate_id'] != null;
      if (r['status'] == 'approved') require(approved);
      if (r['status'] == 'draft') {
        require(!approved && r['amount'] == null && r['currency'] == null);
      }
      MachineRate? rate;
      List<String>? amounts;
      if (approved) {
        rate = rates[r['rate_id']];
        require(rate != null);
        require(
          rate!.machineId == v.machineId &&
              rateFarms[rate.id] == farm &&
              rate.effectiveOn.compareTo(v.businessDay) <= 0,
        );
        require(
          rate.cost(v.minutes) == r['amount'] && rate.currency == r['currency'],
        );
        amounts = LaborMoney.allocate(
          r['amount'] as String,
          v.allocations.map((a) => a.minutes).toList(),
          v.minutes,
          rate.scale,
        );
      }
      for (var i = 0; i < v.allocations.length; i++) {
        final a = v.allocations[i];
        final matches = parts.where((p) => p['plan_id'] == a.planId).toList();
        require(matches.length == 1);
        final p = matches.single;
        require(p['farm_id'] == farm && p['minutes'] == a.minutes);
        if (a.taskId != null) {
          final tasks = await db.rawQuery(
            'SELECT id FROM production_plan_tasks_v1 WHERE id=? AND farm_id=? AND plan_id=?',
            [a.taskId, farm, a.planId],
          );
          require(tasks.length == 1);
        }
        final plan = await SqliteMachineRepository.one(
          db,
          'production_plans_v1',
          farm,
          a.planId,
        );
        require(
          v.businessDay.compareTo(plan['starts_on'] as String) >= 0 &&
              v.businessDay.compareTo(plan['ends_on'] as String) <= 0,
        );
        if (approved) {
          require(
            p['currency'] == rate!.currency &&
                p['amount'] == amounts![i] &&
                plan['currency'] == rate.currency,
          );
        } else {
          require(p['currency'] == null && p['amount'] == null);
        }
      }
      if (r['status'] == 'approved' &&
          (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='personnel_entries_v1'",
          )).isNotEmpty) {
        final attendance = await db.query(
          'personnel_entries_v1',
          where:
              "farm_id=? AND worker_id=? AND status='approved' AND starts_at<? AND ends_at>?",
          whereArgs: [farm, v.operatorId, r['ends_at'], r['starts_at']],
        );
        require(attendance.every((e) => e['machine_id'] == v.machineId));
      }
      if (r['status'] == 'void') continue;
      for (final other in all) {
        if (other['id'] == r['id'] ||
            other['status'] == 'void' ||
            other['farm_id'] != farm) {
          continue;
        }
        final o = MachineRun.fromJson(SqliteMachineRepository.body(other));
        if (o.machineId == v.machineId || o.operatorId == v.operatorId) {
          require(
            !(v.startsAt.isBefore(o.endsAt) && v.endsAt.isAfter(o.startsAt)),
          );
        }
        if (o.machineId == v.machineId && !o.endsAt.isAfter(v.startsAt)) {
          require(
            ExactDecimal.parse(
                  o.meterEnd,
                ).compareTo(ExactDecimal.parse(v.meterStart)) <=
                0,
          );
        }
      }
    }
    final ids = all.map((r) => r['id']).toSet();
    require(allocated.every((a) => ids.contains(a['source_id'])));
    for (final r in await db.query('machine_expenses_v1')) {
      final v = MachineExpense.fromJson(SqliteMachineRepository.body(r));
      v.validate();
      require(
        v.id == r['id'] &&
            v.machineId == r['machine_id'] &&
            v.day == r['day'] &&
            v.kind == r['kind'] &&
            v.reference.trim() == r['reference'],
      );
      await SqliteMachineRepository.resource(
        db,
        r['farm_id'] as String,
        v.machineId,
        'machine',
        active: false,
      );
      await SqliteMachineRepository.profileExists(
        db,
        r['farm_id'] as String,
        v.machineId,
      );
    }
  }
}
