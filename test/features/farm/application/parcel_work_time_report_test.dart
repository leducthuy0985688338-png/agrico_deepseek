import 'package:agrico_deepseek/features/farm/application/parcel_work_productivity.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_work_time_productivity.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_work_time_report.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:flutter_test/flutter_test.dart';

ParcelWorkTimeProductivity summary({
  String farmId = 'farm',
  int missingArea = 0,
  int workerMinutes = 120,
  int machineMinutes = 60,
}) => ParcelWorkTimeProductivity(
  recorded: ParcelWorkProductivity(
    farmId: farmId,
    parcelId: 'parcel',
    phase: ParcelWorkPhase.clearing,
    eventCount: 1,
    recordedAreaM2: 10000,
    eventsWithoutArea: missingArea,
    workerEventCounts: const {'w1': 1},
    machineEventCounts: const {'m1': 1},
  ),
  workerMinutes: workerMinutes,
  machineMinutes: machineMinutes,
  evidenceCount: 2,
);

void main() {
  const csv = ParcelWorkTimeReportCsv();

  test('exports evidence totals and recorded-area rates', () {
    final output = csv.encode(summary());
    expect(output.startsWith('\uFEFF'), isTrue);
    expect(output, contains('"worker_minutes"'));
    expect(output, contains('"120","60","2","0.5","1.0"'));
    expect(output.endsWith('\r\n'), isTrue);
  });

  test(
    'unknown duration or incomplete area never exports an invented rate',
    () {
      final output = csv.encode(summary(missingArea: 1, workerMinutes: 0));
      expect(output, contains('"0","60","2","",""'));
    },
  );

  test('escapes spreadsheet formulas and CSV quotes', () {
    final output = csv.encode(summary(farmId: '  =1+2,"danger"'));
    expect(output, contains('"\'  =1+2,""danger"""'));
  });
}
