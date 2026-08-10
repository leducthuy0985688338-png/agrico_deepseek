import 'package:flutter_test/flutter_test.dart';

import 'package:agrico_deepseek/models/production_cost_model.dart';
import 'package:agrico_deepseek/services/season_cost_driver_analysis_service.dart';

ProductionCostModel _cost({
  required String id,
  required String seasonId,
  required ProductionCostCategory category,
  required String itemName,
  required double amount,
}) {
  return ProductionCostModel(
    id: id,
    fieldId: 'FIELD-1',
    seasonId: seasonId,
    category: category,
    date: DateTime(2026, 1, 1),
    itemName: itemName,
    quantity: 1,
    unit: 'đơn vị',
    unitPrice: amount,
    amount: amount,
  );
}

void main() {
  group('SeasonCostDriverChange', () {
    test('calculates absolute and percentage change', () {
      const change = SeasonCostDriverChange(
        label: 'Phân bón',
        category: ProductionCostCategory.material,
        currentAmount: 1_500_000,
        previousAmount: 1_000_000,
      );

      expect(change.absoluteChange, 500000);
      expect(change.changeRate, 0.5);
    });

    test('handles a new driver with zero previous cost', () {
      const change = SeasonCostDriverChange(
        label: 'Dầu diesel',
        category: ProductionCostCategory.fuel,
        currentAmount: 800_000,
        previousAmount: 0,
      );

      expect(change.absoluteChange, 800000);
      expect(change.changeRate, 1);
    });
  });

  group('SeasonCostDriverAnalysis', () {
    test('exposes total delta and increasing drivers', () {
      const analysis = SeasonCostDriverAnalysis(
        currentSeasonId: 'CURRENT',
        previousSeasonId: 'PREVIOUS',
        currentTotal: 7_000_000,
        previousTotal: 5_000_000,
        categories: const [
          SeasonCostCategoryChange(
            category: ProductionCostCategory.material,
            currentAmount: 3_000_000,
            previousAmount: 2_000_000,
          ),
          SeasonCostCategoryChange(
            category: ProductionCostCategory.labor,
            currentAmount: 1_000_000,
            previousAmount: 1_500_000,
          ),
        ],
        drivers: const [
          SeasonCostDriverChange(
            label: 'Phân bón',
            category: ProductionCostCategory.material,
            currentAmount: 3_000_000,
            previousAmount: 2_000_000,
          ),
          SeasonCostDriverChange(
            label: 'Nhân công',
            category: ProductionCostCategory.labor,
            currentAmount: 1_000_000,
            previousAmount: 1_500_000,
          ),
        ],
      );

      expect(analysis.totalChange, 2_000_000);
      expect(analysis.totalChangeRate, 0.4);
      expect(analysis.increasingCategories.single.category,
          ProductionCostCategory.material);
      expect(analysis.increasingDrivers.single.label, 'Phân bón');
    });
  });

  test('ProductionCostModel data can be grouped by category and driver', () {
    final records = [
      _cost(
        id: '1',
        seasonId: 'PREVIOUS',
        category: ProductionCostCategory.material,
        itemName: 'Phân bón',
        amount: 1_000_000,
      ),
      _cost(
        id: '2',
        seasonId: 'CURRENT',
        category: ProductionCostCategory.material,
        itemName: 'Phân bón',
        amount: 1_500_000,
      ),
    ];

    final previous = records.where((item) => item.seasonId == 'PREVIOUS');
    final current = records.where((item) => item.seasonId == 'CURRENT');
    final previousTotal = previous.fold<double>(0, (sum, item) => sum + item.amount);
    final currentTotal = current.fold<double>(0, (sum, item) => sum + item.amount);

    expect(previousTotal, 1_000_000);
    expect(currentTotal - previousTotal, 500000);
  });
}
