import 'package:agrico_deepseek/models/production_cost_model.dart';
import 'package:agrico_deepseek/providers/production_cost_provider.dart';
import 'package:agrico_deepseek/services/production_cost_database.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeProductionCostDatabase extends ProductionCostDatabase {
  List<ProductionCostModel> persisted = const [];

  @override
  Future<void> replaceAll(List<ProductionCostModel> records) async {
    persisted = List.unmodifiable(records);
  }
}

void main() {
  test('production cost cloud round trip keeps accounting and source details',
      () {
    final source = ProductionCostModel(
      id: 'CP-CLOUD',
      fieldId: 'LO-CLOUD',
      seasonId: 'VU-CLOUD',
      category: ProductionCostCategory.labor,
      date: DateTime.utc(2027, 2, 19, 8, 30),
      itemName: 'Công lao động • Nguyễn Văn An',
      quantity: 1.25,
      unit: 'ngày công',
      unitPrice: 240000,
      amount: 300000,
      employeeId: 'NV-01',
      machineId: 'MAY-01',
      notes: 'Ca làm 10 giờ',
      source: 'labor',
      sourceId: 'NV-01|LO-CLOUD|2027-02-19T08:30:00.000Z',
    );

    final restored = ProductionCostModel.fromJson(source.toJson());

    expect(restored.id, source.id);
    expect(restored.fieldId, source.fieldId);
    expect(restored.seasonId, source.seasonId);
    expect(restored.category, source.category);
    expect(restored.date, source.date);
    expect(restored.itemName, source.itemName);
    expect(restored.quantity, source.quantity);
    expect(restored.unit, source.unit);
    expect(restored.unitPrice, source.unitPrice);
    expect(restored.amount, source.amount);
    expect(restored.employeeId, source.employeeId);
    expect(restored.machineId, source.machineId);
    expect(restored.notes, source.notes);
    expect(restored.source, source.source);
    expect(restored.sourceId, source.sourceId);
  });

  test(
      'production cost restore replaces state, deduplicates, and ignores empty cloud',
      () async {
    final database = FakeProductionCostDatabase();
    final provider = ProductionCostProvider(database: database);
    final older = ProductionCostModel(
      id: 'CP-01',
      fieldId: 'LO-01',
      seasonId: 'VU-01',
      category: ProductionCostCategory.material,
      date: DateTime.utc(2027, 2, 15),
      itemName: 'Phân bón',
      quantity: 10,
      unit: 'kg',
      unitPrice: 12000,
      amount: 120000,
    );
    final newer = ProductionCostModel(
      id: 'CP-02',
      fieldId: 'LO-01',
      seasonId: 'VU-01',
      category: ProductionCostCategory.fuel,
      date: DateTime.utc(2027, 2, 18),
      itemName: 'Dầu diesel',
      quantity: 20,
      unit: 'lít',
      unitPrice: 22000,
      amount: 440000,
      machineId: 'MAY-01',
      source: 'fuel',
      sourceId: 'PX-01',
    );

    await provider.restoreFromCloud(records: [older, newer, newer]);

    expect(provider.allRecords, hasLength(2));
    expect(
      provider.recordsForSeason('VU-01').map((item) => item.id),
      ['CP-02', 'CP-01'],
    );
    expect(
      database.persisted.map((item) => item.id).toSet(),
      {'CP-01', 'CP-02'},
    );
    expect(provider.totalCost('VU-01'), 560000);
    expect(
      provider.byCategory('VU-01'),
      {
        ProductionCostCategory.fuel: 440000,
        ProductionCostCategory.material: 120000,
      },
    );

    final idsAfterRestore =
        provider.allRecords.map((item) => item.id).toList(growable: false);
    await provider.restoreFromCloud(records: const []);

    expect(provider.allRecords.map((item) => item.id), idsAfterRestore);
    expect(database.persisted, hasLength(2));
  });
}
