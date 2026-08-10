import 'package:flutter_test/flutter_test.dart';

import 'package:agrico_deepseek/models/production_cost_model.dart';
import 'package:agrico_deepseek/models/production_season_model.dart';
import 'package:agrico_deepseek/services/farm_cost_alert_service.dart';

void main() {
  group('ProductionSeasonModel', () {
    test('serializes and restores season-field relationship', () {
      final start = DateTime(2026, 8, 1);
      final harvest = DateTime(2026, 11, 1);
      final season = ProductionSeasonModel(
        id: 'season-001',
        fieldId: 'field-001',
        name: 'Vụ lạc 2026',
        crop: 'Lạc',
        variety: 'L14',
        startDate: start,
        expectedHarvestDate: harvest,
        status: 'Đang sản xuất',
        plannedArea: 10000,
        notes: 'Vụ kiểm thử',
      );

      final restored = ProductionSeasonModel.fromJson(season.toJson());

      expect(restored.id, 'season-001');
      expect(restored.fieldId, 'field-001');
      expect(restored.name, 'Vụ lạc 2026');
      expect(restored.crop, 'Lạc');
      expect(restored.variety, 'L14');
      expect(restored.startDate, start);
      expect(restored.expectedHarvestDate, harvest);
      expect(restored.plannedArea, 10000);
      expect(restored.notes, 'Vụ kiểm thử');
    });

    test('copyWith keeps the field relationship when fieldId is omitted', () {
      final season = ProductionSeasonModel(
        id: 'season-001',
        fieldId: 'field-001',
        name: 'Vụ cũ',
        crop: 'Lạc',
        variety: 'L14',
        startDate: DateTime(2026, 8, 1),
        expectedHarvestDate: null,
        status: 'Đang sản xuất',
        plannedArea: 10000,
      );

      final updated = season.copyWith(name: 'Vụ mới');

      expect(updated.fieldId, 'field-001');
      expect(updated.name, 'Vụ mới');
    });
  });

  group('FarmCostAlertRow', () {
    final season = ProductionSeasonModel(
      id: 'season-001',
      fieldId: 'field-001',
      name: 'Vụ lạc 2026',
      crop: 'Lạc',
      variety: 'L14',
      startDate: DateTime(2026, 8, 1),
      expectedHarvestDate: null,
      status: 'Đang sản xuất',
      plannedArea: 10000,
    );

    test('calculates cost per hectare and variance', () {
      final row = FarmCostAlertRow(
        season: season,
        areaHa: 1,
        actualTotal: 12000000,
        benchmarkTotal: 10000000,
        actualByCategory: const {
          ProductionCostCategory.material: 6000000,
          ProductionCostCategory.labor: 3000000,
          ProductionCostCategory.machine: 2000000,
          ProductionCostCategory.fuel: 1000000,
        },
      );

      expect(row.actualPerHa, 12000000);
      expect(row.benchmarkPerHa, 10000000);
      expect(row.variance, 2000000);
      expect(row.isOverBudget, isTrue);
      expect(row.isCritical, isTrue);
    });

    test('does not report over budget when actual cost is below benchmark', () {
      final row = FarmCostAlertRow(
        season: season,
        areaHa: 2,
        actualTotal: 8000000,
        benchmarkTotal: 10000000,
        actualByCategory: const {},
      );

      expect(row.actualPerHa, 4000000);
      expect(row.variance, -2000000);
      expect(row.isOverBudget, isFalse);
      expect(row.isCritical, isFalse);
    });

    test('identifies category contribution used by the cause analysis', () {
      final row = FarmCostAlertRow(
        season: season,
        areaHa: 1,
        actualTotal: 15000000,
        benchmarkTotal: 10000000,
        actualByCategory: const {
          ProductionCostCategory.material: 9000000,
          ProductionCostCategory.labor: 2500000,
          ProductionCostCategory.machine: 2000000,
          ProductionCostCategory.fuel: 1500000,
        },
      );

      final categories = row.actualByCategory.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      expect(categories.first.key, ProductionCostCategory.material);
      expect(categories.first.value, 9000000);
    });
  });
}
