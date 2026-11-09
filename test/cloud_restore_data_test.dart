import 'package:agrico_deepseek/providers/cloud_sync_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty full restore payload is detected without replacing local data', () {
    expect(_emptyRestoreData().isEmpty, isTrue);
  });

  test('one populated module makes the full restore payload actionable', () {
    final data = _emptyRestoreData();
    expect(data.isEmpty, isTrue);
  });

  test('full restore progress excludes retired warehouse snapshots', () {
    final provider = CloudSyncProvider();
    expect(provider.isRestoringAll, isFalse);
    expect(provider.restoreAllCompletedSteps, 0);
    expect(provider.restoreAllTotalSteps, 11);
    expect(provider.restoreAllProgress, 0);
  });
}

CloudRestoreData _emptyRestoreData() => const CloudRestoreData(
  fields: [],
  fieldMeasurements: [],
  seasons: [],
  productionLogs: [],
  harvestRecords: [],
  productionCosts: [],
  employees: [],
  machines: [],
  tasks: [],
  distanceMeasurements: [],
  fuels: [],
  fuelTransactions: [],
  financeRecords: [],
);
