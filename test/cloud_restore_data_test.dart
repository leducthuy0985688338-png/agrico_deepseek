import 'package:agrico_deepseek/models/warehouse_item.dart';
import 'package:agrico_deepseek/providers/cloud_sync_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty full restore payload is detected without replacing local data', () {
    expect(_emptyRestoreData().isEmpty, isTrue);
  });

  test('one populated module makes the full restore payload actionable', () {
    final data = _emptyRestoreData(
      warehouseItems: [
        WarehouseItem(
          id: 'VT-001',
          name: 'Phân bón',
          unit: 'kg',
          importPrice: 12000,
          supplier: 'Nhà cung cấp A',
          stock: 50,
        ),
      ],
    );

    expect(data.isEmpty, isFalse);
  });

  test('full restore progress exposes all dependency groups', () {
    final provider = CloudSyncProvider();

    expect(provider.isRestoringAll, isFalse);
    expect(provider.restoreAllCompletedSteps, 0);
    expect(provider.restoreAllTotalSteps, 12);
    expect(provider.restoreAllProgress, 0);
  });
}

CloudRestoreData _emptyRestoreData({
  List<WarehouseItem> warehouseItems = const [],
}) =>
    CloudRestoreData(
      fields: const [],
      fieldMeasurements: const [],
      seasons: const [],
      productionLogs: const [],
      harvestRecords: const [],
      productionCosts: const [],
      employees: const [],
      machines: const [],
      tasks: const [],
      distanceMeasurements: const [],
      warehouseItems: warehouseItems,
      fuels: const [],
      fuelTransactions: const [],
      financeRecords: const [],
    );
