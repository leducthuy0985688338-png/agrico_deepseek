import 'package:flutter_test/flutter_test.dart';

import 'package:agrico_deepseek/models/production_cost_model.dart';
import 'package:agrico_deepseek/providers/production_cost_provider.dart';
import 'package:agrico_deepseek/services/production_cost_database.dart';

class _FakeProductionCostDatabase extends ProductionCostDatabase {
  final Map<String, List<ProductionCostModel>> recordsBySeason;

  _FakeProductionCostDatabase(this.recordsBySeason);

  @override
  Future<List<ProductionCostModel>> getBySeason(String seasonId) async {
    return List.of(recordsBySeason[seasonId] ?? const []);
  }
}

void main() {
  test('loads and exposes production costs for multiple seasons', () async {
    final materialCost = ProductionCostModel(
      id: 'CP-01',
      fieldId: 'FIELD-01',
      seasonId: 'SEASON-01',
      category: ProductionCostCategory.material,
      date: DateTime(2026, 8, 1),
      itemName: 'Phân bón',
      quantity: 10,
      unit: 'kg',
      unitPrice: 15000,
      amount: 150000,
    );
    final fuelCost = ProductionCostModel(
      id: 'CP-02',
      fieldId: 'FIELD-02',
      seasonId: 'SEASON-02',
      category: ProductionCostCategory.fuel,
      date: DateTime(2026, 8, 2),
      itemName: 'Dầu Diesel',
      quantity: 20,
      unit: 'lít',
      unitPrice: 25000,
      amount: 500000,
    );
    final provider = ProductionCostProvider(
      database: _FakeProductionCostDatabase({
        'SEASON-01': [materialCost],
        'SEASON-02': [fuelCost],
      }),
    );

    await provider.loadForSeasons(['SEASON-01', 'SEASON-02']);

    expect(provider.recordsForSeason('SEASON-01'), [same(materialCost)]);
    expect(provider.recordsForSeason('SEASON-02'), [same(fuelCost)]);
    expect(provider.allRecords, containsAll([materialCost, fuelCost]));
    expect(provider.totalCost('SEASON-01'), 150000);
    expect(provider.totalCost('SEASON-02'), 500000);

    provider.dispose();
  });
}
