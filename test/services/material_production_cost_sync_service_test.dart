import 'package:agrico_deepseek/models/production_cost_model.dart';
import 'package:agrico_deepseek/services/material_production_cost_sync_service.dart';
import 'package:agrico_deepseek/services/production_cost_database.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryCosts extends ProductionCostDatabase {
  final Map<String, ProductionCostModel> records = {};
  int writes = 0;

  @override
  Future<ProductionCostModel?> getBySource(String source, String sourceId) async =>
      records['$source:$sourceId'];

  @override
  Future<void> upsert(ProductionCostModel record) async {
    writes++;
    records['${record.source}:${record.sourceId}'] = record;
  }
}

void main() {
  test('retry preserves the first material issue cost snapshot', () async {
    final costs = _MemoryCosts();
    final service = MaterialProductionCostSyncService(costDatabase: costs);
    Future<ProductionCostModel?> deliver(double price, double quantity) =>
        service.syncExport(
          transactionId: 'issue-1',
          itemId: 'material-1',
          itemName: 'Fertilizer',
          unit: 'kg',
          quantity: quantity,
          unitPrice: price,
          fieldId: 'field-1',
          seasonId: 'season-1',
          date: DateTime.utc(2026, 10, 18),
        );
    final original = await deliver(20, 5);
    final replay = await deliver(100, 9);
    expect(costs.writes, 1);
    expect(replay?.id, original?.id);
    expect(replay?.quantity, 5);
    expect(replay?.unitPrice, 20);
    expect(replay?.amount, 100);
  });

  test('invalid unit price does not write a material cost', () async {
    final costs = _MemoryCosts();
    final service = MaterialProductionCostSyncService(costDatabase: costs);
    await expectLater(
      service.syncExport(
        transactionId: 'issue-invalid',
        itemId: 'material-1',
        itemName: 'Fertilizer',
        unit: 'kg',
        quantity: 2,
        unitPrice: double.nan,
        fieldId: 'field-1',
        seasonId: 'season-1',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(costs.writes, 0);
  });
}
