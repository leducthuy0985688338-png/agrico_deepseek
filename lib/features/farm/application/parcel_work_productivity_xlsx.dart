import 'package:excel/excel.dart';

import 'parcel_work_time_productivity.dart';

/// Separate read-only workbook. Does not modify Report20.
/// Area and rates are recorded indicators, not geometry-verified unique area.
class ParcelWorkProductivityXlsx {
  const ParcelWorkProductivityXlsx();

  List<int> encode(ParcelWorkTimeProductivity summary) {
    final workbook = Excel.createExcel();
    const tab = 'Work productivity';
    final sheet = workbook[tab];
    final r = summary.recorded;
    sheet.appendRow([
      TextCellValue('Farm'),
      TextCellValue('Parcel'),
      TextCellValue('Phase'),
      TextCellValue('Events'),
      TextCellValue('Recorded area (m2)'),
      TextCellValue('Events missing area'),
      TextCellValue('Worker minutes'),
      TextCellValue('Machine minutes'),
      TextCellValue('Time evidence count'),
      TextCellValue('Recorded ha / worker hour'),
      TextCellValue('Recorded ha / machine hour'),
    ]);
    sheet.appendRow([
      TextCellValue(_safe(r.farmId)),
      TextCellValue(_safe(r.parcelId)),
      TextCellValue(r.phase.name),
      IntCellValue(r.eventCount),
      DoubleCellValue(r.recordedAreaM2),
      IntCellValue(r.eventsWithoutArea),
      IntCellValue(summary.workerMinutes),
      IntCellValue(summary.machineMinutes),
      IntCellValue(summary.evidenceCount),
      if (summary.recordedHaPerWorkerHour case final double rate)
        DoubleCellValue(rate)
      else
        TextCellValue(''),
      if (summary.recordedHaPerMachineHour case final double rate)
        DoubleCellValue(rate)
      else
        TextCellValue(''),
    ]);
    final workers = workbook['Workers'];
    workers.appendRow([
      TextCellValue('Resource ID'),
      TextCellValue('Event participations'),
    ]);
    for (final id in r.workerEventCounts.keys.toList()..sort()) {
      workers.appendRow([
        TextCellValue(_safe(id)),
        IntCellValue(r.workerEventCounts[id]!),
      ]);
    }
    final machines = workbook['Machines'];
    machines.appendRow([
      TextCellValue('Resource ID'),
      TextCellValue('Event participations'),
    ]);
    for (final id in r.machineEventCounts.keys.toList()..sort()) {
      machines.appendRow([
        TextCellValue(_safe(id)),
        IntCellValue(r.machineEventCounts[id]!),
      ]);
    }
    // Excel.createExcel() includes a default sheet; remove it if unused.
    if (workbook.tables.containsKey('Sheet1')) workbook.delete('Sheet1');
    final bytes = workbook.save();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('XLSX encoding failed.');
    }
    return bytes;
  }

  String _safe(String value) {
    final trimmed = value.replaceFirst(RegExp(r'^[\s\u0000-\u001f]+'), '');
    return trimmed.isNotEmpty && '=+-@'.contains(trimmed[0])
        ? "'$value"
        : value;
  }
}
