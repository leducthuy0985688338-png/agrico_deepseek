import 'package:flutter_test/flutter_test.dart';

import 'package:agrico_deepseek/models/production_cost_model.dart';
import 'package:agrico_deepseek/models/production_season_model.dart';
import 'package:agrico_deepseek/services/farm_cost_alert_service.dart';

void main() {
  ProductionSeasonModel season() => ProductionSeasonModel(
        id: 'S1',
        fieldId: 'F1',
        name: 'Vụ Lạc 2026',
        crop: 'Lạc',
        variety: 'Lạc đỏ',
        startDate: DateTime(2026, 1, 1),
        expectedHarvestDate: DateTime(2026, 5, 1),
        status: 'Đang sản xuất',
        plannedArea: 10000,
      );

  test('calculates variance, per-ha values and over-budget state', () {
    final row = FarmCostAlertRow(
      season: season(),
      areaHa: 1,
      actualTotal: 1_200_000,
      benchmarkTotal: 1_000_000,
      actualByCategory: const {},
    );

    expect(row.variance, 200000);
    expect(row.actualPerHa, 1200000);
    expect(row.benchmarkPerHa, 1000000);
    expect(row.isOverBudget, isTrue);
    expect(row.isCritical, isTrue);
  });

  test('does not flag a season below the benchmark', () {
    final row = FarmCostAlertRow(
      season: season(),
      areaHa: 2,
      actualTotal: 1_800_000,
      benchmarkTotal: 2_000_000,
      actualByCategory: const {
        ProductionCostCategory.material: 1_000_000,
        ProductionCostCategory.fuel: 800_000,
      },
    );

    expect(row.variance, -200000);
    expect(row.actualPerHa, 900000);
    expect(row.benchmarkPerHa, 1000000);
    expect(row.isOverBudget, isFalse);
    expect(row.isCritical, isFalse);
  });

  test('handles zero area safely', () {
    final row = FarmCostAlertRow(
      season: season(),
      areaHa: 0,
      actualTotal: 500000,
      benchmarkTotal: 0,
      actualByCategory: const {},
    );

    expect(row.actualPerHa, 0);
    expect(row.benchmarkPerHa, 0);
    expect(row.isOverBudget, isTrue);
    expect(row.isCritical, isFalse);
  });
}
