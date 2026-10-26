import 'package:excel/excel.dart';

import '../../../core/reports/excel_report_layout.dart';
import '../domain/machines.dart';
import '../../personnel/domain/personnel.dart' show LaborMoney;

class MachineReport {
  const MachineReport({
    required this.farm,
    required this.period,
    required this.machines,
    required this.runs,
    required this.expenses,
    required this.costs,
    this.machineId,
  });
  final String farm, period;
  final String? machineId;
  final List<MachineCard> machines;
  final List<MachineRecord<MachineRun>> runs;
  final List<MachineRecord<MachineExpense>> expenses;
  final List<ProductionMachineCost> costs;
  bool selected(String id, String day) =>
      (machineId == null || machineId == id) && day.startsWith('$period-');
  Excel workbook() {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period)) {
      throw const FormatException('Invalid report month.');
    }
    final e = Excel.createExcel();
    void row(String tab, List<String> cells, {Set<int> numbers = const {}}) {
      e[tab].appendRow([
        for (var i = 0; i < cells.length; i++)
          if (numbers.contains(i) &&
              RegExp(r'^-?\d+(\.\d+)?$').hasMatch(cells[i]) &&
              cells[i].replaceAll(RegExp(r'[-.]'), '').length <= 15)
            cells[i].contains('.')
                ? DoubleCellValue(double.parse(cells[i]))
                : IntCellValue(int.parse(cells[i]))
          else
            TextCellValue(cells[i]),
      ]);
    }

    final names = {for (final m in machines) m.id: '${m.code} · ${m.name}'};
    row('THONG TIN', ['AGRICO', 'Máy móc / Machine operations']);
    row('THONG TIN', ['Farm', farm]);
    row('THONG TIN', ['Month UTC+7', period]);
    row('THONG TIN', ['Machine', machineId ?? 'All']);
    row('THONG TIN', ['Export UTC', DateTime.now().toUtc().toIso8601String()]);
    row('THONG TIN', [
      'Cost rule',
      'Only approved all-inclusive shift allocations are production costs. Fuel and maintenance are component observations; never added again.',
    ]);
    row('THONG TIN', [
      'Fuel scope',
      'Records reconcile referenced source documents; no automatic stock movement, cash payment or payable. Litres per operating hour is a period ratio, not measured engine consumption.',
    ]);
    row('THONG TIN', [
      'Due service',
      'Latest approved maintenance as of export, not historical month-end.',
    ]);
    row('DANH SACH MAY', [
      'ID',
      'Code',
      'Name',
      'Active',
      'Model',
      'Serial',
      'Plate',
      'Owner',
      'Fuel',
      'Meter unit',
    ]);
    for (final m in machines.where(
      (m) => machineId == null || m.id == machineId,
    )) {
      row('DANH SACH MAY', [
        m.id,
        m.code,
        m.name,
        '${m.active}',
        m.profile['model'] ?? '',
        m.profile['serial'] ?? '',
        m.profile['plate'] ?? '',
        m.profile['owner'] ?? '',
        m.profile['fuelType'] ?? '',
        m.profile['meterUnit'] ?? '',
      ]);
    }
    final rs = runs.where(
      (r) => selected(r.value.machineId, r.value.businessDay),
    );
    row('NHAT KY CA MAY', [
      'ID',
      'Machine',
      'Operator ID',
      'Start UTC',
      'End UTC',
      'Idle minutes',
      'Operating minutes',
      'Meter start',
      'Meter end',
      'Output',
      'Unit',
      'Status',
      'Rate snapshot ID',
      'Cost',
      'Currency',
      'Allocated cost',
      'Unallocated cost',
    ]);
    for (final r in rs) {
      final v = r.value;
      final allocated = LaborMoney.sum(
        costs.where((c) => c.sourceId == v.id).map((c) => c.amount),
      );
      row(
        'NHAT KY CA MAY',
        [
          v.id,
          names[v.machineId] ?? v.machineId,
          v.operatorId,
          v.startsAt.toUtc().toIso8601String(),
          v.endsAt.toUtc().toIso8601String(),
          '${v.idleMinutes}',
          '${v.minutes}',
          v.meterStart,
          v.meterEnd,
          v.outputQuantity ?? '',
          v.outputUnit ?? '',
          r.status,
          r.rateId ?? '',
          r.amount ?? '',
          r.currency ?? '',
          r.status == 'approved' ? allocated : '',
          r.status == 'approved' ? LaborMoney.minus(r.amount!, allocated) : '',
        ],
        numbers: {5, 6, 7, 8, 9, 13, 15, 16},
      );
    }
    for (final kind in ['fuel', 'maintenance']) {
      final tab = kind == 'fuel' ? 'NHIEN LIEU' : 'BAO DUONG';
      row(tab, [
        'ID',
        'Day',
        'Machine',
        'Litres',
        'Meter',
        'Amount component only',
        'Currency',
        'Reference',
        'Description',
        'Next date',
        'Next meter',
        'Status',
      ]);
      for (final r in expenses.where(
        (r) => r.value.kind == kind && selected(r.value.machineId, r.value.day),
      )) {
        final v = r.value;
        row(
          tab,
          [
            v.id,
            v.day,
            names[v.machineId] ?? v.machineId,
            v.litres ?? '',
            v.meter ?? '',
            v.amount,
            v.currency,
            v.reference,
            v.note,
            v.nextOn ?? '',
            v.nextMeter ?? '',
            r.status,
          ],
          numbers: {3, 4, 5, 10},
        );
      }
    }
    row('PHAN BO MAY', [
      'Day',
      'Source',
      'Machine',
      'Plan ID',
      'Minutes',
      'All-inclusive cost',
      'Currency',
    ]);
    for (final c in costs.where((c) => selected(c.machineId, c.day))) {
      row(
        'PHAN BO MAY',
        [
          c.day,
          c.sourceId,
          names[c.machineId] ?? c.machineId,
          c.planId,
          '${c.minutes}',
          c.amount,
          c.currency,
        ],
        numbers: {4, 5},
      );
    }
    row('TONG HOP', [
      'Currency',
      'Approved full shift costs',
      'Allocated production cost',
      'Unallocated cost',
      'Fuel components only',
      'Maintenance components only',
    ]);
    for (final currency in ['VND', 'LAK']) {
      final total = LaborMoney.sum(
        rs
            .where((r) => r.status == 'approved' && r.currency == currency)
            .map((r) => r.amount!),
      );
      final allocated = LaborMoney.sum(
        costs
            .where(
              (c) => selected(c.machineId, c.day) && c.currency == currency,
            )
            .map((c) => c.amount),
      );
      String component(String kind) => LaborMoney.sum(
        expenses
            .where(
              (r) =>
                  r.status == 'approved' &&
                  r.value.kind == kind &&
                  r.value.currency == currency &&
                  selected(r.value.machineId, r.value.day),
            )
            .map((r) => r.value.amount),
      );
      row(
        'TONG HOP',
        [
          currency,
          total,
          allocated,
          LaborMoney.minus(total, allocated),
          component('fuel'),
          component('maintenance'),
        ],
        numbers: {1, 2, 3, 4, 5},
      );
    }
    row('NANG SUAT MAY', [
      'Machine',
      'Operating minutes',
      'Output unit',
      'Approved output',
      'Output/hour',
      'Fuel litres in period',
      'Litres/operating hour (period ratio)',
    ]);
    for (final m in machines.where(
      (m) => machineId == null || m.id == machineId,
    )) {
      final group = rs.where(
        (r) => r.status == 'approved' && r.value.machineId == m.id,
      );
      final minutes = group.fold<int>(0, (s, r) => s + r.value.minutes);
      final litres = LaborMoney.sum(
        expenses
            .where(
              (r) =>
                  r.status == 'approved' &&
                  r.value.kind == 'fuel' &&
                  r.value.machineId == m.id &&
                  selected(m.id, r.value.day),
            )
            .map((r) => r.value.litres!),
      );
      final units = group.map((r) => r.value.outputUnit ?? '').toSet();
      if (units.isEmpty) units.add('');
      for (final unit in units) {
        final specific = group.where((r) => (r.value.outputUnit ?? '') == unit);
        final output = LaborMoney.sum(
          specific.map((r) => r.value.outputQuantity ?? '0'),
        );
        final outputMinutes = specific.fold<int>(
          0,
          (s, r) => s + r.value.minutes,
        );
        row(
          'NANG SUAT MAY',
          [
            names[m.id]!,
            '$minutes',
            unit,
            output,
            outputMinutes == 0
                ? ''
                : LaborMoney.fraction(
                    output,
                    60,
                    outputMinutes,
                    6,
                    MoneyRounding.halfUp,
                  ),
            litres,
            minutes == 0
                ? ''
                : LaborMoney.fraction(
                    litres,
                    60,
                    minutes,
                    6,
                    MoneyRounding.halfUp,
                  ),
          ],
          numbers: {1, 3, 4, 5, 6},
        );
      }
    }
    row('LICH BAO DUONG', [
      'Machine',
      'Last approved service',
      'Next date',
      'Next meter',
      'Latest run meter',
      'Due as of export',
    ]);
    for (final m in machines.where(
      (m) => machineId == null || m.id == machineId,
    )) {
      final history =
          expenses
              .where(
                (r) =>
                    r.status == 'approved' &&
                    r.value.machineId == m.id &&
                    r.value.kind == 'maintenance',
              )
              .toList()
            ..sort((a, b) => b.value.day.compareTo(a.value.day));
      if (history.isEmpty) continue;
      final s = history.first.value;
      final readings =
          runs
              .where((r) => r.status == 'approved' && r.value.machineId == m.id)
              .toList()
            ..sort((a, b) => b.value.endsAt.compareTo(a.value.endsAt));
      final meter = readings.isEmpty ? s.meter : readings.first.value.meterEnd;
      final due =
          (s.nextOn != null &&
              MachineRules.day(DateTime.now()).compareTo(s.nextOn!) >= 0) ||
          (s.nextMeter != null &&
              meter != null &&
              ExactDecimal.parse(
                    meter,
                  ).compareTo(ExactDecimal.parse(s.nextMeter!)) >=
                  0);
      row(
        'LICH BAO DUONG',
        [
          names[m.id]!,
          s.day,
          s.nextOn ?? '',
          s.nextMeter ?? '',
          meter ?? '',
          due ? 'Due' : 'Not due / no threshold',
        ],
        numbers: {3, 4},
      );
    }
    e.delete('Sheet1');
    for (final sheet in e.tables.values) {
      for (var i = 0; i < sheet.maxColumns; i++) {
        sheet.setColumnWidth(i, 25);
      }
    }
    return e;
  }

  List<int> export() => encodeReportWorkbook(workbook());
}
