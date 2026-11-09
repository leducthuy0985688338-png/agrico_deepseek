import 'dart:convert';
import 'package:excel/excel.dart';
import '../domain/machines.dart';
import '../../personnel/domain/personnel.dart' show LaborMoney;

/// Values are authoritative ERP snapshots, not independent spreadsheet math.
/// One cost row per plan; visits never repeat a plan's money.
abstract final class MachineAllocationExport {
  static void append(
    Excel excel, {
    required Iterable<MachineRecord<MachineRun>> runs,
    required List<ProductionMachineCost> costs,
    required MachineTrace trace,
  }) {
    void row(String sheet, List<Object?> cells) => excel[sheet].appendRow([
      for (final c in cells) TextCellValue(c?.toString() ?? ''),
    ]);
    const allocations = 'PHAN BO CA MAY ERP';
    const visits = 'LUOT CHUYEN MAY ERP';
    row(allocations, [
      'Run ID',
      'Day UTC+7',
      'Machine ID',
      'Operator ID',
      'Operating minutes',
      'Plan ID',
      'Plan code',
      'Parcel ID',
      'Parcel code',
      'Allocated minutes',
      'Approved plan cost',
      'Currency',
      'Rate ID',
      'Rate revision',
      'Rate amount',
      'Standard minutes',
      'Scale',
      'Rounding',
      'Status',
      'Run revision',
      'Entered by',
      'Entered UTC',
      'Approved by',
      'Approved UTC',
      'Unallocated minutes',
      'Unallocated cost (once per run)',
      'Source policy',
      'Audit events (supplementary; not historical closing digest)',
      'Run note / correction reference',
    ]);
    row(visits, [
      'Run ID',
      'Visit order',
      'Plan ID',
      'Plan code',
      'Parcel ID',
      'Parcel code',
      'Minutes',
      'Task ID',
      'History source',
      'Cost source (money only in plan allocation sheet)',
    ]);
    final rateById = {for (final r in trace.rates) r.id: r};
    final costsByRun = <String, List<ProductionMachineCost>>{};
    for (final cost in costs) {
      costsByRun.putIfAbsent(cost.sourceId, () => []).add(cost);
    }
    final auditByRun = <Object?, List<Map<String, Object?>>>{};
    for (final audit in trace.audit) {
      auditByRun.putIfAbsent(audit['entity_id'], () => []).add(audit);
    }
    for (final record in runs) {
      final run = record.value;
      final rate = rateById[record.rateId];
      final events = auditByRun[run.id] ?? const [];
      Map<String, Object?> event(String action) =>
          events.where((a) => a['action'] == action).firstOrNull ?? const {};
      final entered = event('run.create'), approved = event('run.approve');
      final sourceCosts =
          (costsByRun[run.id] ?? const <ProductionMachineCost>[])
              .where((c) => c.currency == record.currency)
              .toList();
      final allocated = LaborMoney.sum(sourceCosts.map((c) => c.amount));
      final costByPlan = {for (final c in sourceCosts) c.planId: c};
      final parts = run.allocations;
      // A zero-allocation run must still expose its full remainder.
      for (var i = 0; i < (parts.isEmpty ? 1 : parts.length); i++) {
        final part = parts.isEmpty ? null : parts[i];
        final plan = trace.plans[part?.planId] ?? const {};
        final parcel = plan['parcel_id'] as String?;
        final cost = costByPlan[part?.planId];
        row(allocations, [
          run.id,
          run.businessDay,
          run.machineId,
          run.operatorId,
          run.minutes,
          part?.planId,
          plan['code'],
          parcel,
          trace.parcelCodes[parcel],
          part?.minutes ?? 0,
          record.status == 'approved' ? cost?.amount : null,
          record.currency,
          record.rateId,
          rate?.revision,
          rate?.amount,
          rate?.shiftMinutes,
          rate?.scale,
          rate?.rounding.name,
          record.status,
          record.revision,
          entered['actor_id'],
          entered['occurred_at'],
          approved['actor_id'],
          approved['occurred_at'],
          i == 0
              ? run.minutes - parts.fold<int>(0, (s, a) => s + a.minutes)
              : null,
          i == 0 && record.status == 'approved'
              ? LaborMoney.minus(record.amount!, allocated)
              : null,
          'ERP all-inclusive; total rounded then largest remainder; no components added',
          events.isEmpty ? 'Unavailable in this source' : jsonEncode(events),
          run.note,
        ]);
      }
      final history = run.segments.isEmpty ? run.allocations : run.segments;
      for (var i = 0; i < history.length; i++) {
        final visit = history[i],
            plan = trace.plans[history[i].planId] ?? const {};
        final parcel = plan['parcel_id'] as String?;
        row(visits, [
          run.id,
          i + 1,
          visit.planId,
          plan['code'],
          parcel,
          trace.parcelCodes[parcel],
          visit.minutes,
          visit.taskId,
          run.segments.isEmpty
              ? 'Historical aggregate; visit order unknown'
              : 'Ordered minute visits',
          '${run.id}:${visit.planId}',
        ]);
      }
    }
  }
}
