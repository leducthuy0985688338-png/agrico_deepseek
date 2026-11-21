import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_work_productivity.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_work_time_productivity.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_work_productivity_xlsx.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';

void main() {
  test('XLSX contains separate summary and resource sheets', () {
    final value = ParcelWorkTimeProductivity(
      recorded: ParcelWorkProductivity(
        farmId: 'farm-1',
        parcelId: 'parcel-1',
        phase: ParcelWorkPhase.values.first,
        eventCount: 2,
        recordedAreaM2: 10000,
        eventsWithoutArea: 0,
        workerEventCounts: const {'worker-1': 2},
        machineEventCounts: const {'machine-1': 1},
      ),
      workerMinutes: 120,
      machineMinutes: 60,
      evidenceCount: 2,
    );
    final bytes = const ParcelWorkProductivityXlsx().encode(value);
    final parsed = Excel.decodeBytes(bytes);
    expect(
      parsed.tables.keys,
      containsAll(['Work productivity', 'Workers', 'Machines']),
    );
    expect(parsed['Work productivity'].rows.length, 2);
    expect(parsed['Workers'].rows.length, 2);
    expect(parsed['Machines'].rows.length, 2);
  });

  test('XLSX does not create a rate when time is missing', () {
    final value = ParcelWorkTimeProductivity(
      recorded: ParcelWorkProductivity(
        farmId: '=unsafe',
        parcelId: 'parcel-1',
        phase: ParcelWorkPhase.values.first,
        eventCount: 0,
        recordedAreaM2: 0,
        eventsWithoutArea: 0,
        workerEventCounts: const {},
        machineEventCounts: const {},
      ),
      workerMinutes: 0,
      machineMinutes: 0,
      evidenceCount: 0,
    );
    final parsed = Excel.decodeBytes(
      const ParcelWorkProductivityXlsx().encode(value),
    );
    expect(parsed['Work productivity'].rows.length, 2);
    expect(
      parsed['Work productivity'].rows[1][0]?.value.toString(),
      contains("'=unsafe"),
    );
  });
}
